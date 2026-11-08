extends Node
## Bot integration/soak probe. Owner: S07. Public API: none.
## NET: host and client verify drivers, authority, liveness and replicated motion.

var _failed := false
var _positions: Dictionary = {}
var _moved: Dictionary = {}


func _ready() -> void:
	add_child(load("res://game/main.tscn").instantiate())
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		print("[TEST] FAIL ", message)


func _run() -> void:
	# Exercise all intent types over simulated time without waiting for random live actions.
	var brain := BotBrain.new()
	var intent := PlayerInput.new()
	var seen := {}
	for i in 6000:
		brain.fill_input(self, intent, 0.1)
		_check(intent.move.length() <= 1.001, "normalized movement")
		if intent.jump_pressed: seen["jump"] = true
		if intent.interact_pressed: seen["interact"] = true
		if intent.primary_pressed: seen["primary"] = true
		if intent.sprint: seen["sprint"] = true
	_check(seen.size() == 4, "brain exercises jump/interact/primary/sprint")
	await get_tree().create_timer(2.0).timeout
	var duration := float(NetworkManager.args.get("bot-test-seconds", 3))
	var until := Time.get_ticks_msec() + int(duration * 1000)
	while Time.get_ticks_msec() < until:
		var count := int(NetworkManager.args.get("bot-test-count", 4))
		_check(NetworkManager.is_in_session(), "still connected")
		_check(Players.all().size() == count + 2, "host + client + server bots still present")
		for i in count:
			var id := Players.BOT_ID_BASE + i
			var bot := Players.get_player(id) as Player
			_check(bot != null, "server bot exists")
			if bot == null: continue
			_check(bot.is_bot and not bot.is_local(), "bot flags")
			_check(bot.get_multiplayer_authority() == 1, "server authority")
			_check((bot.input_driver is BotBrain) == multiplayer.is_server(), "driver only on authority")
			_check(bot.global_position.is_finite(), "finite position")
			if _positions.has(id) and bot.global_position.distance_to(_positions[id]) > 0.1:
				_moved[id] = true
			_positions[id] = bot.global_position
		var local := Players.local_player() as Player
		_check(local != null, "local slot exists")
		if local != null:
			_check((local.input_driver is BotBrain) == NetworkManager.args.has("bot"), "--bot local driver")
			if NetworkManager.args.has("bot"):
				if _positions.has("local") and local.global_position.distance_to(_positions["local"]) > 0.1:
					_moved["local"] = true
				_positions["local"] = local.global_position
		await get_tree().create_timer(0.25).timeout
	for i in int(NetworkManager.args.get("bot-test-count", 4)):
		_check(_moved.has(Players.BOT_ID_BASE + i), "each server bot moves on both peers")
	if NetworkManager.args.has("bot"):
		_check(_moved.has("local"), "client bot actually moves")
	print("[TEST] BOT PASSED" if not _failed else "[TEST] BOT FAILED")
	# WHY: let the other peer finish its probe before normal teardown.
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(1 if _failed else 0)
