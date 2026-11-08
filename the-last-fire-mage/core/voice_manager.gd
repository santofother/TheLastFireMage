extends Node
## Proximity voice chat.
## Both Steam and ENet modes send raw 16 kHz 16-bit PCM from Godot's mic (direct input API).
## (Steam's own getVoice() returned no data in testing, so it is no longer used for sending;
## STEAM codec packets are still decoded on receive for compatibility.)
## F4 / --voice-loopback: hear your own mic locally (tests playback on one machine).
## Packets go over Godot RPC (unreliable_ordered, channel 2), so both transports share one path.
## The game calls register_speaker() for each remote player and sets `listener` to the local player.

enum Codec { RAW_PCM16 = 0, STEAM = 1 }

const RAW_RATE := 16000
const STEAM_RATE := 24000
const RAW_CHUNK := 320 ## samples per packet (20 ms at 16 kHz, 640 bytes: fits one Steam/ENet datagram)
# FIX(S08, Codex): raw mic PCM had no gain, making loopback and remote speech faint.
const MIC_GAIN := 12.0 # TUNE: +21.6 dB capture gain; clamp before PCM quantization.
const OPEN_MIC_GATE := 0.04 ## peak level that opens the open-mic gate
const GATE_HOLD := 0.35 ## seconds the gate stays open after speech
const SPEAKING_TIMEOUT := 0.3

## Tunable falloff: full volume inside full_volume_distance, silent at silent_distance (gentle quadratic fade between).
var full_volume_distance := 8.0
var silent_distance := 45.0
var push_to_talk := true
var ptt_key: Key = KEY_V
var enable_raw_voice := true
var loopback := false ## play own mic locally (debug)

var mic_level := 0.0 ## 0..1, Godot mic (for the meter)
var local_speaking := false
var packets_sent := 0
var packets_received := 0
var mic_peak_seen := 0.0 ## loudest mic sample since start (diagnostics/tests)
var frames_played := 0 ## decoded samples pushed to speakers (diagnostics/tests)
var listener: Node3D ## local player; distances are measured from here

var _speakers := {} ## peer_id -> {player, node, rate, last}
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
	var lp := AudioStreamPlayer.new()
	lp.name = "LoopbackPlayer"
	add_child(lp)
	_loop_sp = {"player": lp, "node": null, "rate": 0, "last": -10.0}
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
			return "Raw PCM 16 kHz" if enable_raw_voice else "Off"
	return "Idle"


func register_speaker(peer_id: int, player: AudioStreamPlayer3D, node: Node3D) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	# WHY: max_distance adds its own linear attenuation even with attenuation disabled.
	player.max_distance = 0.0
	player.volume_db = -80.0
	_speakers[peer_id] = {"player": player, "node": node, "rate": 0, "last": -10.0}


func unregister_speaker(peer_id: int) -> void:
	_speakers.erase(peer_id)


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
				_send(_encode_pcm16(_pending), Codec.RAW_PCM16)
				_pending.clear()


func _reset_raw() -> void:
	if _pending.size() > 0:
		_send(_encode_pcm16(_pending), Codec.RAW_PCM16) # flush the tail of the sentence
		_pending.clear()
	_rs_pos = 0.0
	_rs_acc = 0.0
	_rs_count = 0


func _encode_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i] * MIC_GAIN, -1.0, 1.0) * 32767.0))
	return b


func _send(data: PackedByteArray, codec: int) -> void:
	if loopback:
		_play_pcm(_loop_sp, data, RAW_RATE)
	if NetworkManager.is_in_session():
		_voice_packet.rpc(data, codec)
		packets_sent += 1


# ---------------------------------------------------------------- receive / playback

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _voice_packet(data: PackedByteArray, codec: int) -> void:
	packets_received += 1
	var sp: Dictionary = _speakers.get(multiplayer.get_remote_sender_id(), {})
	if sp.is_empty():
		return
	var pcm := data
	var rate := RAW_RATE
	if codec == Codec.STEAM:
		if not SteamManager.available:
			return
		var d: Dictionary = Steam.decompressVoice(data, STEAM_RATE)
		if int(d.get("result", -1)) != Steam.VOICE_RESULT_OK:
			return
		pcm = d.get("uncompressed", PackedByteArray())
		pcm = pcm.slice(0, int(d.get("size", pcm.size())))
		rate = STEAM_RATE
	_play_pcm(sp, pcm, rate)


func _play_pcm(sp: Dictionary, pcm: PackedByteArray, rate: int) -> void:
	var player = sp["player"] # AudioStreamPlayer3D, or AudioStreamPlayer for loopback
	if not is_instance_valid(player):
		return
	if sp["rate"] != rate or not player.playing:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = rate
		gen.buffer_length = 0.5
		player.stream = gen
		player.play()
		sp["rate"] = rate
	var pb := player.call("get_stream_playback") as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var count := mini(pcm.size() / 2, pb.get_frames_available())
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		var s := pcm.decode_s16(i * 2) / 32768.0
		frames[i] = Vector2(s, s)
	pb.push_buffer(frames)
	frames_played += count
	sp["last"] = Time.get_ticks_msec() / 1000.0


func _update_speakers(now: float) -> void:
	var from: Vector3
	if is_instance_valid(listener) and listener.is_inside_tree():
		from = listener.global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		from = cam.global_position
	for id in _speakers:
		var sp: Dictionary = _speakers[id]
		var node: Node3D = sp["node"]
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var d := node.global_position.distance_to(from)
		var fade := clampf((d - full_volume_distance) / maxf(0.001, silent_distance - full_volume_distance), 0.0, 1.0)
		var vol := 1.0 - fade * fade
		sp["player"].volume_db = linear_to_db(maxf(vol, 0.0001))
		if node.has_method("set_speaking"):
			node.set_speaking(now - float(sp["last"]) < SPEAKING_TIMEOUT)
