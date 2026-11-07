extends Node3D
## S03 two-peer regression: real owner movement/state sync and server-validated bump RPC.
## Owner: S03. Public API: none. Run tools/tests/movement_net_test.sh (host + client).

class Driver extends RefCounted:
	var elapsed := 0.0
	## Fills the real controller; client runs into host, then crouches in place.
	func fill_input(_player: Player, intent: PlayerInput, delta: float) -> void:
		elapsed += delta
		intent.clear()
		if elapsed < 1.5:
			intent.move = Vector2.LEFT
			intent.sprint = true
		else:
			intent.crouch = true

var _hosting := false
var _spawner: MultiplayerSpawner
var _client_id := 0
var _elapsed := 0.0
var _saw_sprint := false
var _saw_crouch := false
var _saw_push := false
var _client_spawned := false


func _ready() -> void:
	var players := Node3D.new()
	players.name = "Players"
	add_child(players)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	_spawner.spawn_path = ^"../Players"
	_spawner.spawn_function = _spawn_player
	add_child(_spawner)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 1, 40)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	add_child(floor_body)
	var peer := ENetMultiplayerPeer.new()
	var port := int(NetworkManager.args.get("port", 24696))
	var error: Error
	_hosting = NetworkManager.args.has("host")
	if _hosting:
		error = peer.create_server(port)
	else:
		error = peer.create_client("127.0.0.1", port)
	if error != OK:
		print("[TEST] FAIL movement peer startup: ", error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	if _hosting:
		multiplayer.peer_connected.connect(_on_connected)
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		print("[TEST] FAIL movement network timeout"); get_tree().quit(1))


func _on_connected(id: int) -> void:
	_client_id = id
	_spawner.spawn(1)
	_spawner.spawn(id)


func _spawn_player(id: int) -> Node:
	var player := load("res://game/player/player.tscn").instantiate() as Player
	player.peer_id = id
	player.name = str(id)
	player.position = Vector3(0.0 if id == 1 else 1.1, 0.04, 0.0)
	if id != 1 and id == multiplayer.get_unique_id():
		player.input_driver = Driver.new()
		_client_spawned = true
	return player


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not _hosting:
		if _client_spawned:
			_elapsed += delta
		if _elapsed > 2.5:
			print("[TEST] MOVEMENT NETWORK CLIENT PASSED")
			get_tree().quit()
		return
	var host := get_node_or_null("Players/1") as Player
	var client := get_node_or_null("Players/%d" % _client_id) as Player
	if host == null or client == null:
		return
	_elapsed += delta
	_saw_push = _saw_push or host.position.x < -0.04
	_saw_sprint = _saw_sprint or client.is_sprinting
	_saw_crouch = _saw_crouch or (client.is_crouching and is_equal_approx(
		(client.get_node("Collision").shape as CapsuleShape3D).height, client.tuning.crouch_height))
	if _elapsed > 3.0:
		var ok := _saw_push and _saw_sprint and _saw_crouch
		print("[TEST] server sees client sprint=%s crouch=%s and client bump pushed host=%s" % [
			_saw_sprint, _saw_crouch, _saw_push])
		print("[TEST] MOVEMENT NETWORK %s" % ("PASSED" if ok else "FAILED"))
		get_tree().quit(0 if ok else 1)
