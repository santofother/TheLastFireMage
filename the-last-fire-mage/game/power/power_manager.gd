class_name PowerManager
extends Node
## Mage power: kills add power, tiers unlock for good, effectiveness decays to the tier floor. Owner: S13.
## Registered as GameEvents.system(&"power").
## NET: server computes; fires GameEvents.power_changed on all peers via its own RPC.
## Public API: `current_power()`, `current_tier()`, `multiplier()`, `add_power(amount, reason)`.

var tuning: PowerTuning

func _enter_tree() -> void:
	GameEvents.register_system(&"power", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/power/tuning_power.tres", "power") as PowerTuning


## Mage power now (firestorm compares this to its required power). Any peer.
func current_power() -> float:
	return 0.0 # TODO(S13)


## Unlocked tier 0..3. Any peer.
func current_tier() -> int:
	return 0 # TODO(S13)


## Fire effectiveness (1.0 = base). Any peer.
func multiplier() -> float:
	return 1.0 # TODO(S13)


## NET: server only. Adds power (e.g. test hooks; kills are counted from GameEvents by this system).
func add_power(_amount: float, _reason: StringName) -> void:
	pass # TODO(S13)
