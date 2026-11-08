## Capture gain regression checks. Owner: S08 playtest fix. NET: standalone local test.
## Exercises the PCM encoder shared by loopback, full packets and sentence tails.
extends Node

func _ready() -> void:
	var pcm: PackedByteArray = VoiceManager._encode_pcm16(PackedFloat32Array([0.025, -0.025, 0.0, 0.8, -0.8]))
	assert(pcm.size() == 10, "gain preserves packet size")
	assert(absf(pcm.decode_s16(0) / 32767.0 - 0.3) < 0.0001, "quiet positive speech gains 21.6 dB")
	assert(absf(pcm.decode_s16(2) / 32767.0 + 0.3) < 0.0001, "quiet negative speech gains 21.6 dB")
	assert(pcm.decode_s16(4) == 0, "silence stays silent")
	assert(pcm.decode_s16(6) == 32767 and pcm.decode_s16(8) == -32767, "loud speech clamps without wrapping")
	var listener := Node3D.new()
	var speaker := Node3D.new()
	var player := AudioStreamPlayer3D.new()
	add_child(listener)
	add_child(speaker)
	speaker.add_child(player)
	VoiceManager.listener = listener
	VoiceManager.register_speaker(2, player, speaker)
	assert(player.max_distance == 0.0, "no second engine distance fade")
	VoiceManager._update_speakers(0.0)
	assert(is_equal_approx(player.volume_db, 0.0), "nearby speech keeps full gain")
	speaker.position.x = (VoiceManager.full_volume_distance + VoiceManager.silent_distance) * 0.5
	VoiceManager._update_speakers(0.0)
	assert(is_equal_approx(db_to_linear(player.volume_db), 0.75), "gentle proximity falloff")
	speaker.position.x = VoiceManager.silent_distance
	VoiceManager._update_speakers(0.0)
	assert(player.volume_db <= -79.0, "distant speech remains silent")
	VoiceManager.unregister_speaker(2)
	VoiceManager.listener = null
	print("[TEST] VOICE GAIN PASSED")
	get_tree().quit()
