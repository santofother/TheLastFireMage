class_name ChickenTuning
extends Tuning
## Tuning for chicken. Owner: S06. Instance: `tuning_chicken.tres`. `--tune=` section: "chicken".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var count := 10 ## TUNE: chickens per round
@export var max_hp := 1.0 ## TUNE: one hit kills
@export var walk_speed := 1.5 ## TUNE: m/s
@export var flee_speed := 4.0 ## TUNE: m/s
@export var flee_radius := 4.0 ## TUNE: m, a living player this close scares the chicken
@export var flee_distance := 6.0 ## TUNE: m, how far a scared chicken runs before re-checking
@export var calm_time := 1.5 ## TUNE: s, stays scared this long after the last threat left
@export var wander_radius := 8.0 ## TUNE: m, wander targets are picked this far around the chicken
@export var idle_time_min := 1.5 ## TUNE: s, pecking pause between wander legs
@export var idle_time_max := 4.0 ## TUNE: s
@export var noise_radius := 12.0 ## TUNE: m, cluck audible range
@export var cluck_interval_min := 3.0 ## TUNE: s, calm cluck spacing
@export var cluck_interval_max := 8.0 ## TUNE: s
@export var scared_cluck_interval := 0.7 ## TUNE: s, average spacing while fleeing
@export var scared_cluck_db := 6.0 ## TUNE: dB louder while scared
@export var carried_cluck_mult := 2.0 ## TUNE: cluck interval multiplier while carried (clucks less)
@export var hidden_cluck_mult := 4.0 ## TUNE: cluck interval multiplier while hidden
@export var hidden_cluck_db := -10.0 ## TUNE: dB while hidden (muffled)
@export var carry_speed_mult := 0.85 ## TUNE: carrier speed while carrying
@export var respawn_time := 0.0 ## TUNE: s, 0 = no respawn; >0 = a dead chicken is replaced after this
@export var debug_beacons := true ## TUNE: tall pink pillar + "CHICKEN" label (seen through walls) on every chicken. Debug; turn off for real playtests
