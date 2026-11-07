class_name HideSpot
extends Node3D
## A place to hide carried chickens (crate/barrel/shed). Owner: S10. The map (S05) instances
## `hide_spot.tscn` wherever it wants one; group `hide_spot`.
## NET: server decides contents; the hidden objects sync their own `is_hidden` state.
## Public API: `capacity`, `search_time`, `hidden_objects()`.

## How many chickens fit.
@export var capacity := 2 # TUNE
## Seconds the mage needs to search it.
@export var search_time := 2.0 # TUNE


## Objects hidden here (server).
func hidden_objects() -> Array[Node]:
	return [] # TODO(S10)
