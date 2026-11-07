class_name ChickenTuning
extends Tuning
## Tuning for chicken. Owner: S06. Instance: `tuning_chicken.tres`. `--tune=` section: "chicken".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var count := 10 ## TUNE: chickens per round
@export var max_hp := 1.0 ## TUNE: one hit kills
@export var walk_speed := 1.5 ## TUNE: m/s
@export var flee_speed := 4.0 ## TUNE: m/s
@export var flee_radius := 4.0 ## TUNE: m
@export var noise_radius := 12.0 ## TUNE: m, cluck audible range
@export var carry_speed_mult := 0.85 ## TUNE: carrier speed while carrying
@export var respawn_time := 0.0 ## TUNE: s, 0 = no respawn
