extends Node
## Proximity voice chat. Owner: S12 (v2). NET: runs on every peer; each peer plays what it receives.
## Both Steam and ENet modes capture 16 kHz mono from Godot's mic (direct input API) and send it as
## IMA ADPCM (4 bit, ~66 kbit/s, see core/voice/voice_adpcm.gd). RAW 16-bit PCM (256 kbit/s) is the fallback:
## `use_compression = false` or `--voice-raw`. Receivers always decode every codec.
## (Steam's own getVoice() returned no data in testing, so it is no longer used for sending;
## STEAM codec packets are still decoded on receive for compatibility.)
## F4 / --voice-loopback: hear your own mic locally (tests playback on one machine).
## Packets go over Godot RPC (unreliable_ordered, channel 2), so both transports share one path.
## Public API for the game (core/ knows nothing about mages or death):
##   register_speaker(peer, player, node) / unregister_speaker(peer), `listener` = local player/camera,
##   set_speaker_effect(peer, preset, strength)   per-speaker distortion / pitch-down / reverb (core/voice/voice_fx.gd),
##   set_voice_group(peer, group) + `voice_rules`  who hears whom (data-driven table below),
##   tx_kbps / rx_kbps / status_line()             bandwidth stats for the F3 overlay.
# WHY: voices were too quiet in playtests and were fixed (MIC_GAIN, full/silent distance, max_distance = 0).
# CONTRACT: do not lower MIC_GAIN, full_volume_distance or silent_distance, or re-enable max_distance, without the user.

const VoiceAdpcm := preload("res://core/voice/voice_adpcm.gd")
const VoiceFx := preload("res://core/voice/voice_fx.gd")

enum Codec { RAW_PCM16 = 0, STEAM = 1, ADPCM = 2 }

const GROUP_ALIVE := &"alive"
const GROUP_DEAD := &"dead"
## Hearing rules: RULES[speaker_group][listener_group] = multiplier on the falloff distances.
## 1.0 = normal proximity, 0.0 = cannot hear, RULE_GLOBAL = heard at full volume at any distance.
## Missing entries mean 1.0. The GDD says living and dead both use proximity chat at the same range;
## dead players also hear each other everywhere so the dead can coordinate.
const RULE_GLOBAL := INF
# TUNE: edit this table (or call set_voice_rule at runtime) to change who hears whom.
const DEFAULT_RULES := {
	GROUP_ALIVE: {GROUP_ALIVE: 1.0, GROUP_DEAD: 1.0},
	GROUP_DEAD: {GROUP_ALIVE: 1.0, GROUP_DEAD: RULE_GLOBAL},
}

const RAW_RATE := 16000
const STEAM_RATE := 24000
const RAW_CHUNK := 320 ## samples per packet (20 ms at 16 kHz, 640 bytes: fits one Steam/ENet datagram)
# FIX(S08, Codex): raw mic PCM had no gain, making loopback and remote speech faint.
const MIC_GAIN := 12.0 # TUNE: +21.6 dB capture gain; clamp before PCM quantization.
const OPEN_MIC_GATE := 0.04 ## peak level that opens the open-mic gate
const GATE_HOLD := 0.35 ## seconds the gate stays open after speech
const SPEAKING_TIMEOUT := 0.3
# Silence suppression: chunks quieter than this (raw mic, before gain) are not sent after the hang time.
const SILENCE_PEAK := 0.003 # TUNE
const SILENCE_HANG_CHUNKS := 12 ## 240 ms of silence still sent so word endings are not clipped
# Jitter buffer: playback starts once this much audio is queued, and restarts after an underrun.
const JITTER_PREBUFFER := 0.06 # TUNE seconds
const JITTER_MAX_QUEUE := 0.30 # TUNE seconds; older audio is dropped beyond this so latency stays bounded
const FADE_IN_FRAMES := 64

## Tunable falloff: full volume inside full_volume_distance, silent at silent_distance (gentle quadratic fade between).
var full_volume_distance := 8.0
var silent_distance := 45.0
var push_to_talk := true
var ptt_key: Key = KEY_V
var enable_raw_voice := true
var loopback := false ## play own mic locally (debug)
var use_compression := true ## false = RAW 16-bit PCM
var voice_rules: Dictionary = DEFAULT_RULES.duplicate(true) ## see DEFAULT_RULES
var tx_kbps := 0.0 ## voice payload sent, kbit/s (updated once a second)
var rx_kbps := 0.0 ## voice payload received, kbit/s
var chunks_suppressed := 0 ## silent chunks not sent (diagnostics/tests)
var underruns := 0 ## jitter buffer ran dry (diagnostics)

