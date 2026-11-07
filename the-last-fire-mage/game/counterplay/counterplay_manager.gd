class_name CounterplayManager
extends Node3D
## Villager tools to briefly stop the mage: items at `item_spawn`, environment pieces. Owner: S15.
## Registered as GameEvents.system(&"counterplay").
## NET: server validates hits and applies effects through Player.stun / set_speed_modifier.
## Public API: `request_stun(target, seconds, source_id)` (diminishing returns; dead-player items in
## wave 4 can reuse it).

var tuning: CounterplayTuning

func _enter_tree() -> void:
	GameEvents.register_system(&"counterplay", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/counterplay/tuning_counterplay.tres", "counterplay") as CounterplayTuning


## NET: server only. Stuns `target` (a Player) with diminishing returns. Returns the seconds applied.
func request_stun(_target: Node, _seconds: float, _source_id: int) -> float:
	return 0.0 # TODO(S15)
