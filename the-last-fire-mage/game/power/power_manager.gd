class_name PowerManager
extends Node
## Mage power and permanent round tiers. Owner: S13.
## Public API: current_power(), current_tier(), multiplier(), add_power(amount, reason).
## NET: server awards/decays; reliable snapshots notify all peers, including late joiners.

var tuning: PowerTuning
var _power := 0.0
var _tier := 0
## Every mage this round. They share one power pool and tier.
var _mages: Array[int] = []
var _phase := Enums.Phase.LOBBY
var _decay_left := 0.0

func _enter_tree() -> void:
	GameEvents.register_system(&"power", self)

func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/power/tuning_power.tres", "power") as PowerTuning
	GameEvents.role_assigned.connect(_on_role)
	GameEvents.phase_changed.connect(_on_phase)
	GameEvents.chicken_killed.connect(_on_chicken)
	GameEvents.player_died.connect(_on_death)
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.session_ended.connect(_on_session_end)

## Mage power now. Any peer.
func current_power() -> float:
	return _power

## Permanently unlocked tier 0..3 for this round. Any peer.
func current_tier() -> int:
	return _tier

## Fire effectiveness interpolates toward the next tier; never below the unlocked tier base.
func multiplier() -> float:
	var base := tuning.tier_multipliers[_tier]
	if _tier + 1 >= tuning.tier_thresholds.size():
		return base
	var progress := inverse_lerp(tuning.tier_thresholds[_tier], tuning.tier_thresholds[_tier + 1], _power)
	return lerpf(base, tuning.tier_multipliers[_tier + 1], clampf(progress, 0.0, 1.0))

## NET: server only. Adds power; kill signals call this with tuned rewards.
func add_power(amount: float, _reason: StringName) -> void:
	if not Net.is_server(self) or _mages.is_empty() or amount <= 0.0 or not is_finite(amount):
		return
	_power += amount
	while _tier + 1 < tuning.tier_thresholds.size() and _power >= tuning.tier_thresholds[_tier + 1]:
		_tier += 1
	_publish()

func _process(delta: float) -> void:
	if not Net.is_server(self) or _phase != Enums.Phase.HUNT:
		return
	_decay_left -= delta
	if _decay_left <= 0.0:
		var interval := maxf(0.01, tuning.decay_interval)
		var steps := floori(-_decay_left / interval) + 1
		_decay_left += steps * interval
		_power = maxf(tuning.tier_thresholds[_tier], _power * pow(clampf(1.0 - tuning.decay_percent / 100.0, 0.0, 1.0), steps))
		_publish()

func _on_role(id: int, role: int) -> void:
	if Net.is_server(self) and role == Enums.Role.MAGE and id not in _mages:
		_mages.append(id)
		_publish()

func _on_phase(phase: int, _duration: float) -> void:
	_phase = phase
	if not Net.is_server(self):
		return
	if phase in [Enums.Phase.LOBBY, Enums.Phase.ROLE_REVEAL]:
		_power = 0.0
		_tier = 0
		if phase == Enums.Phase.LOBBY:
			_mages.clear()
		_publish()
	_decay_left = tuning.decay_interval

func _on_chicken(killer: int, _position: Vector3) -> void:
	if killer in _mages and _phase == Enums.Phase.HUNT:
		add_power(tuning.per_chicken, &"chicken")

func _on_death(victim: int, killer: int, _cause: StringName) -> void:
	# WHY: Match handles the last villager's death first and enters RESULTS during the same signal.
	if killer in _mages and victim != killer and _phase in [Enums.Phase.HUNT, Enums.Phase.RESULTS]:
		var match_system := GameEvents.system(&"match")
		if match_system and match_system.get_role(victim) == Enums.Role.VILLAGER:
			add_power(tuning.per_villager, &"villager")

func _publish() -> void:
	Net.broadcast(self, &"_rpc_state", [_mages, _power, _tier])

func _on_registered(id: int, _name: String) -> void:
	if Net.is_server(self) and Net.is_online(self) and id != multiplayer.get_unique_id():
		_rpc_state.rpc_id(id, _mages, _power, _tier)

func _on_session_end(_reason: String) -> void:
	_on_phase(Enums.Phase.LOBBY, 0.0)

@rpc("authority", "call_local", "reliable")
func _rpc_state(mage_ids: Array, power: float, tier: int) -> void:
	if mage_ids != _mages:
		VoiceManager.clear_speaker_effects() # FIX(S12, Claude): previous mage voices go back to normal
	_mages.assign(mage_ids)
	_power = power
	_tier = tier
	if _mages.is_empty():
		GameEvents.power_changed.emit(0, _power, _tier, multiplier())
		return
	# FIX(S12, Claude): mage voice distortion grows with power (0.35 at start -> 1.0 at the top threshold).
	var top := maxf(0.001, tuning.tier_thresholds[tuning.tier_thresholds.size() - 1])
	for mage in _mages:
		GameEvents.power_changed.emit(mage, _power, _tier, multiplier())
		VoiceManager.set_speaker_effect(mage, &"mage", lerpf(0.35, 1.0, clampf(_power / top, 0.0, 1.0)))
