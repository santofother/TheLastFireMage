class_name SpectatorTuning
extends Tuning
## Tuning for spectator. Owner: S11. Instance: `tuning_spectator.tres`. `--tune=` section: "spectator".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var vision_radius := 11.0 ## TUNE: m of map visible under the ghost
@export var fog_edge := 5.0 ## TUNE: m width of the fog fade at the radius
@export var camera_height := 30.0 ## TUNE: m, height of the one-way glass layer ghosts walk on
@export var move_speed := 15.0 ## TUNE: m/s
@export var camera_distance := 7.0 ## TUNE: m behind the ghost
@export var mouse_sensitivity := 0.0025
