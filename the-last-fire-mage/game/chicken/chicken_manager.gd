class_name ChickenManager
extends Node3D
## Spawns and tracks chickens. Owner: S06. Registered as GameEvents.system(&"chickens").
## NET: server spawns chickens into `$Chickens` through `$ChickenSpawner` (MultiplayerSpawner), at nodes in
## group `chicken_spawn`. Chickens are server-simulated.
## Round hook: on `phase_changed(ROLE_REVEAL)` the server clears and spawns `tuning.count` chickens.
## Respawn: if `tuning.respawn_time > 0`, a killed chicken is replaced after that many seconds (server).
## Public API: `spawn_chickens(count)`, `clear_chickens()`, `get_chickens()`, `alive_count()`, `tuning`.

const CHICKEN_SCENE := preload("res://game/chicken/chicken.tscn")
## Used if the map has no `chicken_spawn` markers.
const FALLBACK_SPAWN := Vector3(0, 0.5, 0)

var tuning: ChickenTuning
var _next_id := 1

@onready var chickens_root: Node3D = $Chickens
@onready var spawner: MultiplayerSpawner = $ChickenSpawner


func _enter_tree() -> void:
	GameEvents.register_system(&"chickens", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/chicken/tuning_chicken.tres", "chicken") as ChickenTuning
	spawner.spawn_function = _spawn_chicken
	GameEvents.phase_changed.connect(_on_phase_changed)
	GameEvents.chicken_killed.connect(_on_chicken_killed)
	NetworkManager.session_ended.connect(func(_r: String) -> void: clear_chickens())


## NET: server only. Spawns `count` chickens spread over the `chicken_spawn` markers (random jitter).
func spawn_chickens(count: int) -> void:
	if not Net.is_server(self):
		return
	var spawns := get_tree().get_nodes_in_group(&"chicken_spawn")
	spawns.shuffle()
	for i in count:
		var base: Vector3 = (spawns[i % spawns.size()] as Node3D).global_position if not spawns.is_empty() \
			else FALLBACK_SPAWN
		var jitter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) if i >= spawns.size() \
			else Vector3.ZERO
		spawner.spawn({"name": "Chicken%d" % _next_id, "pos": base + jitter + Vector3(0, 0.2, 0)})
		_next_id += 1
	print("[Chicken] Spawned %d (alive %d)" % [count, alive_count()])


## NET: server only. Removes all chickens (round reset). Also runs locally when the session ends.
func clear_chickens() -> void:
	for c in get_chickens():
		c.queue_free()


## All chicken nodes (every peer).
func get_chickens() -> Array[Node]:
	return chickens_root.get_children()


## Living chickens (every peer).
func alive_count() -> int:
	var n := 0
	for c in get_chickens():
		if not c.is_queued_for_deletion() and (c as Chicken).health.is_alive:
			n += 1
	return n


func _spawn_chicken(data: Dictionary) -> Node: # every peer (spawner)
	var c := CHICKEN_SCENE.instantiate() as Chicken
	c.name = data["name"]
	c.tuning = tuning
	c.position = data["pos"]
	c.home = data["pos"]
	return c


func _on_phase_changed(phase: int, _duration: float) -> void:
	if phase == Enums.Phase.ROLE_REVEAL and Net.is_server(self):
		clear_chickens()
		spawn_chickens(tuning.count)


func _on_chicken_killed(_killer_id: int, _pos: Vector3) -> void:
	if tuning.respawn_time > 0.0 and Net.is_server(self):
		get_tree().create_timer(tuning.respawn_time).timeout.connect(func() -> void:
			if alive_count() < tuning.count:
				spawn_chickens(1))
