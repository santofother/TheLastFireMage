## S12 voice v2 checks: ADPCM codec, bandwidth, group rules, effect buses; v3 jitter buffer (reorder, FEC, PLC).
## Owner: S12. NET: standalone local test (no network).
extends Node

func _fail(msg: String) -> void:
	print("[TEST] FAIL voice_codec: %s" % msg)
	get_tree().quit(1)


func _ready() -> void:
	var Adpcm = VoiceManager.VoiceAdpcm
	# --- codec round trip on a speech-like signal (two tones + envelope), 20 ms packets
	var chunk := PackedFloat32Array()
	chunk.resize(VoiceManager.RAW_CHUNK)
	var err := 0.0
	var sig := 0.0
	var raw_bytes := 0
	var packed_bytes := 0
	var phase := 0.0
	for p in 50: # one second
		for i in chunk.size():
			phase += 1.0
			var env := 0.5 + 0.5 * sin(phase * 0.0004)
			chunk[i] = (sin(phase * 0.11) * 0.5 + sin(phase * 0.37) * 0.25) * env
		var packet: PackedByteArray = Adpcm.encode(chunk)
		var back: PackedFloat32Array = Adpcm.decode(packet)
		if back.size() != chunk.size():
			return _fail("decoded %d samples, expected %d" % [back.size(), chunk.size()])
		for i in chunk.size():
			err += pow(back[i] - chunk[i], 2.0)
			sig += pow(chunk[i], 2.0)
		raw_bytes += chunk.size() * 2
		packed_bytes += packet.size()
	var snr := 10.0 * log(sig / maxf(err, 1e-12)) / log(10.0)
	var drop := 1.0 - float(packed_bytes) / raw_bytes
	print("[TEST] VOICE CODEC snr=%.1f dB bytes=%d/%d drop=%.0f%% (%.1f kbit/s)" % [snr, packed_bytes, raw_bytes, drop * 100.0, packed_bytes * 8.0 / 1000.0])
	if snr < 20.0:
		return _fail("snr too low")
	if drop < 0.5:
		return _fail("bandwidth drop < 50%")
	# --- odd/short packets keep their exact length; garbage doesn't crash
	for n in [1, 2, 3, 7, 160, 319]:
		var short := PackedFloat32Array()
		short.resize(n)
		if Adpcm.decode(Adpcm.encode(short)).size() != n:
			return _fail("length mismatch for %d samples" % n)
	if not Adpcm.decode(PackedByteArray([1])).is_empty():
		return _fail("malformed packet should decode to nothing")
	# --- capture gain still applied before 4-bit quantisation (do not revert the volume fix)
	if not is_equal_approx(VoiceManager.MIC_GAIN, 12.0) or VoiceManager.full_volume_distance != 8.0 or VoiceManager.silent_distance != 45.0:
		return _fail("voice loudness tuning changed")
	# --- group rules
	VoiceManager.set_voice_group(7, &"dead")
	if VoiceManager.get_voice_group(7) != &"dead" or VoiceManager.get_voice_group(8) != &"alive":
		return _fail("group storage")
	if VoiceManager.rule_scale(&"dead", &"dead") != VoiceManager.RULE_GLOBAL or VoiceManager.rule_scale(&"alive", &"alive") != 1.0:
		return _fail("default rules")
	var listener := Node3D.new()
	var speaker := Node3D.new()
	var player := AudioStreamPlayer3D.new()
	add_child(listener)
	add_child(speaker)
	speaker.add_child(player)
	speaker.position.x = 100.0 # far beyond silent_distance
	VoiceManager.listener = listener
	VoiceManager.register_speaker(7, player, speaker)
	VoiceManager._update_speakers(0.0)
	VoiceManager.set_voice_group(1, &"alive")
	if player.volume_db > -79.0:
		return _fail("alive listener should not hear a distant dead speaker")
	VoiceManager.set_voice_group(1, &"dead")
	VoiceManager._update_speakers(0.0)
	if not is_equal_approx(player.volume_db, 0.0):
		return _fail("dead listener should hear dead speakers everywhere (db=%f)" % player.volume_db)
	VoiceManager.set_voice_rule(&"dead", &"dead", 0.0)
	VoiceManager._update_speakers(0.0)
	if player.volume_db > -79.0:
		return _fail("rule scale 0 should mute")
	VoiceManager.set_voice_rule(&"dead", &"dead", VoiceManager.RULE_GLOBAL)
	VoiceManager.set_voice_group(1, &"alive")
	# --- effect buses
	VoiceManager.set_speaker_effect(7, &"mage", 1.0)
	var bus := AudioServer.get_bus_index(&"Voice_7")
	if bus < 0 or player.bus != &"Voice_7":
		return _fail("effect bus missing")
	var on := 0
	for e in AudioServer.get_bus_effect_count(bus):
		on += 1 if AudioServer.is_bus_effect_enabled(bus, e) else 0
	if on != 3:
		return _fail("mage preset should enable pitch, distortion and reverb (got %d)" % on)
	VoiceManager.set_speaker_effect(7, &"mage", 0.0)
	for e in AudioServer.get_bus_effect_count(bus):
		if AudioServer.is_bus_effect_enabled(bus, e):
			return _fail("strength 0 should bypass effects")
	VoiceManager.set_speaker_effect(7, &"mage", 0.5)
	VoiceManager.unregister_speaker(7)
	if AudioServer.get_bus_index(&"Voice_7") >= 0:
		return _fail("effect bus not freed")
	VoiceManager.clear_speaker_effects()
	# --- v3 transport: redundant copy round trip (half rate, same length, still recognisable)
	var red_bytes: PackedByteArray = VoiceManager.encode_redundant(chunk)
	var red_back: PackedFloat32Array = VoiceManager.decode_redundant(red_bytes)
	if red_back.size() != VoiceManager.RAW_CHUNK or red_bytes.size() > 90:
		return _fail("redundant copy size %d bytes / %d samples" % [red_bytes.size(), red_back.size()])
	# --- jitter buffer: reorder by sequence, rebuild losses from the redundant copy, conceal the rest.
	# Packets 0..9; 3 and 7 are lost but their copies ride in 4 and 8; 6 is lost with its copy (7) -> concealed.
	var jp := AudioStreamPlayer.new()
	add_child(jp)
	var sp: Dictionary = VoiceManager._new_speaker(jp, null)
	var chunks := []
	for s in 10:
		var c := PackedFloat32Array()
		c.resize(VoiceManager.RAW_CHUNK)
		c.fill(0.1 + 0.01 * s)
		chunks.append(c)
	var rec0: int = VoiceManager.packets_recovered
	var con0: int = VoiceManager.frames_concealed
	var played0: int = VoiceManager.frames_played
	for s in [0, 2, 1, 4, 5, 9, 8]: # out of order on purpose
		var red: PackedByteArray = VoiceManager.encode_redundant(chunks[s - 1]) if s > 0 else PackedByteArray()
		VoiceManager._receive(sp, s, chunks[s], red)
	var keys: Array = (sp["pending"] as Dictionary).keys()
	keys.sort()
	if keys != [0, 1, 2, 3, 4, 5, 7, 8, 9]:
		return _fail("pending after reorder/FEC should be 0-5,7-9 (got %s)" % [keys])
	if not sp["buffering"]:
		return _fail("jitter buffer should still be pre-buffering before the first pump")
	var waited := 0.0
	while VoiceManager.frames_played - played0 < 10 * VoiceManager.RAW_CHUNK and waited < 2.0:
		VoiceManager._pump_one(sp)
		await get_tree().process_frame
		waited += get_process_delta_time()
	var played: int = VoiceManager.frames_played - played0
	print("[TEST] VOICE JITTER played=%d recovered=%d concealed=%d" % [played,
		VoiceManager.packets_recovered - rec0, VoiceManager.frames_concealed - con0])
	if played < 10 * VoiceManager.RAW_CHUNK:
		return _fail("jitter buffer should play all 10 chunks (played %d frames)" % played)
	if VoiceManager.packets_recovered - rec0 != 2:
		return _fail("two lost packets should be rebuilt from redundancy")
	if VoiceManager.frames_concealed - con0 != VoiceManager.RAW_CHUNK:
		return _fail("exactly one chunk should be concealed")
	# A packet whose slot already played is dropped, not played late.
	var late0: int = VoiceManager.packets_late
	VoiceManager._receive(sp, 6, chunks[6], PackedByteArray())
	if VoiceManager.packets_late != late0 + 1:
		return _fail("late packet should be counted and dropped")
	# A long burst stays bounded (latency cap).
	for s in range(100, 160):
		VoiceManager._receive(sp, s, chunks[0], PackedByteArray())
	var cap := int((float(sp["target"]) + VoiceManager.JITTER_MAX_QUEUE) / VoiceManager.CHUNK_SEC)
	if (sp["pending"] as Dictionary).size() > cap:
		return _fail("queue not bounded (%d)" % (sp["pending"] as Dictionary).size())
	jp.stop()
	VoiceManager.listener = null
	print("[TEST] VOICE CODEC PASSED")
	get_tree().quit()
