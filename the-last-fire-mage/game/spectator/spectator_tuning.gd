class_name SpectatorTuning
extends Tuning
## Tuning for spectator. Owner: S11. Instance: `tuning_spectator.tres`. `--tune=` section: "spectator".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var vision_radius := 11.0 ## TUNE: m of map visible under the ghost
@export var fog_edge := 5.0 ## TUNE: m width of the fog fade at the radius
@export var camera_height := 24.0 ## TUNE: m, glass layer height: ~5 m above the tallest town structure (~19 m)
@export var move_speed := 7.0 ## TUNE: m/s (sprint doubles it). Was 15: too fast to follow the action
@export var camera_distance := 7.0 ## TUNE: m behind the ghost
@export var mouse_sensitivity := 0.0025
@export var ping_interval := 15.0 ## TUNE: s between pings that mark every living player for dead spectators
@export var ping_duration := 4.0 ## TUNE: s each ping stays on screen
