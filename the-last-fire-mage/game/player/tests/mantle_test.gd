extends Node3D
## Space mantle regression fixtures. Owner: S03. Runs standalone on the authority peer.
## Public API: none. Run tools/tests/mantle_test.sh.

class Driver extends RefCounted:
	var tick := 0
	var second_press := true
	## Feeds a ground jump followed by a fresh Space press near its apex.
	func fill_input(_player: Player, intent: PlayerInput, _delta: float) -> void:
		intent.clear()
		intent.jump = true
		intent.jump_pressed = tick == 5 or (second_press and tick == 32)
		tick += 1

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	body.position = at
	return body


func _run() -> void:
	_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	for scenario in ["space", "held", "ceiling", "too_high", "locked", "mage"]:
		var height := 3.5 if scenario == "too_high" else 1.6
		var ledge := _box(Vector3(3, height, 3), Vector3(0, height / 2.0, -2.3))
		var ceiling: StaticBody3D
		if scenario == "ceiling":
			ceiling = _box(Vector3(3, 0.2, 3), Vector3(0, 2.5, -2.3))
		var player := preload("res://game/player/player.tscn").instantiate() as Player
		player.is_bot = true
		player.position = Vector3(0, 0.02, -0.45)
		var driver := Driver.new()
		driver.second_press = scenario != "held"
		player.input_driver = driver
		add_child(player)
		if scenario == "mage":
			player.set_role(Enums.Role.MAGE)
		var pulled := false
		for tick in 65:
			if scenario == "locked" and tick == 30:
				player.set_input_lock(&"test", true)
			await get_tree().physics_frame
			await get_tree().process_frame
			pulled = pulled or (player.position.y >= height and player.position.z < -0.8)
		var expected: bool = scenario in ["space", "mage"]
		var ok: bool = pulled == expected
		print("[TEST] %s mantle %s" % ["ok" if ok else "FAIL", scenario])
		if not ok:
			_fails += 1
		player.queue_free()
		ledge.queue_free()
		if ceiling != null:
			ceiling.queue_free()
		await get_tree().process_frame
	print("[TEST] MANTLE %s" % ["PASSED" if _fails == 0 else "FAILED"])
	get_tree().quit(0 if _fails == 0 else 1)
