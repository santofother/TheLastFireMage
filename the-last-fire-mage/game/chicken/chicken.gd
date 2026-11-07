class_name Chicken
extends CharacterBody3D
## One chicken. Owner: S06. Lives under ChickenManager/$Chickens, spawned by its MultiplayerSpawner.
## NET: server simulates (authority 1); clients only display synced state.
## Implements the CARRYABLE interface used by the interact system (S10), see ARCHITECTURE §Interact:
## `can_be_carried()`, `carry_speed_multiplier()`, `on_picked_up(carrier)`, `on_dropped(pos, impulse)`,
## `on_hidden(spot)`, `on_unhidden()`. All of them are called by S10 on the SERVER only.
## Death: Health.died -> GameEvents.chicken_killed(killer_id, pos) on all peers; server frees the node.

## Peer id of the carrying player, 0 = free. Synced. While != 0 every peer places the chicken at the
## carrier's `carry_socket`.
var carrier_id := 0
## True while inside a hide spot. Synced.
var is_hidden := false

@onready var health: Health = $Health


func _ready() -> void:
	health.max_hp = 1.0
	health.died.connect(_on_died)


func _on_died(killer_id: int, _cause: StringName) -> void:
	GameEvents.chicken_killed.emit(killer_id, global_position)
	if Net.is_server(self):
		queue_free()


## Carryable: can a player pick this up right now?
func can_be_carried() -> bool:
	return health.is_alive and carrier_id == 0


## Carryable: carrier speed multiplier while carrying this.
func carry_speed_multiplier() -> float:
	return 0.85 # TODO(S06): from ChickenTuning.carry_speed_mult


## Carryable, NET: server only.
func on_picked_up(_carrier: Node3D) -> void:
	pass # TODO(S06)


## Carryable, NET: server only. `impulse` = throw velocity (zero for a plain drop).
func on_dropped(_pos: Vector3, _impulse: Vector3) -> void:
	pass # TODO(S06)


## Carryable, NET: server only.
func on_hidden(_spot: Node3D) -> void:
	pass # TODO(S06)


## Carryable, NET: server only. Found by the mage or taken out by a villager.
func on_unhidden() -> void:
	pass # TODO(S06)
