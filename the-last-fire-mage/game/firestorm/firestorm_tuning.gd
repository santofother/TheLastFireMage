class_name FirestormTuning
extends Tuning
## Tuning for firestorm. Owner: S14. Instance: `tuning_firestorm.tres`. `--tune=` section: "firestorm".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var start_time := 120.0 ## TUNE: s into HUNT
@export var stage_count := 4 ## TUNE: stages
@export var warning_time := 15.0 ## TUNE: s before a stage
@export var start_radius := 90.0 ## TUNE: m
@export var final_radius := 12.0 ## TUNE: m
@export var damage_per_second := 10.0 ## TUNE: hp/s outside the zone
@export var mage_grace_time := 10.0 ## TUNE: s below required power before the storm kills the mage
