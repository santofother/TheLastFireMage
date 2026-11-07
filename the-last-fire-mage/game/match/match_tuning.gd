class_name MatchTuning
extends Tuning
## Tuning for match. Owner: S04. Instance: `tuning_match.tres`. `--tune=` section: "match".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var role_reveal_time := 3.0 ## TUNE: s
@export var head_start_time := 30.0 ## TUNE: s (GDD)
@export var hunt_time := 360.0 ## TUNE: s (GDD says 8 min, card starts at 6)
@export var results_time := 10.0 ## TUNE: s
@export var min_players := 2 ## TUNE: players needed to start
