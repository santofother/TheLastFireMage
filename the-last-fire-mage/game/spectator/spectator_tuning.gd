class_name SpectatorTuning
extends Tuning
## Tuning for spectator. Owner: S11. Instance: `tuning_spectator.tres`. `--tune=` section: "spectator".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var vision_radius := 15.0 ## TUNE: m
@export var camera_height := 30.0 ## TUNE: m above ground
@export var move_speed := 15.0 ## TUNE: m/s
