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
	p.health.kill(0, &"test")
	await get_tree().physics_frame
	_check(not p.is_alive, "player dead")
	_check(mgr.is_spectating, "spectating after death")
	_check(p.collision_layer == 0, "corpse has no collision layer")
	_check(mgr.camera.current, "spectator camera current")
	_check(is_equal_approx(mgr.camera.global_position.y, mgr.tuning.camera_height), "camera at spectator height")
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
