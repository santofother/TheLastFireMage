class_name InteractManager
extends Node
## Server-side bookkeeping for interactions: who carries what, one carrier at a time. Owner: S10.
## Registered as GameEvents.system(&"interact").
## NET: server only decides; results reach peers through the carried object's own synced state
## (e.g. Chicken.carrier_id) and GameEvents.carry_changed.
## Public API: `carried_by(peer_id) -> Node`, `carrier_of(obj) -> int`.

func _enter_tree() -> void:
	GameEvents.register_system(&"interact", self)


## What a player carries (null = nothing). Server only.
func carried_by(_peer_id: int) -> Node:
	return null # TODO(S10)


## Peer id carrying `obj` (0 = nobody). Server only.
func carrier_of(_obj: Node) -> int:
	return 0 # TODO(S10)
