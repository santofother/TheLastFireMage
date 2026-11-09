extends Node3D
## Scripted controller regression tests. Owner: S03. Runs offline on authority peer 1.
## Public API: none; run through tools/tests/movement_test.sh.

class Driver extends RefCounted:
	var move := Vector2.ZERO
	var sprint := false
	var crouch := false
	var jump := false
	var look := Vector2.ZERO

	## Supplies the same intent interface used by human players and S07 bots.
	func fill_input(_player: Player, intent: PlayerInput, _delta: float) -> void:
		intent.clear()
		intent.move = move
		intent.sprint = sprint
		intent.crouch = crouch
		intent.jump_pressed = jump
		intent.look_delta = look
		jump = false
		look = Vector2.ZERO

var _fails := 0
var _player: Player
var _driver := Driver.new()


func _ready() -> void:
	get_tree().create_timer(110.0).timeout.connect(func() -> void:
		print("[TEST] FAIL movement timeout"); get_tree().quit(1))
	_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	_run.call_deferred()


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.position = pos
	return body


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(ok: bool, description: String) -> void:
	print("[TEST] %s %s" % ["ok  " if ok else "FAIL", description])
	if not ok:
		_fails += 1


func _reset(pos := Vector3(0, 0.04, 0)) -> void:
	_driver.move = Vector2.ZERO
	_driver.sprint = false
	_driver.crouch = false
	_player.set_input_lock(&"test", false)
	_player.teleport(pos)
	_player.rotation = Vector3.ZERO
	await _ticks(4)


# FIX(S14, Codex): Drive real roof landings, including jumps whose apex is above the one-story band.
func _check_roof_fall(height: float, sprint: bool, jump: bool, damage_scale: float) -> void:
	var roof := _box(Vector3(0, height - 0.15, 0), Vector3(4, 0.3, 2.4))
	await _reset(Vector3(0, height + 0.04, 0))
	_player.health.revive()
	_driver.move = Vector2(0, -1)
	_driver.sprint = sprint
	await _ticks(10)
	_driver.jump = jump
	var peak := _player.position.y
	for i in 120:
		await _ticks(1)
		if _player.is_on_floor() and _player.position.y < 0.2:
			break
		peak = _player.position.y if _player.is_on_floor() else maxf(peak, _player.position.y)
	var base := 4.0
	if jump:
		base = 8.0 if sprint else 5.0
	var expected := base * 4.5 * (peak - _player.position.y) / 3.1 * damage_scale
	_check(_player.is_on_floor() and _player.position.y < 0.2
		and absf(100.0 - _player.health.hp - expected) < 0.1,
		"%.1f m roof fall (sprint=%s, jump=%s) takes %.2f HP, expected %.2f (landing y=%.2f)" % [
			height, sprint, jump, 100.0 - _player.health.hp, expected, _player.position.y])
	roof.queue_free()


