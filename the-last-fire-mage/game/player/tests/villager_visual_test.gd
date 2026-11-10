extends Node3D
## Headless checks for the red villager model and its clip selection. Owner: villager model integration.
## Public API: none; run through tools/tests/villager_visual_test.sh. NET: offline, authority peer 1.

class Driver extends RefCounted:
	var move := Vector2.ZERO
	var sprint := false
	var jump := false

	## Same intent interface that humans and bots use.
	func fill_input(_player: Player, intent: PlayerInput, _delta: float) -> void:
		intent.clear()
		intent.move = move
		intent.sprint = sprint
		intent.jump_pressed = jump
		jump = false

const ALL_CLIPS: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"jump_start", &"jump_air", &"jump_land",
	&"climb_mantle", &"interact", &"pickup", &"carry_idle", &"carry_walk", &"put_down", &"hit_stun", &"knockback",
	&"death"]
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"jump_air", &"carry_idle", &"carry_walk"]

var _fails := 0
var _player: Player
var _visual: VillagerVisual
var _anim: AnimationPlayer
var _driver := Driver.new()


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("[TEST] FAIL villager visual timeout"); get_tree().quit(1))
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	add_child(floor_body)
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _settle() -> void:
	_driver.move = Vector2.ZERO
	_driver.sprint = false
	await _ticks(90)


func _run() -> void:
	_player = load("res://game/player/player.tscn").instantiate() as Player
	_player.input_driver = _driver
	add_child(_player)
	_visual = _player.get_node("VillagerVisual") as VillagerVisual
	_anim = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	await _ticks(30)

	for clip in ALL_CLIPS:
		_check(_anim.has_animation(clip), "clip exists: %s" % clip)
	for clip in LOOPING:
		_check(_anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "clip loops: %s" % clip)
	_check(_visual.visible and not _player.get_node("Body").visible and not _player.get_node("Nose").visible,
		"default player shows the villager, not the capsule")
	_check(_visual.clip == &"idle", "stands idle")

	_driver.move = Vector2(0, -1)
	await _ticks(45)
	_check(_visual.clip == &"run" and _anim.speed_scale > 1.5, "walk speed uses the scaled run clip")
	_driver.sprint = true
	await _ticks(45)
	_check(_visual.clip == &"sprint" and _anim.speed_scale > 1.5, "sprinting uses the sprint clip")
	await _settle()
	_driver.move = Vector2(0, 1)
	await _ticks(45)
	_check(_visual.clip == &"run" and _anim.speed_scale < 0.0, "backing up plays the run clip in reverse")
	await _settle()

	_driver.jump = true
	await _ticks(4)
	_check(_visual.clip == &"jump_start", "jump starts on the takeoff tick")
	await _ticks(36)
	_check(_visual.clip == &"jump_air", "air pose while airborne")
	while _player.is_airborne:
		await get_tree().physics_frame
	await _ticks(2)
	_check(_visual.clip == &"jump_land", "landing clip on floor contact")
	await _settle()
	_check(_visual.clip == &"idle", "returns to idle after landing")

	GameEvents.carry_changed.emit(_player.peer_id + 1, &"chicken")
	await _ticks(2)
	_check(_visual.clip == &"idle", "ignores another player's carry")
	GameEvents.carry_changed.emit(_player.peer_id, &"chicken")
	await _ticks(2)
	_check(_visual.clip == &"pickup", "pickup plays when carrying starts")
	await _ticks(70)
	_check(_visual.clip == &"carry_idle", "holds carry idle")
	await _ticks(20)
	var socket := _player.to_local(_player.carry_socket.global_position)
	_check(absf(socket.y - 0.41) < 0.06 and absf(socket.z + 0.35) < 0.08 and absf(socket.x) < 0.05,
		"carry socket sits at the hands in front of the player, got %s" % socket)
	_driver.move = Vector2(0, -1)
	await _ticks(45)
	_check(_visual.clip == &"carry_walk", "carry walk while moving")
	await _settle()
	GameEvents.carry_changed.emit(_player.peer_id, &"")
	await _ticks(2)
	_check(_visual.clip == &"put_down", "put down when carrying ends")
	await _settle()

	_player.stun(0.5)
	await _ticks(3)
	_check(_visual.clip == &"hit_stun", "stun reaction")
	await _ticks(60)
	_check(_visual.clip == &"idle", "recovers from stun")

	_player.health.kill(0, &"test")
	await _ticks(3)
	_check(_visual.clip == &"death", "death clip")
	await _ticks(180)
	_check(_visual.clip == &"death" and not _anim.is_playing(), "death holds its final pose")
	_player.health.revive()
	await _ticks(3)
	_check(_visual.clip == &"idle", "revive stands back up")

	_player.set_role(Enums.Role.MAGE)
	_check(not _visual.visible and _player.get_node("MageVisual").visible and not _player.get_node("Body").visible,
		"mage shows the mage model, not the capsule")
	await _ticks(5) # WHY: mage abilities finish their deferred setup before being removed.
	_player.set_role(Enums.Role.VILLAGER)
	_check(_visual.visible and not _player.get_node("MageVisual").visible and not _player.get_node("Body").visible,
		"villager role shows the model again")

	print("[TEST] VILLAGER VISUAL %s (%d failures)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
