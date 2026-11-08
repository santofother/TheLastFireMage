class_name PlayerTuning
extends Tuning
## Movement/body numbers for one role. Owner: S03. Files: `tuning_villager.tres`, `tuning_mage.tres`.
## Sections for `--tune=`: "villager" and "mage" (e.g. `--tune=villager.walk_speed=5`).

@export var height := 1.0 ## TUNE: m (GDD: villager 1.0, mage 1.4)
@export var radius := 0.3 ## TUNE: m
@export var walk_speed := 4.0 ## TUNE: m/s
@export var sprint_speed := 6.5 ## TUNE: m/s
@export var jump_velocity := 4.85 ## TUNE: m/s (~1.2 m jump at default gravity)
@export var max_hp := 100.0 ## TUNE
@export var camera_height := 0.9 ## TUNE: camera pivot height above feet, m

## TUNE: lowest wall sample above airborne feet, m.
@export var mantle_probe_height := 0.1
## TUNE: horizontal reach beyond the capsule, m.
@export var mantle_reach := 0.45
## TUNE: maximum ledge rise above current airborne feet, m.
@export var mantle_max_rise := 1.0
## TUNE: clearance above and inside the ledge, m.
@export var mantle_clearance := 0.05
