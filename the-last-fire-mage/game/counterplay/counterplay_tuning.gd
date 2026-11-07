class_name CounterplayTuning
extends Tuning
## Tuning for counterplay. Owner: S15. Instance: `tuning_counterplay.tres`. `--tune=` section: "counterplay".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var stun_duration := 1.5 ## TUNE: s
@export var stun_cooldown := 20.0 ## TUNE: s per source
@export var dr_window := 8.0 ## TUNE: s, repeated stuns inside this window are shorter
@export var dr_factor := 0.5 ## TUNE: stun length multiplier per repeat
@export var item_respawn_time := 20.0 ## TUNE: s
