extends Node
## Proximity voice chat. Owner: S12 (v2), v3 transport by the voice-upgrade session.
## NET: runs on every peer; each peer plays what it receives.
## Both Steam and ENet modes capture 16 kHz mono from Godot's mic (direct input API) and send it as
## IMA ADPCM (4 bit, ~66 kbit/s, see core/voice/voice_adpcm.gd). RAW 16-bit PCM (256 kbit/s) is the fallback:
## `use_compression = false` or `--voice-raw`. Receivers always decode every codec.
## (Steam's own getVoice() returned no data in testing, so it is not used.)
## F4 / --voice-loopback: hear your own mic locally (tests playback on one machine).
## Transport v3 (loss-tolerant, for online play): packets go over Godot RPC (UNRELIABLE, channel 2) and carry
##   a sequence number plus a low-rate (8 kHz ADPCM) copy of the previous chunk (`use_fec`, off with --voice-no-fec).
##   Receivers reorder by sequence, rebuild a lost chunk from the next packet's copy, conceal what is still missing
##   (mirrored repeat that fades out) and size the jitter buffer from measured arrival jitter (60..250 ms).
##   # WHY: unreliable_ordered silently dropped every packet that arrived out of order, and one lost 20 ms
##   packet was an audible hole; over the internet both happen all the time.
## Public API for the game (core/ knows nothing about mages or death):
##   register_speaker(peer, player, node) / unregister_speaker(peer), `listener` = local player/camera,
##   set_speaker_effect(peer, preset, strength)   per-speaker distortion / pitch-down / reverb (core/voice/voice_fx.gd),
##   set_voice_group(peer, group) + `voice_rules`  who hears whom (data-driven table below),
##   tx_kbps / rx_kbps / status_line()             bandwidth and loss stats for the F3 overlay.
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
const RAW_CHUNK := 320 ## samples per packet (20 ms at 16 kHz, 640 bytes: fits one Steam/ENet datagram)
# FIX(S08, Codex): raw mic PCM had no gain, making loopback and remote speech faint.
const MIC_GAIN := 12.0 # TUNE: +21.6 dB capture gain; clamp before PCM quantization.
const OPEN_MIC_GATE := 0.04 ## peak level that opens the open-mic gate
const GATE_HOLD := 0.35 ## seconds the gate stays open after speech
const SPEAKING_TIMEOUT := 0.3
# Silence suppression: chunks quieter than this (raw mic, before gain) are not sent after the hang time.
const SILENCE_PEAK := 0.003 # TUNE
const SILENCE_HANG_CHUNKS := 12 ## 240 ms of silence still sent so word endings are not clipped
const CHUNK_SEC := float(RAW_CHUNK) / RAW_RATE
# Jitter buffer: playback starts once `target` seconds are queued (adaptive), and restarts after an underrun.
const JITTER_PREBUFFER := 0.06 # TUNE seconds: minimum target (LAN)
const JITTER_TARGET_MAX := 0.25 # TUNE seconds: target ceiling on a very jittery connection
const JITTER_K := 3.0 # TUNE: target = JITTER_PREBUFFER + JITTER_K * measured jitter
const JITTER_MAX_QUEUE := 0.30 # TUNE seconds above target; older audio is dropped so latency stays bounded
const FADE_IN_FRAMES := 64
const PLC_MAX := 4 # TUNE: concealed chunks in a row (80 ms) before skipping ahead to the next real audio
const PLC_DECAY := 0.55 # TUNE: gain per concealed chunk
const GEN_LENGTH := 0.5 ## AudioStreamGenerator buffer seconds

## Tunable falloff: full volume inside full_volume_distance, silent at silent_distance (gentle quadratic fade between).
var full_volume_distance := 8.0
var silent_distance := 45.0
var push_to_talk := true
var ptt_key: Key = KEY_V
var enable_raw_voice := true
var loopback := false ## play own mic locally (debug)
var use_compression := true ## false = RAW 16-bit PCM
var use_fec := true ## send a low-rate copy of the previous chunk in every packet (recovers single losses)
var voice_rules: Dictionary = DEFAULT_RULES.duplicate(true) ## see DEFAULT_RULES
var tx_kbps := 0.0 ## voice payload sent, kbit/s (updated once a second)
var rx_kbps := 0.0 ## voice payload received, kbit/s
var chunks_suppressed := 0 ## silent chunks not sent (diagnostics/tests)
var underruns := 0 ## jitter buffer ran dry (diagnostics)
var packets_recovered := 0 ## lost chunks rebuilt from the next packet's redundant copy
var packets_late := 0 ## arrived after their play slot (dropped)
var frames_concealed := 0 ## samples of packet-loss concealment played

