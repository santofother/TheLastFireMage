extends Node3D
## S18 headless audio test: bank completeness, bus layout + voice routing, dread LOS logic, noise ranges,
## storm emitter placement, room reverb. Asserts on director state (no audio output exists headless).
## Prints `[TEST] AUDIO PASSED` or `[TEST] FAIL <what>` and quits.

const FakePlayer := preload("res://game/audio/tests/fake_player.gd")
const FakeFirestorm := preload("res://game/audio/tests/fake_firestorm.gd")
const VoiceFx := preload("res://core/voice/voice_fx.gd")

var director: AudioDirector
var ear := Node3D.new()
var failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_bank()
	director = (load("res://game/audio/audio_director.tscn") as PackedScene).instantiate() as AudioDirector
	add_child(director)
	ear.name = "Ear"
	add_child(ear)
	director.listener_override = ear
	director.role_override = Enums.Role.VILLAGER
	_check(GameEvents.system(&"audio") == director, "director registered as system audio")
	await _check_buses_and_voice()
	await _check_dread()
	await _check_noise()
	await _check_storm()
	await _check_reverb()
	print("[TEST] FAIL audio" if failed else "[TEST] AUDIO PASSED")
	get_tree().quit(1 if failed else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[TEST] ok %s" % what)
	else:
		failed = true
		print("[TEST] FAIL %s" % what)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = pos
	return body


# ---------------------------------------------------------------- bank vs cue sheet

func _check_bank() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/audio/CUE_SHEET.md")
	var text := FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "cue sheet readable at %s" % path)
	var re := RegEx.create_from_string("(?m)^\\|\\s*`([a-z0-9_]+)`\\s*\\|")
	var bank := Sfx.bank()
	var count := 0
	var bad := PackedStringArray()
	for m in re.search_all(text):
		count += 1
		var cue := StringName(m.get_string(1))
		var s := bank.get_stream(cue)
		if s == null or not _has_audio(s):
			bad.append(String(cue))
	_check(count >= 40, "cue sheet lists %d cues" % count)
	_check(bad.is_empty(), "every cue resolves to a non-empty stream (missing: %s)" % ", ".join(bad))
	_check(bank.cue_names().size() == count, "bank has exactly the cue-sheet cues (%d)" % bank.cue_names().size())
	_check(Sfx.stream(&"definitely_not_a_cue") == null, "unknown cue returns null without crashing")


func _has_audio(s: AudioStream) -> bool:
	if s is AudioStreamRandomizer:
		var r := s as AudioStreamRandomizer
		if r.streams_count == 0:
			return false
		for i in r.streams_count:
			if r.get_stream(i) == null or r.get_stream(i).get_length() <= 0.0:
				return false
		return true
	return s.get_length() > 0.0


# ---------------------------------------------------------------- buses + voice routing

func _check_buses_and_voice() -> void:
	for bus in AudioDirector.BUSES:
		_check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"SFX")) == &"World", "SFX sends to World")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"World")) == &"Game", "World sends to Game")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Voices")) == &"Master", "Voices bypass the Game bus")
	AudioDirector.set_volume(&"game", 0.5)
	AudioDirector.set_volume(&"player", 1.5)
	AudioDirector.set_volume(&"mic", 0.25)
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Game")) - linear_to_db(0.5)) < 0.01
		and absf(AudioDirector.get_volume(&"player") - 1.5) < 0.01 and is_equal_approx(VoiceManager.mic_volume, 0.25),
		"game / player / mic volumes are separate")
	AudioDirector.set_volume(&"game", 0.0)
	_check(AudioDirector.get_volume(&"game") == 0.0, "game volume 0 mutes the Game bus")
	for kind in [&"game", &"player", &"mic"]:
		AudioDirector.set_volume(kind, 1.0)
	var plain := _fake_player(901, Vector3(1000, 0, 0))
	var fx := _fake_player(902, Vector3(1000, 0, 5))
	var fx_bus := VoiceFx.ensure_bus(902)
	fx.voice.bus = fx_bus
	await _wait(0.6)
	_check(plain.voice.bus == &"Voices", "plain voice routed into Voices")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(fx_bus)) == &"Voices", "Voice_<peer> FX bus sends to Voices")
	var stray := AudioStreamPlayer3D.new()
	add_child(stray)
	_check(stray.bus == &"SFX", "stray 3D sounds on Master are moved to SFX")
	stray.queue_free()
	var cluck := AudioStreamPlayer3D.new()
	cluck.name = "Cluck"
	add_child(cluck)
	await get_tree().process_frame
	var takes := Sfx.stream(&"chicken_cluck") as AudioStreamRandomizer
	_check(cluck.has_meta(&"s18_cluck") and cluck.bus == &"SFX" and takes != null and takes.streams_count >= 6,
		"chicken clucks adopted (recorded takes swap in outside headless)")
	cluck.queue_free()
	_check(plain.get_node_or_null(^"AudioEmitter") is FootstepEmitter, "director attached a FootstepEmitter")
	plain.queue_free()
	fx.queue_free()
	VoiceFx.free_bus(fx_bus)
	await _wait(0.1)


