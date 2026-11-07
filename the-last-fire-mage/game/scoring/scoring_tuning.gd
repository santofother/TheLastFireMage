class_name ScoringTuning
extends Tuning
## Tuning for scoring. Owner: S16. Instance: `tuning_scoring.tres`. `--tune=` section: "scoring".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var mage_per_kill := 100 ## TUNE: points
@export var mage_win_bonus := 200 ## TUNE: points
@export var villager_per_10s := 5 ## TUNE: points per 10 s survived
@export var villager_win_bonus := 150 ## TUNE: points
