class_name FirestormTuning
extends Tuning
## Firestorm balance settings. Owner: S14. Loaded on all peers; used by the server.
## Instance: tuning_firestorm.tres. CLI overrides: --tune=firestorm.<property>=<value>.

## TUNE: Seconds into HUNT before the storm activates.
@export var start_time := 120.0
## TUNE: Number of stages over the remaining HUNT.
@export var stage_count := 4
## TUNE: Seconds of HUD warning before a stage starts.
@export var warning_time := 15.0
## TUNE: Initial safe-zone radius in meters.
@export var start_radius := 90.0
## TUNE: Final safe-zone radius in meters.
@export var final_radius := 12.0
## TUNE: HP lost per second outside the zone for a villager.
@export var damage_per_second := 10.0
## TUNE: Consecutive seconds below the threshold before the storm kills the mage.
@export var mage_grace_time := 10.0
