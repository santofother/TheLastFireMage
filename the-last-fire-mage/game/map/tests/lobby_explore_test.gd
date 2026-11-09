extends Node
## Real device-input regression for walking the town while solo in the lobby. Owner: S05.
## Public API: launch lobby_explore_test.tscn with a graphical Godot binary and --no-steam --port=N.
## NET: one local ENet host; asserts mouse capture, keyboard movement and Esc menu gating.

var _fails := 0


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[TEST] FAIL graphical DisplayServer required to exercise mouse capture")
		get_tree().quit(1)
		return
	add_child(load("res://game/main.tscn").instantiate())
	var port := int(NetworkManager.args.get("port", 20000 + randi() % 20000))
	_check(NetworkManager.host_enet(port) == OK, "host solo town session")
	for i in 45:
		await get_tree().physics_frame
	var player: Player = Players.local_player()
	var match_manager := GameEvents.system(&"match") as MatchManager
	_check(player != null and player.can_control(), "solo player is controllable")
	_check(match_manager.phase == Enums.Phase.LOBBY, "solo exploration remains in lobby")
	_check(get_tree().get_nodes_in_group("map_boat").size() >= 4, "real town loaded instead of test arena")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "lobby initially exposes cursor")
	match_manager.get_node("UI/Lobby/Content/Explore").pressed.emit()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var start := player.global_position
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await get_tree().process_frame
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "lobby preserves captured cursor while exploring")
	_check(player.global_position.z < start.z - 0.8, "real keyboard-input path moves player through town")
	var stamina := (GameEvents.system(&"hud") as Hud).get_node("Stamina/Meter") as ProgressBar
	_check(stamina.is_visible_in_tree() and stamina.value < stamina.max_value
		and is_equal_approx(stamina.value, player.stamina),
		"solo exploration displays the live stamina meter")
	_escape()
	for i in 3:
		await get_tree().process_frame
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Esc opens menu and releases cursor")
	_check(not stamina.is_visible_in_tree(), "stamina meter clears the lobby menu")
	# Let the movement controller finish braking before testing fresh menu input.
	for i in 12:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	start = player.global_position
	for i in 12:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_check(Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() < 0.1, "menu blocks movement")
	_escape()
	for i in 3:
		await get_tree().process_frame
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Esc closes menu and restores exploration")
	_check(match_manager.phase == Enums.Phase.LOBBY, "exploration does not start a round")
	print("[TEST] LOBBY EXPLORE PASSED" if _fails == 0 else "[TEST] LOBBY EXPLORE FAILED")
	get_tree().quit(0 if _fails == 0 else 1)


func _escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(release)


func _check(ok: bool, message: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		_fails += 1
