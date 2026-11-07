class_name FirestormManager
extends Node3D
## Shrinking safe zone + mage power threshold. Owner: S14. Registered as GameEvents.system(&"firestorm").
## NET: server runs stages and damage (Health.apply_damage / kill with cause &"firestorm"); fires
## GameEvents.firestorm_stage / firestorm_warning on all peers; zone values synced for visuals/HUD.
## Reads the mage's power from `GameEvents.system(&"power").current_power()`.
## Public API: `stage`, `zone_center`, `zone_radius`, `is_inside(pos)`, `required_power()`.

## Current stage (0 = storm not started).
var stage := 0
var zone_center := Vector3.ZERO
var zone_radius := 1000.0
var tuning: FirestormTuning

func _enter_tree() -> void:
	GameEvents.register_system(&"firestorm", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/firestorm/tuning_firestorm.tres", "firestorm") as FirestormTuning


## True if `pos` is inside the safe zone (XZ distance). Any peer.
func is_inside(pos: Vector3) -> bool:
	return Vector2(pos.x - zone_center.x, pos.z - zone_center.z).length() <= zone_radius


## Power the mage must hold this stage. Any peer.
func required_power() -> float:
	return 0.0 # TODO(S14)
