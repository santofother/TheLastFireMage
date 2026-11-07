class_name ChickenManager
extends Node3D
## Spawns and tracks chickens. Owner: S06. Registered as GameEvents.system(&"chickens").
## NET: server spawns chickens into `$Chickens` through `$ChickenSpawner` (MultiplayerSpawner), at nodes in
## group `chicken_spawn`. Chickens are server-simulated.
## Public API: `spawn_chickens(count)`, `clear_chickens()`, `get_chickens()`, `alive_count()`.

var tuning: ChickenTuning

func _enter_tree() -> void:
	GameEvents.register_system(&"chickens", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/chicken/tuning_chicken.tres", "chicken") as ChickenTuning


## NET: server only. Spawns `count` chickens at random `chicken_spawn` markers.
func spawn_chickens(_count: int) -> void:
	pass # TODO(S06)


## NET: server only. Removes all chickens (round reset).
func clear_chickens() -> void:
	pass # TODO(S06)


## All chicken nodes (every peer).
func get_chickens() -> Array[Node]:
	return $Chickens.get_children()


## Living chickens (every peer).
func alive_count() -> int:
	return get_chickens().size()