var mic_level := 0.0 ## 0..1, Godot mic (for the meter)
var local_speaking := false
var packets_sent := 0
var packets_received := 0
var mic_peak_seen := 0.0 ## loudest mic sample since start (diagnostics/tests)
var frames_played := 0 ## decoded samples pushed to speakers (diagnostics/tests)
var listener: Node3D ## local player; distances are measured from here

var _speakers := {} ## peer_id -> {player, node, rate, last, queue, queued, buffering, fade, bus} (HUD reads `last`)
var _groups := {} ## peer_id -> StringName voice group
var _effects := {} ## peer_id -> {preset, strength}
var _tx_bytes := 0
var _rx_bytes := 0
var _stat_timer := 0.0
var _silent_chunks := 0
var _headless := false
var _mic_active := false
var _mic_restart_id := 0
var _mic_started := false
var _last_local_voice := -10.0
var _gate_timer := 0.0
var _rs_pos := 0.0
var _rs_acc := 0.0
var _rs_count := 0
var _pending := PackedFloat32Array()
var _loop_sp := {}
var _f4_was_down := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	loopback = NetworkManager.args.has("voice-loopback")
	use_compression = not NetworkManager.args.has("voice-raw")
	var lp := AudioStreamPlayer.new()
	lp.name = "LoopbackPlayer"
	add_child(lp)
	_loop_sp = _new_speaker(lp, null)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.peer_left.connect(_on_peer_left)
	# Deferred so the menu can apply the saved mic device first (no restart at startup).
	_setup_mic.call_deferred()


func _setup_mic() -> void:
	# Godot 4.5+ direct mic API: no AudioStreamMicrophone / capture bus needed.
	# (The old bus approach captured nothing when routed into a muted bus.)
	_mic_started = true
	if _headless:
		return
	var err := AudioServer.set_input_device_active(true)
	_mic_active = err == OK
	print("[Voice] mic '%s' active=%s (%s) rate=%d" % [AudioServer.input_device, _mic_active, error_string(err), AudioServer.get_input_mix_rate()])


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func set_input_device(device: String) -> void:
	if device == AudioServer.input_device:
		return # restarting the same device crashed Godot's WASAPI driver on Windows
	if _headless or not _mic_started:
		AudioServer.input_device = device # mic not started yet: just pick the device
		return
	# Stop -> switch -> start a moment later; switching while active / restarting instantly crashed on Windows.
	_mic_active = false
	AudioServer.set_input_device_active(false)
	AudioServer.input_device = device
	_mic_restart_id += 1
	var my_id := _mic_restart_id
	await get_tree().create_timer(0.5).timeout
	if my_id == _mic_restart_id: # ignore if another switch happened meanwhile
		_setup_mic()


func voice_mode_name() -> String:
	match NetworkManager.mode:
		NetworkManager.Mode.STEAM, NetworkManager.Mode.ENET:
			if not enable_raw_voice:
				return "Off"
			return "ADPCM 4-bit 16 kHz" if use_compression else "Raw PCM 16 kHz"
	return "Idle"


## One-line stats for the F3 overlay.
func status_line() -> String:
	return "Voice bandwidth: tx %.1f kbit/s  rx %.1f kbit/s  (raw would be %.0f)  suppressed: %d  underruns: %d" % [
		tx_kbps, rx_kbps, RAW_RATE * 16 / 1000.0, chunks_suppressed, underruns]


## Game hook: a remote player's AudioStreamPlayer3D `player` located at `node`.
func register_speaker(peer_id: int, player: AudioStreamPlayer3D, node: Node3D) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	# WHY: max_distance adds its own linear attenuation even with attenuation disabled.
	player.max_distance = 0.0
	player.volume_db = -80.0
	_speakers[peer_id] = _new_speaker(player, node)
	if _effects.has(peer_id):
		_apply_effect(peer_id)


func unregister_speaker(peer_id: int) -> void:
	var sp: Dictionary = _speakers.get(peer_id, {})
	if sp.has("bus"):
		if is_instance_valid(sp["player"]):
			sp["player"].bus = &"Master"
		VoiceFx.free_bus(sp["bus"])
	_speakers.erase(peer_id)