func _run() -> void:
	_player = load("res://game/player/player.tscn").instantiate() as Player
	_player.name = "1"
	_player.input_driver = _driver
	add_child(_player)
	await _reset()
	_driver.move = Vector2(0, -1)
	await _ticks(1)
	_check(_player.velocity.length() < _player.tuning.walk_speed, "run accelerates rather than snapping")
	await _ticks(25)
	_check(_player.position.z < -1.0, "scripted PlayerInput moves player")
	_driver.sprint = true
	await _ticks(30)
	_check(absf(_player.velocity.z) > 6.0, "sprint reaches tuned speed")
	_check(_player.camera.fov > _player.tuning.camera_fov + 3.0, "sprint gives a small FOV kick")
	_driver.move = Vector2.ZERO
	await _ticks(20)
	_check(absf(_player.velocity.z) < 0.1, "ground braking stops player")

	await _reset()
	_driver.jump = true
	await _ticks(1)
	_check(_player.velocity.y > 0.0, "scripted jump takes off")
	var after_jump := _player.stamina
	_check(is_equal_approx(after_jump, _player.tuning.max_stamina - _player.tuning.jump_stamina_cost),
		"successful jump spends stamina once")
	await _ticks(25)
	_check(_player.position.y > 1.0, "standing jump reaches approximately 1.2 metres")
	_check(is_equal_approx(_player.stamina, after_jump), "stamina does not recover in the air")
	await _ticks(45)
	await _reset()
	_driver.move = Vector2(0, -1)
	_driver.sprint = true
	await _ticks(30)
	var takeoff := _player.position
	_driver.jump = true
	await _ticks(1)
	_driver.move = Vector2.ZERO
	await _ticks(30)
	_check(takeoff.distance_to(_player.position) > 3.0 and absf(_player.velocity.z) > 6.0,
		"running jump carries momentum over a three-metre gap without held input")
	_driver.move = Vector2.RIGHT
	var before_air := _player.velocity.x
	await _ticks(5)
	_check(_player.velocity.x > before_air, "air control steers without removing forward momentum")

	await _reset()
	_driver.crouch = true
	# WHY: _reset leaves the feet 4 cm up; crouching in the air is a leg tuck, so settle on the floor first.
	await _ticks(12)
	_check(_player.is_crouching and is_equal_approx((_player.get_node("Collision").shape as CapsuleShape3D).height,
		_player.tuning.crouch_height), "crouch resizes collision")
	var ceiling := _box(Vector3(0, 0.9, 0), Vector3(3, 0.25, 3))
	await _ticks(3)
	_driver.crouch = false
	await _ticks(3)
	_check(_player.is_crouching, "cannot stand through a low ceiling")
	ceiling.queue_free()
	await _ticks(3)
	_check(not _player.is_crouching, "stands once ceiling is clear")

	await _reset()
	_driver.move = Vector2.RIGHT
	_player.set_input_lock(&"test", true)
	_driver.jump = true
	_driver.look = Vector2(0.3, 0.2)
	await _ticks(5)
	_check(_player.position.x < 0.01 and _player.rotation.y == 0.0 and not _player.input.jump_pressed,
		"input lock clears movement, jump and mouse look")
	_player.set_input_lock(&"test", false)
	_driver.move = Vector2.ZERO
	_player.stun(0.1)
	await _ticks(1)
	_check(not _player.can_control(), "stun still disables control")
	await _ticks(10)

	# A press just before landing must survive until the next grounded tick.
	await _reset(Vector3(0, 0.45, 0))
	_player.velocity.y = -3.0
	_driver.jump = true
	var buffered_jump := false
	for i in 12:
		await _ticks(1)
		buffered_jump = buffered_jump or _player.velocity.y > 1.0
	_check(buffered_jump, "jump buffer fires after landing")

	var perch := _box(Vector3(20, 1.0, 0), Vector3(2, 2, 2))
	await _reset(Vector3(20.75, 2.04, 0))
	_driver.move = Vector2.RIGHT
	for i in 30:
		await _ticks(1)
		if not _player.is_on_floor():
			break
	_driver.jump = true
	await _ticks(1)
	_check(_player.velocity.y > 0.0, "coyote jump works just beyond a ledge")
	perch.queue_free()

	var ledge := _box(Vector3(0, 0.8, -3), Vector3(4, 1.6, 3))
	await _reset()
	_driver.move = Vector2(0, -1)
	await _ticks(3)
	_driver.jump = true
	var saw_mantle := false
	for i in 65:
		await _ticks(1)
		saw_mantle = saw_mantle or _player.is_mantling
	_check(saw_mantle and _player.position.y > 1.5 and _player.position.z < -1.7,
		"jump at a 1.6-metre ledge mantles onto the top")
	await _reset()
	await _ticks(1)
	_driver.move = Vector2(0, -1)
	await _ticks(50)
	_check(not _player.is_mantling and _player.position.y < 0.1, "walking at a wall cannot climb")

	# A blocked landing cannot pull the capsule through an overhang.
	var roof := _box(Vector3(0, 2.5, -3), Vector3(4, 0.3, 3))
	await _reset()
	_driver.move = Vector2(0, -1)
	_driver.jump = true
	saw_mantle = false
	for i in 45:
		await _ticks(1)
		saw_mantle = saw_mantle or _player.is_mantling
	_check(not saw_mantle, "mantle rejects insufficient headroom")
	roof.queue_free()
	ledge.queue_free()
	var tall := _box(Vector3(0, 1.6, -3), Vector3(4, 3.2, 3))
	await _reset()
	_driver.move = Vector2(0, -1)
	_driver.jump = true
	saw_mantle = false
	for i in 70:
		await _ticks(1)
		saw_mantle = saw_mantle or _player.is_mantling
	_check(not saw_mantle and _player.position.y < 0.2, "cannot scale a wall above two-metre takeoff reach")
	tall.queue_free()

	await _reset(Vector3(0, 5.0, 0))
	var saw_tumble := false
	for i in 65:
		await _ticks(1)
		if _player.is_tumbling:
			saw_tumble = true
			break
	_check(saw_tumble and not _player.can_control() and _player.health.hp < 100.0 and _player.health.hp > 70.0,
		"big walk-off fall tumbles and takes reduced damage")
	await _ticks(45)
	_check(_player.can_control() and not _player.is_tumbling, "recovers from landing tumble")

	await _check_roof_fall(3.6, false, false, 0.5)
	await _check_roof_fall(3.6, true, false, 0.5)
	await _check_roof_fall(3.6, false, true, 0.5)
	await _check_roof_fall(3.6, true, true, 0.5)
	await _check_roof_fall(7.2, true, true, 1.0)
	_player.health.revive()
	await _reset()
	var other := load("res://game/player/player.tscn").instantiate() as Player
	other.peer_id = Players.BOT_ID_BASE
	other.is_bot = true
	other.name = str(other.peer_id)
	other.input_driver = Driver.new()
	other.position = Vector3(1, 0.04, 0)
	add_child(other)
	await _ticks(4)
	var bump_start := other.position
	_driver.move = Vector2.RIGHT
	await _ticks(25)
	_check(other.position.distance_to(bump_start) > 0.05 and other.position.x > bump_start.x, "colliding players give each other a small push")
	other.queue_free()

	await _reset()
	var camera_wall := _box(Vector3(0, 2, 2), Vector3(6, 4, 0.25))
	await _ticks(5)
	_check((_player.get_node("CameraRig/SpringArm") as SpringArm3D).get_hit_length() < 2.1,
		"camera spring arm retracts at world collision")
	camera_wall.queue_free()
	_player.set_role(Enums.Role.MAGE)
	_check(is_equal_approx(_player.tuning.height, 1.4), "mage uses same controller with 1.4-metre tuning")
	_player.health.kill(0, &"test")
	_check(_player.collision_layer == 0 and _player.get_node("Body").rotation.x < -1.5,
		"death keeps corpse presentation")
	_player.health.revive()
	_check(_player.collision_layer == 2 and _player.get_node("Body").rotation.x == 0.0,
		"revive restores upright body")
	await _check_stamina()
	await _check_step_and_tuck()
	print("[TEST] MOVEMENT %s (%d failures)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _jump_peak(tuck_near_apex: bool, tuck_at_takeoff: bool) -> float:
	await _reset(Vector3(30, 0.04, 0))
	await _ticks(10)
	_driver.jump = true
	await _ticks(1)
	var peak := 0.0
	for i in 70:
		if tuck_at_takeoff or (tuck_near_apex and _player.velocity.y < 0.5):
			_driver.crouch = true
		await _ticks(1)
		peak = maxf(peak, _player.position.y)
	_driver.crouch = false
	return peak


# Notches must neither catch the player nor make crossing them faster than a flat run.
func _notched_distance(notch: float) -> float:
	var boxes: Array[StaticBody3D] = []
	if notch > 0.0:
		for i in 24:
			boxes.append(_box(Vector3(60, notch * (i + 1) / 2.0, -4.0 - 0.5 * i), Vector3(6, notch * (i + 1), 0.5)))
	await _reset(Vector3(60, 0.04, 0))
	_driver.move = Vector2(0, -1)
	await _ticks(45)
	var start := _player.position.z
	await _ticks(60)
	var distance := absf(_player.position.z - start)
	_driver.move = Vector2.ZERO
	for b in boxes:
		b.queue_free()
	await _ticks(2)
	return distance


func _check_notched_slope() -> void:
	var flat: float = await _notched_distance(0.0)
	for notch: float in [0.03, 0.06, 0.1, 0.2]:
		var distance: float = await _notched_distance(notch)
		print("[TEST] 60-tick distance flat=%.2f notch %.2f m=%.2f" % [flat, notch, distance])
		_check(distance <= flat * 1.03, "%.2f m notches give no speed boost" % notch)
		_check(distance >= flat * 0.85, "%.2f m notches do not catch the player" % notch)


# Running up a ramp onto a plateau: never airborne at the crest, never faster than the flat.
func _ramp_run(degrees: float) -> Array:
	var boxes: Array[StaticBody3D] = []
	var a := deg_to_rad(degrees)
	var length := 8.0
	if degrees > 0.0:
		var top_mid := Vector3(-30, length / 2.0 * sin(a), -1.0 - length / 2.0 * cos(a))
		var ramp := _box(top_mid - Vector3(0, cos(a), sin(a)) * 0.1, Vector3(6, 0.2, length))
		ramp.rotation.x = a
		boxes.append(ramp)
		var h := length * sin(a)
		boxes.append(_box(Vector3(-30, h / 2.0, -1.0 - length * cos(a) - 4.0), Vector3(6, h, 8)))
	await _reset(Vector3(-30, 0.04, 0))
	_driver.move = Vector2(0, -1)
	var airborne := 0
	for i in 180:
		await _ticks(1)
		if not _player.is_on_floor():
			airborne += 1
	var distance := absf(_player.position.z)
	_driver.move = Vector2.ZERO
	for b in boxes:
		b.queue_free()
	await _ticks(2)
	return [distance, airborne]


# Sprinting up tight stairs (town steps): never faster than a flat sprint, never airborne for long.
func _stair_run(rise: float, tread: float, sprint: bool) -> Array:
	var boxes: Array[StaticBody3D] = []
	if rise > 0.0:
		for i in 40:
			# Each box runs from its riser to the top of the flight, so the treads have no seams.
			var h := rise * (i + 1)
			var depth := tread * (40 - i)
			boxes.append(_box(Vector3(-15, h / 2.0, -2.0 - tread * i - depth / 2.0), Vector3(4, h, depth)))
	await _reset(Vector3(-15, 0.04, 0))
	_driver.move = Vector2(0, -1)
	_driver.sprint = sprint
	var airborne := 0
	for i in 90:
		await _ticks(1)
		if not _player.is_on_floor():
			airborne += 1
	var distance := absf(_player.position.z)
	_driver.move = Vector2.ZERO
	_driver.sprint = false
	for b in boxes:
		b.queue_free()
	await _ticks(2)
	return [distance, airborne]


func _check_ramps() -> void:
	for sprint: bool in [false, true]:
		var flat_stairs: Array = await _stair_run(0.0, 0.3, sprint)
		# TODO(S17): box stairs with treads under ~0.3 m (e.g. 0.25) climb slowly when walking (not sprinting).
		# Town stairs use ramp colliders, so the map never hits this.
		for step: Vector2 in [Vector2(0.08, 0.3), Vector2(0.15, 0.3), Vector2(0.2, 0.3)]:
			var run: Array = await _stair_run(step.x, step.y, sprint)
			print("[TEST] stairs rise %.2f tread %.2f sprint %s: %.2f m (flat %.2f), airborne %d" % [
				step.x, step.y, sprint, run[0], flat_stairs[0], run[1]])
			_check(run[0] <= flat_stairs[0] * 1.02, "stairs %.2f/%.2f give no speed boost" % [step.x, step.y])
			_check(run[0] >= flat_stairs[0] * 0.7, "stairs %.2f/%.2f do not catch the player" % [step.x, step.y])
	var flat: Array = await _ramp_run(0.0)
	for degrees: float in [12.0, 25.0]:
		var run: Array = await _ramp_run(degrees)
		print("[TEST] ramp %d deg: distance %.2f (flat %.2f), airborne ticks %d" % [degrees, run[0], flat[0], run[1]])
		_check(run[0] <= flat[0] * 1.02, "%d deg ramp gives no speed boost" % degrees)
		_check(run[0] >= flat[0] * 0.8, "%d deg ramp does not catch the player" % degrees)
		_check(run[1] <= 1, "%d deg ramp crest does not launch the player" % degrees)


func _check_step_and_tuck() -> void:
	var curb := _box(Vector3(30, 0.15, -6), Vector3(4, 0.3, 9))
	await _reset(Vector3(30, 0.04, 0))
	_driver.move = Vector2(0, -1)
	await _ticks(70)
	_check(_player.position.y > 0.27 and _player.position.z < -2.0, "runs up a 0.3 m ledge without jumping")
	curb.queue_free()
	var wall := _box(Vector3(30, 0.3, -3), Vector3(4, 0.6, 3))
	await _reset(Vector3(30, 0.04, 0))
	_driver.move = Vector2(0, -1)
	await _ticks(70)
	_check(_player.position.y < 0.1 and _player.position.z > -1.6, "a 0.6 m ledge still needs a jump")
	wall.queue_free()
	await _reset(Vector3(30, 0.04, 0))
	await _check_notched_slope()
	await _check_ramps()
	var plain: float = await _jump_peak(false, false)
	var timed: float = await _jump_peak(true, false)
	var early: float = await _jump_peak(false, true)
	print("[TEST] jump peak plain=%.2f early-tuck=%.2f apex-tuck=%.2f" % [plain, early, timed])
	_check(timed > plain + 0.2, "crouching at the top of a jump lifts the feet higher")
	_check(early < timed - 0.05, "a badly timed tuck gains less")
	await _reset(Vector3(30, 0.04, 0))
	await _ticks(10)
	_driver.crouch = true
	await _ticks(10)
	_driver.jump = true
	await _ticks(2)
	_check(_player.velocity.y > 0.0, "can jump out of a crouch")
	_driver.crouch = false


func _check_stamina() -> void:
	await _reset()
	_driver.sprint = true
	await _ticks(10)
	_check(is_equal_approx(_player.stamina, _player.tuning.max_stamina), "holding sprint while still costs nothing")
	_driver.move = Vector2(0, -1)
	for i in 390:
		await _ticks(1)
		if _player.stamina <= 0.0:
			break
	_check(_player.stamina == 0.0, "holding sprint exhausts the stamina pool")
	_driver.jump = true
	await _ticks(12)
	_check(_player.is_on_floor() and not _player.is_sprinting and
		absf(_player.velocity.z + _player.tuning.walk_speed) < 0.1,
		"exhaustion blocks jumps and drops held sprint to running speed")
	_driver.sprint = false
	await _ticks(100)
	_check(_player.stamina >= _player.tuning.sprint_recovery_stamina, "stamina recovers while running without sprint")
	_driver.sprint = true
	await _ticks(1)
	_check(_player.is_sprinting, "sprint works again after recovery")
