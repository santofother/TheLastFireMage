extends Node
## Host-menu bot smoke test. Owner: S07. Public API: none.
## NET: single host drives the real menu button and checks the spawned roster.

func _ready() -> void:
	add_child(load("res://game/main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	var main := GameEvents.system(&"main")
	var count := main.find_child("BotCount", true, false) as SpinBox
	if count == null:
		_fail("Bots selector missing")
		return
	count.value = 3
	var host: Button
	for node in main.find_children("*", "Button", true, false):
		if node.text == "Host LAN": host = node
	if host == null:
		_fail("Host LAN button missing")
		return
	# Use the randomized test port while exercising the same handler as a click.
	var menu: Node = main.get_node("Menu")
	menu._port_edit.text = str(NetworkManager.args.get("port"))
	host.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	if Players.all().size() != 4:
		_fail("expected host + three selected bots")
		return
	for i in 3:
		var bot := Players.get_player(Players.BOT_ID_BASE + i)
		if bot == null or not bot.input_driver is BotBrain:
			_fail("selected bots must have drivers")
			return
	if count.editable:
		_fail("selector should lock while connected")
		return
	print("[TEST] BOT MENU PASSED")
	get_tree().quit()


func _fail(message: String) -> void:
	print("[TEST] FAIL ", message)
	get_tree().quit(1)
