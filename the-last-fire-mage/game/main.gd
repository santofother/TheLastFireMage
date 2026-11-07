extends Node3D
## Game root (main scene). Owner: S02 / head engineer. Registered as GameEvents.system(&"main").
## Loads the map from MAP_SCENE_PATH, owns the player spawner, and holds every system under $Systems.
## CONTRACT: later cards never edit main.tscn or this file. Each system owns its own scene that main.tscn
## instances; change a system by editing that scene.
## NET: runs on every peer. Spawning/despawning players is server only (MultiplayerSpawner replicates).
## Public API: `spawn_player(id, name, is_bot) -> Node` (server), `get_map() -> Node3D`.

## CONTRACT: the map scene. S05 regenerates this file; tests can override with `--map=res://...`.
const MAP_SCENE_PATH := "res://game/map/town.tscn"
const PLAYER_SCENE := preload("res://game/player/player.tscn")
## Used only if the map has no `villager_spawn` markers.
const FALLBACK_SPAWNS := [Vector3(0, 1, 0), Vector3(3, 1, 0), Vector3(-3, 1, 0)]

@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var menu_camera: Camera3D = $MenuCamera
@onready var map_root: Node3D = $Map


func _enter_tree() -> void:
	GameEvents.register_system(&"main", self)


func _ready() -> void:
	_load_map(String(NetworkManager.args.get("map", MAP_SCENE_PATH)))
	spawner.spawn_function = _spawn_player
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.session_ended.connect(_on_session_ended)
	var t := String(NetworkManager.args.get("autotest", ""))
	if not t.is_empty():
		get_tree().create_timer(float(t)).timeout.connect(_autotest_report)
		var q := float(NetworkManager.args.get("quit-after", float(t) + 0.1))
		get_tree().create_timer(q).timeout.connect(get_tree().quit)


## The loaded map scene root (child of $Map).
func get_map() -> Node3D:
	return map_root.get_child(0) as Node3D if map_root.get_child_count() > 0 else null


## NET: server only. Spawns a player for `id` (real peer, or a bot id >= Players.BOT_ID_BASE with
## is_bot = true) at the next `villager_spawn` marker. Returns the node (or the existing one).
func spawn_player(id: int, pname: String, is_bot: bool = false) -> Node:
	if players.has_node(str(id)):
		return players.get_node(str(id))
	var spawns := get_tree().get_nodes_in_group(&"villager_spawn")
	var i := players.get_child_count()
	var pos: Vector3 = (spawns[i % spawns.size()] as Node3D).global_position if not spawns.is_empty() \
		else FALLBACK_SPAWNS[i % FALLBACK_SPAWNS.size()]
	var node := spawner.spawn({"id": id, "name": pname, "pos": pos, "bot": is_bot})
	print("[Game] Spawned ", pname, " (", id, ")", " [bot]" if is_bot else "")
	return node


func _load_map(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("[Game] Could not load map %s" % path)
		return
	map_root.add_child(scene.instantiate())
	print("[Game] Map ", path)


func _on_player_registered(id: int, pname: String) -> void: # server only
	spawn_player(id, pname)


func _spawn_player(data: Dictionary) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data["id"])
	p.peer_id = data["id"]
	p.display_name = data["name"]
	p.is_bot = data.get("bot", false)
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
	print("[TEST] VOICE sent=%d recv=%d played=%d mic_peak=%.3f" % [VoiceManager.packets_sent, VoiceManager.packets_received, VoiceManager.frames_played, VoiceManager.mic_peak_seen])
	for p in players.get_children():
		print("[TEST] POS %s %.2f %.2f" % [p.display_name, p.global_position.x, p.global_position.z])
