class_name BotManager
extends Node
## CLI bot setup. Owner: S07. Registered as GameEvents.system(&"bots").
## --bot drives the local human slot; --bots=N fills the lobby with server-owned players.
## NET: only the authority assigns a driver; replicas use normal player synchronization.

func _enter_tree() -> void:
	GameEvents.register_system(&"bots", self)


func _ready() -> void:
	GameEvents.local_player_ready.connect(_on_local_player_ready)
	NetworkManager.hosting_started.connect(_spawn_bots.call_deferred)
	if NetworkManager.is_in_session() and multiplayer.is_server():
		_spawn_bots.call_deferred()
	var local := Players.local_player()
	if local != null:
		_on_local_player_ready(local)


func _on_local_player_ready(player: Node) -> void:
	if NetworkManager.args.has("bot"):
		player.input_driver = BotBrain.new()
		print("[Bot] Driving local player ", player.peer_id)


func _spawn_bots() -> void:
	if not NetworkManager.is_in_session() or not multiplayer.is_server():
		return
	var count := clampi(int(NetworkManager.args.get("bots", 0)), 0, NetworkManager.MAX_PLAYERS - 1)
	var main := GameEvents.system(&"main")
	for i in count:
		var id := Players.BOT_ID_BASE + i
		# WHY: avoid a duplicate driver if host startup was observed twice.
		if Players.get_player(id) != null:
			continue
		var player: Node = main.spawn_player(id, "Bot%d" % (i + 1), true)
		if player != null:
			player.input_driver = BotBrain.new()
			print("[Bot] Spawned server bot ", id)


## NET: server only. Changes the bot roster while waiting in the lobby.
func set_lobby_count(count: int) -> void:
	if not NetworkManager.is_in_session() or not multiplayer.is_server():
		return
	var match_system := GameEvents.system(&"match")
	if match_system == null or match_system.phase != Enums.Phase.LOBBY:
		return
	count = clampi(count, 0, 5)
	NetworkManager.args["bots"] = count
	for i in range(count, 5):
		var id := Players.BOT_ID_BASE + i
		if Players.get_player(id) != null:
			NetworkManager.peer_left.emit(id)
	_spawn_bots()
