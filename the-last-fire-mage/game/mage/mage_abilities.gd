class_name MageAbilities
extends Node3D
## Mage knife / Ignite / Fire Wave. Owner: S09. Added under Player/Abilities by Player.set_role(MAGE)
## (see RoleScenes). Root name must stay "MageAbilities".
## NET: authority = owning peer, which reads `player.input` and sends requests to the server
## (`@rpc("any_peer")` + server validation of range/angle/cooldown/line of sight). Damage only through
## Health.apply_damage on the server.
## CONTRACT: `power_multiplier` scales fire damage/range/spread. It is updated on every peer from
## GameEvents.power_changed (S13 fires it). Default 1.0.
## Public API: `power_multiplier`, `is_ignited()`, `cooldown_left(ability)` (HUD).

## Fire effectiveness from the power system (1.0 = base).
var power_multiplier := 1.0
var tuning: MageCombatTuning


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/mage/tuning_mage_combat.tres", "mage_combat") as MageCombatTuning
	GameEvents.power_changed.connect(_on_power_changed)


func _on_power_changed(mage_id: int, _power: float, _tier: int, multiplier: float) -> void:
	var p := get_parent().get_parent() as Player
	if p and p.peer_id == mage_id:
		power_multiplier = multiplier


## True while the knife burns.
func is_ignited() -> bool:
	return false # TODO(S09)


## Seconds until `ability` (&"knife", &"ignite", &"fire_wave") is ready again (0 = ready). Any peer.
func cooldown_left(_ability: StringName) -> float:
	return 0.0 # TODO(S09)