func _fake_player(id: int, pos: Vector3) -> Node3D:
	var p := FakePlayer.new()
	p.peer_id = id
	p.add_to_group(&"players")
	p.voice = AudioStreamPlayer3D.new()
	p.add_child(p.voice)
	add_child(p)
	p.global_position = pos
	return p


# ---------------------------------------------------------------- dread (LOS only)

func _check_dread() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var wall := _box(Vector3(5, -100, 0), Vector3(0.5, 4, 8))
	var mage := Node3D.new()
	add_child(mage)
	mage.global_position = Vector3(10, 0, 0)
	ear.global_position = Vector3(0, 1.6, 0)
	director.mage_override = [mage]
	await _wait(1.5)
	var d := director.dread
	_check(d.los and d.active[&"heartbeat"] and d.active[&"strings"], "mage at 10 m with LOS: heartbeat + strings (%s)"
		% d.active_names())
	_check(d.spotted_count == 1, "LOS starting inside 20 m fired one spotted stinger")
	var hb_before := float(d.levels[&"heartbeat"])
	wall.global_position = Vector3(5, 2, 0)
	await _wait(1.25)
	_check(not d.active[&"heartbeat"] and not d.active[&"strings"], "wall blocks LOS: layers off")
	var hb_mid := float(d.levels[&"heartbeat"])
	_check(hb_mid > 0.2 and hb_mid < hb_before, "LOS lost fades out, not instantly (%.2f -> %.2f)" % [hb_before, hb_mid])
	await _wait(3.5)
	_check(float(d.levels[&"heartbeat"]) < 0.01 and float(d.levels[&"strings"]) < 0.01, "faded out after ~3 s")
	d.reset()
	await _wait(1.5)
	_check(not d.los and not d.active[&"heartbeat"] and not d.active[&"strings"],
		"same distance behind a wall from the start: no heartbeat/strings")
	director.role_override = Enums.Role.MAGE
	wall.global_position = Vector3(5, -100, 0)
	await _wait(1.0)
	_check(d.active_names() == "none", "the mage never hears villager dread")
	director.role_override = Enums.Role.VILLAGER
	# Mage frozen during the head start: no layers, no stinger. Released: layers, but still no stinger right away.
	d.reset()
	var spots := d.spotted_count
	director._on_phase_changed(Enums.Phase.HEAD_START, 30.0)
	await _wait(1.5)
	_check(d.active_names() == "none" and d.spotted_count == spots, "head start: no dread, no scare stinger (%s)"
		% d.active_names())
	director._on_phase_changed(Enums.Phase.HUNT, 0.0)
	await _wait(1.5)
	_check(d.active[&"heartbeat"] and d.spotted_count == spots, "mage released in view: dread on, no stinger")
	director._on_phase_changed(Enums.Phase.LOBBY, 0.0)
	# Lingering mage: layers settle 40 % quieter, and come back to full after a calm spell.
	var t := DreadTracker.new(director.tuning)
	for i in 60: # 15 s with the mage 10 m away in view
		t.sense(true, 10.0, true, 0.25)
		t.fade(0.25)
	_check(is_equal_approx(t.settle, director.tuning.dread_settle_level), "lingering mage: dread settles to %.2f" % t.settle)
	for i in 80: # 20 s with no mage
		t.sense(false, INF, false, 0.25)
		t.fade(0.25)
	_check(is_equal_approx(t.settle, 1.0), "after a calm spell the next approach is full volume (%.2f)" % t.settle)
	director.mage_override = []
	mage.queue_free()
	wall.queue_free()


# ---------------------------------------------------------------- noise ranges

