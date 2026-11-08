## Headless regression: death -> spectator state, no collision, revive restores. Owner: S11.
## Run by tools/tests/spectator_test.sh. Offline (no session): the local node counts as server.
extends Node3D

var failed := false


func _ready() -> void:
	await get_tree().process_frame
	var mgr := $Spectator as SpectatorManager
	var p := preload("res://game/player/player.tscn").instantiate() as Player
	p.peer_id = 1
	p.name = "1"
	p.position = Vector3(5, 0, 5)
	add_child(p)
	p.set_role(Enums.Role.VILLAGER)
	await get_tree().physics_frame
	_check(not mgr.is_spectating, "not spectating while alive")
	_check(Players.local_player() == p, "player is local")
	# Fall damage (x4.5): none below 3.1 m; jump 5, sprint jump 8, walk/sprint off 4 per story; linear in height.
	p._report_fall(3.0, false, true)
	p._report_fall(3.0, true, false)
	_check(p.health.hp == 100.0, "no damage below 3.1 m, jumping or not")
	p._report_fall(3.1, false, false)
	_check(is_equal_approx(p.health.hp, 100.0 - 4.0 * 4.5), "walk-off one story = 10.8")
	p.health.hp = 100.0
	p._report_fall(3.1, false, true)
	_check(is_equal_approx(p.health.hp, 100.0 - 5.0 * 4.5), "one-story jump = 13.5")
	p.health.hp = 100.0
	p._report_fall(3.1, true, true)
	_check(is_equal_approx(p.health.hp, 100.0 - 8.0 * 4.5), "one-story sprint jump = 21.6")
	p.health.hp = 100.0
	p._report_fall(6.2, false, true)
	_check(is_equal_approx(p.health.hp, 100.0 - 10.0 * 4.5), "two stories scale linearly")
	# Lethal fall: first one downs (alive, hp 1, no control), a villager revive gives 80%, the second one kills.
	p.health.hp = 10.0
	p._report_fall(6.2, false, true)
	_check(p.is_alive and p.health.is_downed and p.health.hp == p.tuning.downed_hp and not p.can_control(),
		"lethal fall downs instead of killing")
	p.health.recover(p.health.max_hp * p.tuning.revive_hp_fraction)
	_check(not p.health.is_downed and is_equal_approx(p.health.hp, 80.0) and p.can_control(), "revive = 80% hp")
	p.health.hp = 10.0
	p._report_fall(6.2, false, true)
	_check(not p.is_alive and not p.health.is_downed, "second lethal fall (downs_allowed = 1) kills")
	p.health.revive()
	await get_tree().physics_frame
	_check(p.is_alive and p.health.downs_used == 0, "round reset restores downs")
	p.health.kill(0, &"test")
	await get_tree().physics_frame
	_check(not p.is_alive, "player dead")
	_check(mgr.is_spectating, "spectating after death")
	_check(p.collision_layer == 0, "corpse has no collision layer")
	_check(mgr.get_child_count() > 0 and mgr._ghost_anim != null, "ghost uses the player's villager model")
	_check(mgr.camera.current, "spectator camera current")
	_check(mgr.camera.global_position.y > mgr.tuning.camera_height, "camera above the glass layer")
	_check(is_equal_approx(mgr.focus.y, mgr.tuning.camera_height), "ghost on glass layer")
	_check(VoiceManager.listener == mgr.camera, "voice listener follows spectator camera")
	var before := mgr.focus
	mgr.move_focus(Vector3(3, 0, 0))
	_check(mgr.focus.x == before.x + 3.0, "free movement")
	p.health.revive()
	await get_tree().physics_frame
	_check(p.is_alive, "revived")
	_check(not mgr.is_spectating, "spectator off after revive")
	_check(p.camera.current, "player camera restored")
	_check(VoiceManager.listener == p, "listener restored")
	_check(p.collision_layer != 0, "collision restored")
	# 3 storeys (9.3 m) sprint-jump must be over 100 (playtest: 86 was too low).
	p._report_fall(9.3, true, true)
	_check(p.health.is_downed or not p.is_alive, "3-story sprint jump is lethal (>100 dmg)")
	p.health.revive()
	# Hold-to-revive: 4 s of server-counted hold by a free villager.
	_check(is_equal_approx(p.tuning.revive_hold_time, 4.0), "revive hold = 4 s")
	add_child(preload("res://game/interact/interact_manager.tscn").instantiate())
	await get_tree().process_frame
	var v := preload("res://game/player/player.tscn").instantiate() as Player
	v.peer_id = 77
	v.name = "77"
	v.position = Vector3(5, 0, 6)
	add_child(v)
	v.set_role(Enums.Role.VILLAGER)
	await get_tree().physics_frame
	p.health.down(1.0)
	var it := v.find_child("Interactor", true, false) as Interactor
	var node := p.get_node("Interactable") as Interactable
	_check(it != null and node.hold_time == 4.0, "revive interactable has hold_time")
	it.hold_target = node
	it._tick_hold(3.5)
	_check(p.health.is_downed, "3.5 s hold does not revive yet")
	it._tick_hold(0.6)
	_check(not p.health.is_downed, "4 s hold revives")
	# Knife (20) kills a downed player.
	p.health.down(1.0)
	p.health.apply_damage(20.0, 77, &"knife")
	_check(not p.is_alive, "one knife hit kills a downed player")
	p.health.revive()
	v.queue_free()
	# Late-join spectator role.
	GameEvents.role_assigned.emit(1, Enums.Role.SPECTATOR)
	_check(mgr.is_spectating, "SPECTATOR role enters spectator")
	GameEvents.role_assigned.emit(1, Enums.Role.VILLAGER)
	_check(not mgr.is_spectating, "new alive role exits spectator")
	print("[TEST] SPECTATOR %s" % ("FAILED" if failed else "PASSED"))
	get_tree().quit(1 if failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("[TEST] FAIL %s" % what)
