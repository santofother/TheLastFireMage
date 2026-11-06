extends Node3D
## Test map root. The spawner lives here from startup so late joiners never miss spawns.

const PLAYER_SCENE := preload("res://game/player.tscn")
const SPAWN_POINTS := [
	Vector3(0, 1, 6), Vector3(4, 1, 4), Vector3(-4, 1, 4),
	Vector3(6, 1, 0), Vector3(-6, 1, 0), Vector3(0, 1, -2),
]

@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var menu_camera: Camera3D = $MenuCamera


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.session_ended.connect(_on_session_ended)
	var t := String(NetworkManager.args.get("autotest", ""))
	if not t.is_empty():
		get_tree().create_timer(float(t)).timeout.connect(_autotest_report)
		var q := float(NetworkManager.args.get("quit-after", float(t) + 0.1))
		get_tree().create_timer(q).timeout.connect(get_tree().quit)


func _on_player_registered(id: int, pname: String) -> void: # server only
	if players.has_node(str(id)):
		return
	var pos: Vector3 = SPAWN_POINTS[players.get_child_count() % SPAWN_POINTS.size()]
	spawner.spawn({"id": id, "name": pname, "pos": pos})
	print("[Game] Spawned ", pname, " (", id, ")")


func _spawn_player(data: Dictionary) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data["id"])
	p.peer_id = data["id"]
	p.display_name = data["name"]
	p.position = data["pos"]
	return p


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server() and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()


func _on_session_ended(_reason: String) -> void:
	for c in players.get_children():
		c.queue_free()
	menu_camera.current = true


func _autotest_report() -> void:
	print("[TEST] PEERS %d" % (multiplayer.get_peers().size() if NetworkManager.is_in_session() else 0))
	print("[TEST] VOICE sent=%d recv=%d played=%d" % [VoiceManager.packets_sent, VoiceManager.packets_received, VoiceManager.frames_played])
	for p in players.get_children():
		print("[TEST] POS %s %.2f %.2f" % [p.display_name, p.global_position.x, p.global_position.z])
