class_name GameSettings
extends RefCounted
## Host-adjustable balance multipliers for testing (lobby "GAME SETTINGS"). Owner: menu-testing.
## Public API: `DEFS` (what can be tuned), `mults` (id -> factor, 1.0 = 100 %), `set_mults(d)`, `reset()`,
## `register(tuning)` (called by Tuning.load_tuning so freshly loaded tuning picks the factors up).
## NET: the server's MatchManager broadcasts `mults` to every peer (rpc `_rpc_settings`); all peers apply locally.
## WHY: tuning resources are loaded once per node, so factors are applied in place on every live copy
## (base values are remembered at load time) rather than by reloading systems.

## id, label, targets = [[TuningClassName, property], ...], area = factor is applied to a radius (value * f^2).
const DEFS: Array[Dictionary] = [
	{"id": "circle", "label": "Final circle size", "targets": [["FirestormTuning", "final_ring_fraction"]], "area": true},
	{"id": "length", "label": "Total match length", "targets": [["MatchTuning", "hunt_time"],
		["FirestormTuning", "start_time"], ["FirestormTuning", "final_hold_time"]]},
	{"id": "headstart", "label": "Hiding head start", "targets": [["MatchTuning", "head_start_time"]]},
	{"id": "health", "label": "Player health", "targets": [["PlayerTuning", "max_hp"]]},
	{"id": "fall", "label": "Fall damage", "targets": [["PlayerTuning", "fall_damage_scale"]]},
	{"id": "storm", "label": "Storm damage", "targets": [["FirestormTuning", "damage_per_second"]]},
	{"id": "speed", "label": "Movement speed", "targets": [["PlayerTuning", "walk_speed"], ["PlayerTuning", "sprint_speed"]]},
	{"id": "stamina", "label": "Stamina", "targets": [["PlayerTuning", "max_stamina"]]},
	{"id": "mage_dmg", "label": "Mage damage", "targets": [["MageCombatTuning", "knife_damage"], ["MageCombatTuning", "ignite_damage"],
		["MageCombatTuning", "wave_damage"], ["MageCombatTuning", "wave_player_damage"]]},
	{"id": "chicken", "label": "Power per chicken", "targets": [["PowerTuning", "per_chicken"]]},
]

## id -> factor (1.0 = 100 %). Missing ids mean 1.0.
static var mults: Dictionary = {}
static var _live: Array[Dictionary] = [] # {res, base: {prop: value}}


## Registers a freshly loaded tuning copy and applies the current factors to it.
static func register(res: Tuning) -> void:
	var cls := _cls(res)
	var base := {}
	for def in DEFS:
		for t in def["targets"]:
			if t[0] == cls and t[1] in res:
				base[t[1]] = res.get(t[1])
	if base.is_empty():
		return
	_prune()
	_live.append({"res": res, "base": base})
	_apply_one(_live[-1])


## Replaces all factors (e.g. from the host) and re-applies them to every live tuning.
static func set_mults(d: Dictionary) -> void:
	mults = d.duplicate()
	_prune()
	for e in _live:
		_apply_one(e)
	print("[Game] settings ", mults)


## Back to 100 % everywhere.
static func reset() -> void:
	set_mults({})


## Factor for a setting id (1.0 when untouched).
static func factor(id: String) -> float:
	return float(mults.get(id, 1.0))


static func _apply_one(e: Dictionary) -> void:
	var res: Tuning = e["res"]
	var cls := _cls(res)
	for def in DEFS:
		var f := factor(def["id"])
		if bool(def.get("area", false)):
			f = f * f
		for t in def["targets"]:
			if t[0] == cls and e["base"].has(t[1]):
				res.set(t[1], type_convert(float(e["base"][t[1]]) * f, typeof(e["base"][t[1]])))


static func _cls(res: Tuning) -> String:
	var s: Script = res.get_script()
	return String(s.get_global_name()) if s else ""


static func _prune() -> void:
	_live = _live.filter(func(e: Dictionary) -> bool: return (e["res"] as Resource).get_reference_count() > 1)
