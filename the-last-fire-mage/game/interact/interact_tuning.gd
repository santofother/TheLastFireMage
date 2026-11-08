class_name InteractTuning
extends Tuning
## Tuning for carry/throw/search. Owner: S10. Instance: `tuning_interact.tres`. `--tune=` section: "interact".
## Per-object numbers live on the object (`Interactable.max_distance`, `HideSpot.capacity/search_time`).

@export var range_slack := 1.0 ## TUNE: m the server adds to max_distance (positions lag between peers)
@export var throw_speed := 9.0 ## TUNE: m/s along the aim
@export var throw_lift := 2.5 ## TUNE: m/s extra upward so throws arc
@export var release_forward := 0.6 ## TUNE: m in front of the carrier where drops/throws start
@export var search_pop_speed := 2.5 ## TUNE: m/s upward when a search kicks a chicken out
