class_name SpectatorManager
extends Node3D
## Dead/late-join players watch from a top-down camera with limited vision. Owner: S11.
## Registered as GameEvents.system(&"spectator").
## NET: local only (each peer handles its own view). Reacts to GameEvents.player_died / player_revived for
## the local player and to role SPECTATOR. The corpse look is done by Player itself.
## Public API: `is_spectating`, `enter_spectator()`, `exit_spectator()`.

## True while the local view is the spectator camera.
var is_spectating := false
var tuning: SpectatorTuning

func _enter_tree() -> void:
	GameEvents.register_system(&"spectator", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/spectator/tuning_spectator.tres", "spectator") as SpectatorTuning


## Switch the local view to the spectator camera.
func enter_spectator() -> void:
	pass # TODO(S11)


## Give the view back to the local player's camera.
func exit_spectator() -> void:
	pass # TODO(S11)
