extends Node
## Proximity voice chat.
## - Steam mode: Steam voice (getVoice / decompressVoice). Uses the mic chosen in Steam's settings.
## - ENet mode: raw 16 kHz 16-bit PCM from Godot's mic (AudioEffectCapture). Fine for LAN tests.
## Packets go over Godot RPC (unreliable_ordered, channel 2), so both transports share one path.
## The game calls register_speaker() for each remote player and sets `listener` to the local player.

enum Codec { RAW_PCM16 = 0, STEAM = 1 }

const RAW_RATE := 16000
const STEAM_RATE := 24000
const RAW_CHUNK := 640 ## samples per packet (40 ms at 16 kHz)
const OPEN_MIC_GATE := 0.04 ## peak level that opens the open-mic gate
const GATE_HOLD := 0.35 ## seconds the gate stays open after speech
const SPEAKING_TIMEOUT := 0.3

## Tunable falloff: full volume inside full_volume_distance, silent at silent_distance (linear between).
var full_volume_distance := 3.0
var silent_distance := 25.0
var push_to_talk := true
var ptt_key: Key = KEY_V
var enable_raw_voice := true

var mic_level := 0.0 ## 0..1, Godot mic (for the meter)
var local_speaking := false
var packets_sent := 0
var packets_received := 0
var listener: Node3D ## local player; distances are measured from here

var _speakers := {} ## peer_id -> {player, node, rate, last}
var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _headless := false
var _steam_recording := false
var _last_local_voice := -10.0
var _gate_timer := 0.0
var _rs_pos := 0.0
var _rs_acc := 0.0
var _rs_count := 0
var _pending := PackedFloat32Array()


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_setup_mic()


func _setup_mic() -> void:
	# Mic -> [Capture] -> MicSink(muted). Sends must target a lower bus index, so create the sink first.
	var sink := AudioServer.bus_count
	AudioServer.add_bus(sink)
	AudioServer.set_bus_name(sink, "MicSink")
	AudioServer.set_bus_mute(sink, true)
	var mic := AudioServer.bus_count
	AudioServer.add_bus(mic)
	AudioServer.set_bus_name(mic, "Mic")
	AudioServer.set_bus_send(mic, "MicSink")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(mic, _capture)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mic"
	add_child(_mic_player)
	if not _headless:
		_mic_player.play()


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func set_input_device(device: String) -> void:
	AudioServer.input_device = device
	if not _headless:
		_mic_player.stop()
		_mic_player.play()


func voice_mode_name() -> String:
	match NetworkManager.mode:
		NetworkManager.Mode.STEAM:
			return "Steam voice" if SteamManager.available else "Steam voice (unavailable)"
		NetworkManager.Mode.ENET:
			return "Raw PCM 16 kHz (LAN)" if enable_raw_voice else "Off"
	return "Idle"


func register_speaker(peer_id: int, player: AudioStreamPlayer3D, node: Node3D) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = silent_distance
	player.volume_db = -80.0
	_speakers[peer_id] = {"player": player, "node": node, "rate": 0, "last": -10.0}


func unregister_speaker(peer_id: int) -> void:
	_speakers.erase(peer_id)


# ---------------------------------------------------------------- capture / send

func _process(delta: float) -> void:
	var buf := PackedVector2Array()
	var n := _capture.get_frames_available()
	if n > 0:
		buf = _capture.get_buffer(n)
	var peak := 0.0
	for f in buf:
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	mic_level = maxf(peak, mic_level - delta * 1.5)

	var in_session := NetworkManager.is_in_session()
	var now := Time.get_ticks_msec() / 1000.0
	var ptt_down := Input.is_physical_key_pressed(ptt_key) and not _text_has_focus()

	if in_session and NetworkManager.mode == NetworkManager.Mode.STEAM:
		# Steam has its own silence detection, so open mic = record continuously.
		_steam_tick(ptt_down if push_to_talk else true, now)
		local_speaking = now - _last_local_voice < SPEAKING_TIMEOUT
	elif in_session and NetworkManager.mode == NetworkManager.Mode.ENET and enable_raw_voice:
		var want := ptt_down
		if not push_to_talk:
			_gate_timer = GATE_HOLD if peak > OPEN_MIC_GATE else _gate_timer - delta
			want = _gate_timer > 0.0
		if want:
			_raw_encode(buf)
		else:
			_reset_raw()
		local_speaking = want
	else:
		if _steam_recording:
			_steam_tick(false, now)
		local_speaking = false

	_update_speakers(now)


func _text_has_focus() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


func _steam_tick(want: bool, now: float) -> void:
	if not SteamManager.available:
		return
	if want != _steam_recording:
		_steam_recording = want
		if want:
			Steam.startVoiceRecording()
		else:
			Steam.stopVoiceRecording()
	if not _steam_recording:
		return
	var v: Dictionary = Steam.getVoice()
	var written := int(v.get("written", 0))
	if int(v.get("result", -1)) == Steam.VOICE_RESULT_OK and written > 0:
		var data: PackedByteArray = v.get("buffer", PackedByteArray())
		_send(data.slice(0, written), Codec.STEAM)
		_last_local_voice = now


func _raw_encode(buf: PackedVector2Array) -> void:
	var ratio := AudioServer.get_mix_rate() / RAW_RATE
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
		b.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return b


func _send(data: PackedByteArray, codec: int) -> void:
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
	var player: AudioStreamPlayer3D = sp["player"]
	if not is_instance_valid(player):
		return
	if sp["rate"] != rate or not player.playing:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = rate
		gen.buffer_length = 0.5
		player.stream = gen
		player.play()
		sp["rate"] = rate
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var count := mini(pcm.size() / 2, pb.get_frames_available())
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		var s := pcm.decode_s16(i * 2) / 32768.0
		frames[i] = Vector2(s, s)
	pb.push_buffer(frames)
	sp["last"] = Time.get_ticks_msec() / 1000.0


func _update_speakers(now: float) -> void:
	var from: Vector3
	if is_instance_valid(listener):
		from = listener.global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		from = cam.global_position
	for id in _speakers:
		var sp: Dictionary = _speakers[id]
		var node: Node3D = sp["node"]
		if not is_instance_valid(node):
			continue
		var d := node.global_position.distance_to(from)
		var vol := clampf(1.0 - (d - full_volume_distance) / (silent_distance - full_volume_distance), 0.0, 1.0)
		sp["player"].volume_db = linear_to_db(maxf(vol, 0.0001))
		if node.has_method("set_speaking"):
			node.set_speaking(now - float(sp["last"]) < SPEAKING_TIMEOUT)