var mic_level := 0.0 ## 0..1, Godot mic (for the meter)
## User mic volume (settings slider), multiplies MIC_GAIN. 1.0 = default; MIC_GAIN itself stays the contract.
# FIX(S18, Claude): user asked for a mic volume setting; default 1.0 keeps the S12 loudness contract.
var mic_volume := 1.0
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
var _seq := 0 ## next outgoing sequence number
var _prev_red := PackedByteArray() ## 8 kHz copy of the last sent chunk (rides in the next packet)
var _loop_sp := {}
var _f4_was_down := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	loopback = NetworkManager.args.has("voice-loopback")
	use_compression = not NetworkManager.args.has("voice-raw")
	use_fec = not NetworkManager.args.has("voice-no-fec")
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
			return ("ADPCM 4-bit 16 kHz" if use_compression else "Raw PCM 16 kHz") + (" + FEC" if use_fec else "")
	return "Idle"


## One-line stats for the F3 overlay.
func status_line() -> String:
	var jit := 0.0
	for id in _speakers:
		jit = maxf(jit, float(_speakers[id].get("target", 0.0)))
	return ("Voice: tx %.1f kbit/s  rx %.1f kbit/s  suppressed %d  underruns %d\n"
		+ "Voice loss: recovered %d  late %d  concealed %.1f s  buffer %d ms") % [
		tx_kbps, rx_kbps, chunks_suppressed, underruns, packets_recovered, packets_late,
		frames_concealed / float(RAW_RATE), int(jit * 1000.0)]


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
	return {"player": player, "node": node, "rate": 0, "last": -10.0, "cap": -1,
		"pending": {}, "red": {}, "next": -1, "buffering": true, "fade": false, "first_arrival": 0.0,
		"last_chunk": PackedFloat32Array(), "plc": 0, "jitter": 0.0, "target": JITTER_PREBUFFER,
		"arr_time": -10.0, "arr_seq": -1}


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
	_prev_red = PackedByteArray() # talk spurt over: the next packet has no neighbour to protect
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
			_prev_red = PackedByteArray()
			return
	else:
		_silent_chunks = 0
	# Apply the capture gain BEFORE quantising (4-bit ADPCM or 16-bit PCM).
	var gained := PackedFloat32Array()
	gained.resize(samples.size())
	for i in samples.size():
		gained[i] = clampf(samples[i] * MIC_GAIN * mic_volume, -1.0, 1.0)
	if use_compression:
		_send(VoiceAdpcm.encode(gained), Codec.ADPCM, gained)
	else:
		_send(_encode_pcm16(samples), Codec.RAW_PCM16, gained)


func _encode_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i] * MIC_GAIN * mic_volume, -1.0, 1.0) * 32767.0))
	return b


## Half-rate ADPCM copy of a chunk (pairs averaged): ~83 bytes for 20 ms. Used as forward error correction.
static func encode_redundant(gained: PackedFloat32Array) -> PackedByteArray:
	var half := PackedFloat32Array()
	half.resize(gained.size() / 2)
	for i in half.size():
		half[i] = (gained[i * 2] + gained[i * 2 + 1]) * 0.5
	return VoiceAdpcm.encode(half)


## Inverse of encode_redundant: back to 16 kHz by linear interpolation.
static func decode_redundant(data: PackedByteArray) -> PackedFloat32Array:
	var half := VoiceAdpcm.decode(data)
	var out := PackedFloat32Array()
	out.resize(half.size() * 2)
	for i in half.size():
		var nxt := half[i + 1] if i + 1 < half.size() else half[i]
		out[i * 2] = half[i]
		out[i * 2 + 1] = (half[i] + nxt) * 0.5
	return out