## Game hook: set a speaker's voice effect. `preset` is a key of VoiceFx.PRESETS ("mage", "deep", "distort",
## "cave", "none"); `strength` 0..1 scales it (0 = clean). Stays active across re-registration until cleared.
func set_speaker_effect(peer_id: int, preset: StringName, strength: float) -> void:
	if preset == &"none" or strength <= 0.0:
		_effects.erase(peer_id)
	else:
		_effects[peer_id] = {"preset": preset, "strength": clampf(strength, 0.0, 1.0)}
	_apply_effect(peer_id)


## Remove every speaker effect (e.g. at round end).
func clear_speaker_effects() -> void:
	var ids := _effects.keys()
	_effects.clear()
	for id in ids:
		_apply_effect(id)


## Game hook: put a peer in a voice group (default groups: "alive", "dead"). The local peer's group decides what
## it hears; its group is also sent with every packet so remote peers know it. Call it for the LOCAL peer;
## for a remote peer the value is replaced by whatever that peer's next packets say.
func set_voice_group(peer_id: int, group: StringName) -> void:
	_groups[peer_id] = group


func get_voice_group(peer_id: int) -> StringName:
	return _groups.get(peer_id, GROUP_ALIVE)


## Change one rule at runtime (see DEFAULT_RULES for the meaning of `scale`).
func set_voice_rule(speaker_group: StringName, listener_group: StringName, scale: float) -> void:
	if not voice_rules.has(speaker_group):
		voice_rules[speaker_group] = {}
	voice_rules[speaker_group][listener_group] = scale


## Distance multiplier for a speaker group heard by a listener group (1.0 = normal).
func rule_scale(speaker_group: StringName, listener_group: StringName) -> float:
	return float(voice_rules.get(speaker_group, {}).get(listener_group, 1.0))


func _new_speaker(player: Node, node: Node3D) -> Dictionary:
	return {"player": player, "node": node, "rate": 0, "last": -10.0,
		"queue": [], "queued": 0, "buffering": true, "fade": false}


func _apply_effect(peer_id: int) -> void:
	var sp: Dictionary = _speakers.get(peer_id, {})
	if sp.is_empty() or not is_instance_valid(sp["player"]):
		return
	var fx: Dictionary = _effects.get(peer_id, {})
	if fx.is_empty():
		if sp.has("bus"):
			VoiceFx.apply(sp["bus"], &"none", 0.0)
		return
	if not sp.has("bus"):
		sp["bus"] = VoiceFx.ensure_bus(peer_id)
		sp["player"].bus = sp["bus"]
	VoiceFx.apply(sp["bus"], fx["preset"], fx["strength"])


func _on_session_ended(_reason: String) -> void:
	clear_speaker_effects()
	_groups.clear()


func _on_peer_left(peer_id: int) -> void:
	_effects.erase(peer_id)
	_groups.erase(peer_id)


# ---------------------------------------------------------------- capture / send

func _process(delta: float) -> void:
	var buf := PackedVector2Array()
	var n := AudioServer.get_input_frames_available() if _mic_active else 0
	if n > 0:
		buf = AudioServer.get_input_frames(n)
	var peak := 0.0
	for f in buf:
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	mic_level = maxf(peak, mic_level - delta * 1.5)
	mic_peak_seen = maxf(mic_peak_seen, peak)

	var in_session := NetworkManager.is_in_session()
	var now := Time.get_ticks_msec() / 1000.0
	var ptt_down := Input.is_physical_key_pressed(ptt_key) and not _text_has_focus()

	var f4 := Input.is_physical_key_pressed(KEY_F4)
	if f4 and not _f4_was_down:
		loopback = not loopback
		print("[Voice] loopback=%s" % loopback)
	_f4_was_down = f4

	if (in_session or loopback) and enable_raw_voice:
		if NetworkManager.args.has("test-voice"): # headless test: synthetic 440 Hz tone instead of the mic
			buf = _test_tone(n if n > 0 else int(_input_rate() * delta))
			ptt_down = true
		var want := ptt_down
		if not push_to_talk:
			_gate_timer = GATE_HOLD if peak > OPEN_MIC_GATE else _gate_timer - delta
			want = _gate_timer > 0.0
		if NetworkManager.args.has("test-voice"):
			want = true
		if want:
			_raw_encode(buf)
		else:
			_reset_raw()
		local_speaking = want
	else:
		_reset_raw()
		local_speaking = false

	_update_speakers(now)
	_pump_jitter()
	_stat_timer += delta
	if _stat_timer >= 1.0:
		tx_kbps = _tx_bytes * 8.0 / _stat_timer / 1000.0
		rx_kbps = _rx_bytes * 8.0 / _stat_timer / 1000.0
		if NetworkManager.args.has("test-voice") and _tx_bytes > 0:
			print("[Voice] codec=%s tx=%.1f kbit/s (raw 256)" % [Codec.keys()[Codec.values().find(_send_codec())], tx_kbps])
		_tx_bytes = 0
		_rx_bytes = 0
		_stat_timer = 0.0


