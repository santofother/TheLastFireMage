class_name FirestormTuning
extends Tuning
## Firestorm balance settings. Owner: S14. Loaded on all peers; used by the server.
## Instance: tuning_firestorm.tres. CLI overrides: --tune=firestorm.<property>=<value>.

## TUNE: Seconds into HUNT before the storm activates.
@export var start_time := 30.0
## TUNE: Seconds from the first shrink to the second.
@export var second_stage_delay := 60.0
## TUNE: Seconds spent in the closed final circle, also used for its closing time.
@export var final_hold_time := 30.0
## TUNE: Seconds of HUD warning before a stage starts.
@export var warning_time := 15.0
## TUNE: Initial safe-zone radius in meters.
@export var start_radius := 107.0
## TUNE: Reference area in square meters (the town is roughly 150 m by 150 m).
@export var map_area := 22500.0
## TUNE: HP lost per second outside the zone for a villager.
@export var damage_per_second := 10.0
## TUNE: Consecutive seconds below the threshold before the storm kills the mage.
@export var mage_grace_time := 10.0
