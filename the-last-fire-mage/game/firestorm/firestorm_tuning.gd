class_name FirestormTuning
extends Tuning
## Firestorm balance settings. Owner: S14. Loaded on all peers; used by the server.
## Instance: tuning_firestorm.tres. CLI overrides: --tune=firestorm.<property>=<value>.

## TUNE: Seconds into HUNT before the storm activates.
@export var start_time := 30.0
## TUNE: Number of storm rings. Each ring is a random circle inside the previous one; the storm closes onto it.
@export var ring_count := 4
## TUNE: Fraction of map_area the first ring covers ("most of the map").
@export var first_ring_fraction := 0.8
## TUNE: Fraction of map_area the last ring covers. The storm never closes to a point.
@export var final_ring_fraction := 0.3
## TUNE: Seconds spent in the closed final circle at the end of HUNT.
@export var final_hold_time := 30.0
## TUNE: Seconds of HUD warning before a stage starts.
@export var warning_time := 15.0
## TUNE: Initial safe-zone radius in meters (covers the whole town: half-diagonal of 71 x 136 m is ~77 m).
@export var start_radius := 80.0
## TUNE: Playable area in square meters. Measured town bounds are ~71 m (x) by ~136 m (z) = ~9700 m².
## WHY: was 22500 (assumed 150 x 150), which made the "25 %" final circle cover ~58 % of the real town.
@export var map_area := 9700.0
## TUNE: Playable rectangle size (x, z) around the map origin. Ring centers are kept inside it when possible.
@export var map_size := Vector2(71.0, 136.0)
## TUNE: HP lost per second outside the zone for a villager.
@export var damage_per_second := 10.0
## TUNE: HP lost per second by a mage whose power is below the stage threshold.
@export var mage_damage_per_second := 10.0
## TUNE: Consecutive seconds below the threshold before the storm kills the mage.
@export var mage_grace_time := 0.0