var _tone_phase := 0.0
func _test_tone(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var step := TAU * 440.0 / _input_rate()
	for i in frames:
		var v := sin(_tone_phase) * 0.3
		out[i] = Vector2(v, v)
		_tone_phase = fmod(_tone_phase + step, TAU)
	return out


func _input_rate() -> float:
	var r := AudioServer.get_input_mix_rate()
	return r if r > 0.0 else AudioServer.get_mix_rate()


func _text_has_focus() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


func _raw_encode(buf: PackedVector2Array) -> void:
	var ratio := _input_rate() / RAW_RATE
	for f in buf:
		_rs_acc += (f.x + f.y) * 0.5
		_rs_count += 1
		_rs_pos += 1.0
		if _rs_pos >= ratio:
			_rs_pos -= ratio
			_pending.append(_rs_acc / _rs_count) # box-filter downsample
			_rs_acc = 0.0
			_rs_count = 0
			if _pending.size() >= RAW_CHUNK:
				_emit_chunk(_pending)
				_pending.clear()


func _reset_raw() -> void:
	if _pending.size() > 0:
		_emit_chunk(_pending) # flush the tail of the sentence
		_pending.clear()
	_silent_chunks = 0
	_rs_pos = 0.0
	_rs_acc = 0.0
	_rs_count = 0


func _send_codec() -> int:
	return Codec.ADPCM if use_compression else Codec.RAW_PCM16


## Silence-suppress, encode with the active codec and send one chunk of 16 kHz mono floats.
func _emit_chunk(samples: PackedFloat32Array) -> void:
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	if peak < SILENCE_PEAK:
		_silent_chunks += 1
		if _silent_chunks > SILENCE_HANG_CHUNKS:
			chunks_suppressed += 1
			return
	else:
		_silent_chunks = 0
	if use_compression:
		# Apply the same capture gain as the RAW path BEFORE quantising to 4 bits.
		var gained := PackedFloat32Array()
		gained.resize(samples.size())
		for i in samples.size():
			gained[i] = clampf(samples[i] * MIC_GAIN, -1.0, 1.0)
		_send(VoiceAdpcm.encode(gained), Codec.ADPCM)
	else:
		_send(_encode_pcm16(samples), Codec.RAW_PCM16)


func _encode_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i] * MIC_GAIN, -1.0, 1.0) * 32767.0))
	return b


func _send(data: PackedByteArray, codec: int) -> void:
	if loopback:
		_enqueue(_loop_sp, _pcm_to_frames(_decode(data, codec)), RAW_RATE)
	if NetworkManager.is_in_session():
		_voice_packet.rpc(data, codec, String(get_voice_group(multiplayer.get_unique_id())))
		packets_sent += 1
		_tx_bytes += data.size()


# ---------------------------------------------------------------- receive / playback

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _voice_packet(data: PackedByteArray, codec: int, group: String = "alive") -> void:
	packets_received += 1
	_rx_bytes += data.size()
	var sender := multiplayer.get_remote_sender_id()
	_groups[sender] = StringName(group) # the sender's own group travels with its packets
	var sp: Dictionary = _speakers.get(sender, {})
	if sp.is_empty():
		return
	if rule_scale(StringName(group), get_voice_group(multiplayer.get_unique_id())) <= 0.0:
		return # muted by the rule table: skip decoding
	var rate := STEAM_RATE if codec == Codec.STEAM else RAW_RATE
	_enqueue(sp, _pcm_to_frames(_decode(data, codec)), rate)


