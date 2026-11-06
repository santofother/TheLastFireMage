extends Node
## Transport-agnostic session layer (ENet or Steam). Reusable across party games.
## The game listens to `player_registered` / `peer_left` / `session_ended` and spawns/despawns players.

signal hosting_started
signal connected
signal connection_failed(reason: String)
signal player_registered(peer_id: int, player_name: String) ## server only
signal peer_left(peer_id: int)
signal session_ended(reason: String)
signal status_changed(text: String)

enum Mode { OFFLINE, ENET, STEAM }

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 6

var mode: Mode = Mode.OFFLINE
var local_name := "Player"
var player_names: Dictionary = {} ## peer_id -> name (synced from server)
var ping_ms := -1
## Command line user args (after `--`), e.g. `--host --port=24680 --name=Bob --autotest=8`.
var args: Dictionary = {}
## Headless test hook: when set (Vector2 x,z) the local player teleports there.
var test_target = null

var _ping_timer := 0.0


func _ready() -> void:
	args = _parse_args()
	if args.has("name"):
		local_name = args["name"]
	if args.has("test-target"):
		var p: PackedStringArray = String(args["test-target"]).split(",")
		test_target = Vector2(float(p[0]), float(p[1]))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


func mode_name() -> String:
	return ["Offline", "ENet (LAN/IP)", "Steam"][mode]


func is_in_session() -> bool:
	var p := multiplayer.multiplayer_peer
	return mode != Mode.OFFLINE and p != null \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ---------------------------------------------------------------- ENet

func host_enet(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		connection_failed.emit("Could not host on port %d (%s)" % [port, error_string(err)])
		return err
	start_host_with_peer(peer, Mode.ENET)
	return OK


func join_enet(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		connection_failed.emit("Could not connect to %s:%d (%s)" % [ip, port, error_string(err)])
		return err
	start_client_with_peer(peer, Mode.ENET)
	status_changed.emit("Connecting to %s:%d ..." % [ip, port])
	return OK


# ---------------------------------------------------------------- generic (used by SteamManager too)

func start_host_with_peer(peer: MultiplayerPeer, m: Mode) -> void:
	mode = m
	multiplayer.multiplayer_peer = peer
	player_names = {1: local_name}
	print("[Net] Hosting (%s) as '%s'" % [mode_name(), local_name])
	status_changed.emit("Hosting (%s)" % mode_name())
	hosting_started.emit()
	player_registered.emit(1, local_name)


func start_client_with_peer(peer: MultiplayerPeer, m: Mode) -> void:
	mode = m
	multiplayer.multiplayer_peer = peer


func leave(reason: String = "Left game") -> void:
	if mode == Mode.OFFLINE:
		return
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if mode == Mode.STEAM:
		SteamManager.leave_lobby()
	mode = Mode.OFFLINE
	player_names.clear()
	ping_ms = -1
	print("[Net] Session ended: ", reason)
	status_changed.emit(reason)
	session_ended.emit(reason)


# ---------------------------------------------------------------- callbacks

func _on_peer_connected(id: int) -> void:
	print("[Net] PEER_CONNECTED ", id)


func _on_peer_disconnected(id: int) -> void:
	print("[Net] PEER_DISCONNECTED ", id)
	player_names.erase(id)
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	print("[Net] CONNECTED my_id=", multiplayer.get_unique_id())
	status_changed.emit("Connected (%s)" % mode_name())
	connected.emit()
	_register.rpc_id(1, local_name)


func _on_connection_failed() -> void:
	leave("Connection failed")
	connection_failed.emit("Connection failed")


func _on_server_disconnected() -> void:
	leave("Host left the game")


@rpc("any_peer", "call_remote", "reliable")
func _register(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(20)
	if pname.is_empty():
		pname = "Player%d" % (player_names.size() + 1)
	player_names[id] = pname
	print("[Net] REGISTERED ", id, " ", pname)
	_sync_names.rpc(player_names)
	player_registered.emit(id, pname)


@rpc("authority", "call_remote", "reliable")
func _sync_names(names: Dictionary) -> void:
	player_names = names


# ---------------------------------------------------------------- ping (app-level, works for both transports)

func _process(delta: float) -> void:
	if not is_in_session() or multiplayer.is_server():
		return
	_ping_timer += delta
	if _ping_timer >= 1.0:
		_ping_timer = 0.0
		_ping.rpc_id(1, Time.get_ticks_msec())


@rpc("any_peer", "call_remote", "unreliable")
func _ping(t: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


@rpc("authority", "call_remote", "unreliable")
func _pong(t: int) -> void:
	ping_ms = Time.get_ticks_msec() - t