func _send(data: PackedByteArray, codec: int, gained: PackedFloat32Array) -> void:
	var seq := _seq
	_seq += 1
	var red := _prev_red
	_prev_red = encode_redundant(gained) if use_fec else PackedByteArray()
	if loopback:
		_receive(_loop_sp, seq, _decode(data, codec), red)
	if NetworkManager.is_in_session():
		_voice_packet.rpc(seq, data, codec, red, String(get_voice_group(multiplayer.get_unique_id())))
		packets_sent += 1
		_tx_bytes += data.size() + red.size() + 6


# ---------------------------------------------------------------- receive / playback

# NET: sender -> everyone. UNRELIABLE (not ordered): the receiver reorders by `seq` itself.
# `red` = encode_redundant() of chunk seq-1 (empty if FEC is off or seq-1 was not speech).
@rpc("any_peer", "call_remote", "unreliable", 2)
func _voice_packet(seq: int, data: PackedByteArray, codec: int, red: PackedByteArray, group: String = "alive") -> void:
	packets_received += 1
	_rx_bytes += data.size() + red.size() + 6
	var sender := multiplayer.get_remote_sender_id()
	_groups[sender] = StringName(group) # the sender's own group travels with its packets
	var sp: Dictionary = _speakers.get(sender, {})
	if sp.is_empty():
		return
	if rule_scale(StringName(group), get_voice_group(multiplayer.get_unique_id())) <= 0.0:
		return # muted by the rule table: skip decoding
	_receive(sp, seq, _decode(data, codec), red)