## Any codec -> mono floats. Empty on failure.
func _decode(data: PackedByteArray, codec: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	match codec:
		Codec.ADPCM:
			return VoiceAdpcm.decode(data)
		Codec.RAW_PCM16:
			out.resize(data.size() / 2)
			for i in out.size():
				out[i] = data.decode_s16(i * 2) / 32768.0
		Codec.STEAM:
			if not SteamManager.available:
				return out
			var d: Dictionary = Steam.decompressVoice(data, STEAM_RATE)
			if int(d.get("result", -1)) != Steam.VOICE_RESULT_OK:
				return out
			var pcm: PackedByteArray = d.get("uncompressed", PackedByteArray())
			pcm = pcm.slice(0, int(d.get("size", pcm.size())))
			out.resize(pcm.size() / 2)
			for i in out.size():
				out[i] = pcm.decode_s16(i * 2) / 32768.0
	return out


func _pcm_to_frames(mono: PackedFloat32Array) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(mono.size())
	for i in mono.size():
		frames[i] = Vector2(mono[i], mono[i])
	return frames


## Jitter buffer input: queue decoded frames; _pump_jitter() feeds them to the speaker's stream.
func _enqueue(sp: Dictionary, frames: PackedVector2Array, rate: int) -> void:
	var player = sp["player"] # AudioStreamPlayer3D, or AudioStreamPlayer for loopback
	if not is_instance_valid(player) or frames.is_empty():
		return
	if sp["rate"] != rate or not player.playing:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = rate
		gen.buffer_length = 0.5
		player.stream = gen
		player.play()
		sp["rate"] = rate
		sp["queue"] = []
		sp["queued"] = 0
		sp["buffering"] = true
	sp["queue"].append(frames)
	sp["queued"] += frames.size()
	# Bound the latency: after a stall, drop the oldest audio instead of playing it late.
	var max_frames := int(rate * JITTER_MAX_QUEUE)
	while sp["queued"] > max_frames and sp["queue"].size() > 1:
		sp["queued"] -= (sp["queue"].pop_front() as PackedVector2Array).size()
	sp["last"] = Time.get_ticks_msec() / 1000.0


func _pump_jitter() -> void:
	for id in _speakers:
		_pump_one(_speakers[id])
	_pump_one(_loop_sp)


func _pump_one(sp: Dictionary) -> void:
	var rate: int = sp.get("rate", 0)
	var player = sp.get("player")
	if rate == 0 or not is_instance_valid(player):
		return
	var pb := player.call("get_stream_playback") as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var queue: Array = sp["queue"]
	if sp["buffering"]:
		if sp["queued"] < int(rate * JITTER_PREBUFFER):
			return # still filling the jitter buffer
		sp["buffering"] = false
		sp["fade"] = true
	elif queue.is_empty():
		# Generator drained and nothing queued: underrun, so prebuffer again before the next burst.
		var buffered := int(0.5 * rate) - pb.get_frames_available()
		if buffered <= 0:
			sp["buffering"] = true
			underruns += 1
		return
	while not queue.is_empty():
		var chunk: PackedVector2Array = queue[0]
		if pb.get_frames_available() < chunk.size():
			break
		queue.pop_front()
		sp["queued"] -= chunk.size()
		if sp["fade"]:
			sp["fade"] = false
			for i in mini(FADE_IN_FRAMES, chunk.size()): # soft start: no click when speech begins
				chunk[i] *= float(i) / FADE_IN_FRAMES
		pb.push_buffer(chunk)
		frames_played += chunk.size()


func _update_speakers(now: float) -> void:
	var from: Vector3
	if is_instance_valid(listener) and listener.is_inside_tree():
		from = listener.global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		from = cam.global_position
	var listener_group := get_voice_group(multiplayer.get_unique_id() if NetworkManager.is_in_session() else 1)
	for id in _speakers:
		var sp: Dictionary = _speakers[id]
		var node: Node3D = sp["node"]
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var scale := rule_scale(get_voice_group(id), listener_group)
		var vol := 1.0
		if scale <= 0.0:
			vol = 0.0
		elif not is_inf(scale):
			var d := node.global_position.distance_to(from)
			var full := full_volume_distance * scale
			var fade := clampf((d - full) / maxf(0.001, silent_distance * scale - full), 0.0, 1.0)
			vol = 1.0 - fade * fade
		sp["player"].volume_db = linear_to_db(maxf(vol, 0.0001))
		if node.has_method("set_speaking"):
			node.set_speaking(now - float(sp["last"]) < SPEAKING_TIMEOUT)