func _check_noise() -> void:
	var t := director.tuning
	var sprint := FootstepEmitter.noise_range_for(t, true, false, 6.0, false, true, false, false)
	var walk := FootstepEmitter.noise_range_for(t, false, false, 3.0, false, true, false, false)
	var crouch := FootstepEmitter.noise_range_for(t, false, true, 1.5, false, true, false, false)
	var still := FootstepEmitter.noise_range_for(t, false, false, 0.0, false, true, false, false)
	_check(sprint > walk and walk > crouch and crouch == 0.0 and still == 0.0,
		"noise ranges sprint %.0f > walk %.0f > crouch %.0f = still %.0f" % [sprint, walk, crouch, still])
	var stub := FakePlayer.new()
	add_child(stub)
	stub.global_position = Vector3(0, 0, 20)
	var e := FootstepEmitter.new()
	e.player = stub
	e.tuning = t
	stub.add_child(e)
	var measured := {}
	for state in [["sprint", 6.0], ["walk", 3.0], ["crouch", 1.5]]:
		stub.is_sprinting = state[0] == "sprint"
		stub.is_crouching = state[0] == "crouch"
		var before := e.steps_played
		var step := e.get_node_or_null(^"Sfx_step_villager") as AudioStreamPlayer3D
		for i in 60:
			stub.global_position += Vector3(float(state[1]) / 60.0, 0, 0)
			await get_tree().physics_frame
		step = e.get_node_or_null(^"Sfx_step_villager") as AudioStreamPlayer3D
		measured[state[0]] = [e.noise_range, e.steps_played - before, step.max_distance if step else 0.0]
	print("[TEST] emitter measured %s" % str(measured))
	_check(measured["sprint"][0] == sprint and measured["sprint"][1] > 0 and measured["sprint"][2] == sprint,
		"sprinting emitter max_distance %.0f" % measured["sprint"][2])
	_check(measured["walk"][0] == walk and measured["walk"][1] > 0 and measured["walk"][2] == walk,
		"walking emitter max_distance %.0f" % measured["walk"][2])
	_check(measured["crouch"][0] == 0.0 and measured["crouch"][1] == 0, "crouching emitter is silent")
	stub.role = Enums.Role.MAGE
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(e.get_node_or_null(^"Loop_mage_aura_loop") != null, "mage gets the fire-aura loop")
	stub.queue_free()


# ---------------------------------------------------------------- storm emitter

func _check_storm() -> void:
	var p := AudioDirector.storm_point(Vector3(0, 0, 0), 10.0, Vector3(3, 2, 4))
	_check(p.is_equal_approx(Vector3(6, 2, 8)), "storm_point nearest ring point %s" % p)
	var fs := FakeFirestorm.new()
	add_child(fs)
	fs.zone_center = Vector3(200, 0, 0)
	fs.zone_radius = 30.0
	GameEvents.register_system(&"firestorm", fs)
	ear.global_position = Vector3(240, 1.6, 0)
	await _wait(0.3)
	var em := director.storm_emitter
	_check(em.global_position.distance_to(Vector3(230, 1.6, 0)) < 0.5, "storm emitter on the ring nearest the listener %s"
		% em.global_position)
	_check(director.in_storm, "listener outside the zone counts as in the storm")
	ear.global_position = Vector3(200, 1.6, 50)
	await _wait(2.5)
	var flat := Vector2(em.global_position.x - 200.0, em.global_position.z).length()
	_check(em.global_position.distance_to(Vector3(200, 1.6, 30)) < 0.5 and absf(flat - 30.0) < 0.5,
		"storm emitter followed to the new nearest point %s" % em.global_position)
	ear.global_position = Vector3(205, 1.6, 0)
	await _wait(0.3)
	_check(not director.in_storm, "inside the safe zone is not in the storm")
	fs.queue_free()


# ---------------------------------------------------------------- room reverb

func _check_reverb() -> void:
	var c := Vector3(-300, 0, 0)
	_box(c + Vector3(0, -0.5, 0), Vector3(8, 1, 8))
	_box(c + Vector3(0, 3.5, 0), Vector3(8, 1, 8))
	for side in [Vector3(3.5, 1.5, 0), Vector3(-3.5, 1.5, 0)]:
		_box(c + side, Vector3(1, 4, 8))
	for side in [Vector3(0, 1.5, 3.5), Vector3(0, 1.5, -3.5)]:
		_box(c + side, Vector3(8, 4, 1))
	ear.global_position = c + Vector3(0, 1.6, 0)
	await _wait(2.0)
	var closed_enc := director.room_enclosure
	var closed_wet := director.reverb_wet
	_box(Vector3(-600, -0.5, 0), Vector3(80, 1, 80))
	ear.global_position = Vector3(-600, 1.6, 0)
	await _wait(2.0)
	var open_enc := director.room_enclosure
	var open_wet := director.reverb_wet
	print("[TEST] reverb closed enc=%.2f wet=%.2f open enc=%.2f wet=%.2f" % [closed_enc, closed_wet, open_enc, open_wet])
	_check(closed_enc > 0.9 and open_enc < 0.1, "probe sees the closed room vs open ground")
	_check(closed_wet > open_wet + 0.1, "enclosed room gives larger wet than open ground")
	var w := AudioServer.get_bus_index(&"World")
	_check(is_equal_approx((AudioServer.get_bus_effect(w, 0) as AudioEffectReverb).wet, director.reverb_wet),
		"World bus reverb follows the director")
