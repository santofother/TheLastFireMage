class_name PowerTuning
extends Tuning
## Tuning for power. Owner: S13. Instance: `tuning_power.tres`. `--tune=` section: "power".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var per_chicken := 1.0 ## TUNE: power per chicken kill
@export var per_villager := 3.0 ## TUNE: power per villager kill
@export var tier_thresholds := PackedFloat32Array([0.0, 3.0, 6.0, 10.0]) ## TUNE: power needed per tier
@export var tier_multipliers := PackedFloat32Array([1.0, 1.25, 1.5, 2.0]) ## TUNE: fire multiplier per tier (guess)
@export var decay_percent := 1.0 ## TUNE: % effectiveness lost per interval
@export var decay_interval := 5.0 ## TUNE: s