## Any codec -> mono floats. Empty on failure. (Codec.STEAM is no longer sent and decodes to nothing.)
func _decode(data: PackedByteArray, codec: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	match codec:
		Codec.ADPCM:
			return VoiceAdpcm.decode(data)
		Codec.RAW_PCM16:
			out.resize(data.size() / 2)
			for i in out.size():
				out[i] = data.decode_s16(i * 2) / 32768.0
	return out


## Jitter buffer input: file a decoded chunk (and the redundant copy of the one before it) under its sequence.
func _receive(sp: Dictionary, seq: int, mono: PackedFloat32Array, red: PackedByteArray) -> void:
	var player = sp["player"] # AudioStreamPlayer3D, or AudioStreamPlayer for loopback
	if not is_instance_valid(player) or mono.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if sp["rate"] != RAW_RATE or not player.playing:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RAW_RATE
		gen.buffer_length = GEN_LENGTH
		player.stream = gen
		player.play()
		sp["rate"] = RAW_RATE
		sp["cap"] = -1
		sp["pending"] = {}
		sp["red"] = {}
		sp["buffering"] = true
	sp["last"] = now
	# Arrival jitter (RFC 3550 style): how far arrivals stray from the 20 ms cadence. Gaps > 0.5 s are new talk spurts.
	var gap := now - float(sp["arr_time"])
	if seq > int(sp["arr_seq"]):
		if int(sp["arr_seq"]) >= 0 and gap < 0.5:
			var d := absf(gap - (seq - int(sp["arr_seq"])) * CHUNK_SEC)
			sp["jitter"] = float(sp["jitter"]) + (minf(d, 0.5) - float(sp["jitter"])) / 16.0
		sp["arr_time"] = now
		sp["arr_seq"] = seq
	sp["target"] = clampf(JITTER_PREBUFFER + JITTER_K * float(sp["jitter"]), JITTER_PREBUFFER, JITTER_TARGET_MAX)
	var pending: Dictionary = sp["pending"]
	var playing: bool = not sp["buffering"]
	if seq < int(sp["next"]) and int(sp["next"]) - seq < 1000: # (a far older seq = the sender restarted)
		packets_late += 1
		return # its slot already played (or was concealed)
	if pending.is_empty() and sp["buffering"]:
		sp["first_arrival"] = now
	pending[seq] = mono
	var red_set: Dictionary = sp["red"]
	red_set.erase(seq) # the real chunk replaces a rebuilt one
	if not red.is_empty() and not pending.has(seq - 1) and (not playing or seq - 1 >= int(sp["next"])):
		var back := decode_redundant(red)
		if back.size() == RAW_CHUNK:
			pending[seq - 1] = back
			red_set[seq - 1] = true # counted as recovered when it actually plays
	# Bound latency: drop the oldest audio beyond target + JITTER_MAX_QUEUE.
	var max_chunks := int((float(sp["target"]) + JITTER_MAX_QUEUE) / CHUNK_SEC)
	if pending.size() > max_chunks:
		while pending.size() > max_chunks:
			var oldest := _min_key(pending)
			pending.erase(oldest)
			red_set.erase(oldest)
		if playing:
			sp["next"] = _min_key(pending)


static func _min_key(d: Dictionary) -> int:
	var m := 1 << 62
	for k in d:
		m = mini(m, int(k))
	return m


func _pump_jitter() -> void:
	for id in _speakers:
		_pump_one(_speakers[id])
	_pump_one(_loop_sp)


## Jitter buffer output: keep about `target` seconds in the generator, in sequence order, concealing holes.
func _pump_one(sp: Dictionary) -> void:
	var player = sp.get("player")
	if int(sp.get("rate", 0)) == 0 or not is_instance_valid(player):
		return
	var pb := player.call("get_stream_playback") as AudioStreamGeneratorPlayback
	if pb == null:
		return
	if int(sp["cap"]) < 0:
		sp["cap"] = pb.get_frames_available() # generator is empty right after play()
	var pending: Dictionary = sp["pending"]
	var target := int(float(sp["target"]) * RAW_RATE)
	var buffered := int(sp["cap"]) - pb.get_frames_available()
	var now := Time.get_ticks_msec() / 1000.0
	if sp["buffering"]:
		if pending.is_empty():
			return
		# Start once `target` worth of audio is queued, or the first packet has waited that long (short words).
		if pending.size() * RAW_CHUNK < target and now - float(sp["first_arrival"]) < float(sp["target"]):
			return
		sp["buffering"] = false
		sp["fade"] = true
		sp["plc"] = 0
		sp["next"] = _min_key(pending)
	while buffered < target:
		var nxt := int(sp["next"])
		var chunk: PackedFloat32Array
		if pending.has(nxt):
			chunk = pending[nxt]
			pending.erase(nxt)
			if (sp["red"] as Dictionary).erase(nxt):
				packets_recovered += 1
			if int(sp["plc"]) > 0:
				sp["fade"] = true # concealment -> real audio: soften the seam
			sp["plc"] = 0
			sp["last_chunk"] = chunk
		elif pending.is_empty():
			if buffered <= 0:
				sp["buffering"] = true # drained: prebuffer again before the next burst
				underruns += 1
			break
		elif buffered >= RAW_CHUNK:
			break # a hole, but audio is still playing: give the late packet until the last moment
		elif int(sp["plc"]) >= PLC_MAX:
			sp["next"] = _min_key(pending) # long gap: skip ahead to the next real audio
			sp["fade"] = true
			continue
		else:
			chunk = _conceal(sp)
		sp["next"] = nxt + 1
		if sp["fade"]:
			sp["fade"] = false
			chunk = chunk.duplicate()
			for i in mini(FADE_IN_FRAMES, chunk.size()): # soft start: no click when speech begins
				chunk[i] *= float(i) / FADE_IN_FRAMES
		pb.push_buffer(_pcm_to_frames(chunk))
		buffered += chunk.size()
		frames_played += chunk.size()


## Packet-loss concealment: the previous chunk played backwards (so the seam is continuous), fading out.
func _conceal(sp: Dictionary) -> PackedFloat32Array:
	var last: PackedFloat32Array = sp["last_chunk"]
	var n := RAW_CHUNK
	var out := PackedFloat32Array()
	out.resize(n)
	var k := int(sp["plc"])
	var g0 := pow(PLC_DECAY, k)
	var g1 := pow(PLC_DECAY, k + 1)
	var mirrored := PackedFloat32Array()
	mirrored.resize(n)
	for i in n:
		mirrored[i] = last[last.size() - 1 - i] if i < last.size() else 0.0
		out[i] = mirrored[i] * lerpf(g0, g1, float(i) / n)
	sp["last_chunk"] = mirrored
	sp["plc"] = k + 1
	frames_concealed += n
	return out


func _pcm_to_frames(mono: PackedFloat32Array) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(mono.size())
	for i in mono.size():
		frames[i] = Vector2(mono[i], mono[i])
	return frames


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
