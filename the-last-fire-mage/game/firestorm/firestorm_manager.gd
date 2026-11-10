class_name FirestormManager
extends Node3D
## Shrinking safe zone and mage power threshold. Owner: S14.
## NET: server decides the plan, stages, warnings and damage. Peers animate the current shrink from reliable snapshots.
## Public API: stage, zone_center, zone_radius, final_zone_center, final_zone_radius, is_inside(),
## required_power(), and GameEvents.firestorm_stage / firestorm_warning.

const _VISUAL := preload("res://game/firestorm/firestorm_visual.gd")
const _CAUSE := &"firestorm"
const _DAMAGE_INTERVAL := 0.5
const _INACTIVE_RADIUS := 1000.0
const _AREA_FRACTIONS := [0.8, 0.6, 0.25]
const _FINAL_STAGE := 3
const _FALLBACK_THRESHOLDS := [0.0, 3.0, 6.0]

## Current stage (0 = storm not started).
var stage := 0
## Current safe-zone center in world space, interpolated on every peer.
var zone_center := Vector3.ZERO
## Current safe-zone radius in meters, interpolated on every peer.
var zone_radius := _INACTIVE_RADIUS
## Destination announced when the final shrink starts.
var final_zone_center := Vector3.ZERO
## Destination radius in meters.
var final_zone_radius := 0.0
## Local tuning copy with CLI overrides; the server decides which settings are in effect.
var tuning: FirestormTuning

var _visual: Node3D
var _start_center := Vector3.ZERO
var _start_radius := 0.0
var _target_center := Vector3.ZERO
var _target_radius := 0.0
var _shrink_time := 0.0
var _stage_elapsed := 0.0
var _hunt_elapsed := 0.0
var _boundaries: Array[float] = []
var _required := 0.0
var _warned_stage := 0
var _damage_time := 0.0
var _below_threshold := 0.0
var _mage_tick := 0.0


func _enter_tree() -> void:
	GameEvents.register_system(&"firestorm", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/firestorm/tuning_firestorm.tres", "firestorm") as FirestormTuning
	if DisplayServer.get_name() != "headless":
		_visual = _VISUAL.new()
		add_child(_visual)
	GameEvents.phase_changed.connect(_on_phase)
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.session_ended.connect(_on_session_ended)
	set_process(false)


## True when the horizontal position is in the safe zone, or while the storm is inactive.
func is_inside(pos: Vector3) -> bool:
	var offset := Vector2(pos.x - zone_center.x, pos.z - zone_center.z)
	return stage == 0 or offset.length_squared() <= zone_radius * zone_radius


## Power the mage must hold this stage. Any peer.
func required_power() -> float:
	return _required


func _on_phase(phase: int, duration: float) -> void:
	if phase != Enums.Phase.HUNT:
		_reset()
		return
	if not Net.is_server(self) or duration <= 0.0 or tuning.start_time >= duration:
		return

	var main := GameEvents.system(&"main")
	var map: Node3D = main.get_map() if main else null
	var origin := map.global_position if map else global_position
	var start := maxf(0.0, tuning.start_time)
	var second := start + clampf(tuning.second_stage_delay, 0.0, (duration - start) * 0.4)
	var hold := clampf(tuning.final_hold_time, 0.0, (duration - second) / 3.0)
	_boundaries = [start, second, duration - 2.0 * hold, duration - hold]
	_target_center = origin
	_target_radius = maxf(1.0, tuning.start_radius)
	set_process(true)


func _choose_destination(origin: Vector3, max_offset: float) -> Vector3:
	# Spawn markers give reachable final areas. Limit travel to keep each disk inside the last one.
	var candidates: Array[Vector3] = []
	for marker in get_tree().get_nodes_in_group(&"villager_spawn"):
		if marker is Node3D:
			var pos: Vector3 = marker.global_position
			pos.y = origin.y
			if pos.distance_squared_to(origin) <= max_offset * max_offset:
				candidates.append(pos)
	return origin if candidates.is_empty() else candidates.pick_random()


func _process(delta: float) -> void:
	_stage_elapsed += delta
	if Net.is_server(self):
		_hunt_elapsed += delta
		while stage < _FINAL_STAGE and _hunt_elapsed >= _boundaries[stage]:
			_start_next_stage()
		if stage < _FINAL_STAGE and _warned_stage != stage + 1:
			var seconds := _boundaries[stage] - _hunt_elapsed
			if seconds <= tuning.warning_time:
				Net.broadcast(self, &"_rpc_warning", [stage + 1, seconds])
	if stage == 0:
		return
	_update_zone()
	if Net.is_server(self):
		_damage_outside(minf(delta, _hunt_elapsed - _boundaries[0]))
		# Health signals can finish the round synchronously and reset the storm.
		if stage > 0:
			_check_mage(minf(delta, _stage_elapsed))


func _start_next_stage() -> void:
	var next := stage + 1
	var radius := clampf(sqrt(maxf(0.0, tuning.map_area) * _AREA_FRACTIONS[stage] / PI),
		0.5, _target_radius)
	var center := _target_center
	if next == _FINAL_STAGE:
		center = _choose_destination(center, _target_radius - radius)
	Net.broadcast(self, &"_rpc_stage", [next, _threshold_for(next), _target_center, _target_radius,
		center, radius, _boundaries[next] - _boundaries[stage], _hunt_elapsed - _boundaries[stage]])


func _update_zone() -> void:
	var fraction := clampf(_stage_elapsed / _shrink_time, 0.0, 1.0)
	zone_center = _start_center.lerp(_target_center, fraction)
	zone_radius = lerpf(_start_radius, _target_radius, fraction)
	if _visual:
		_visual.set_zone(zone_center, zone_radius, stage)


func _threshold_for(number: int) -> float:
	var power := GameEvents.system(&"power") as PowerManager
	if power and not power.tuning.tier_thresholds.is_empty():
		var thresholds := power.tuning.tier_thresholds
		return thresholds[mini(number - 1, thresholds.size() - 1)]
	return _FALLBACK_THRESHOLDS[mini(number - 1, _FALLBACK_THRESHOLDS.size() - 1)]


func _damage_outside(delta: float) -> void:
	_damage_time += delta
	if _damage_time < _DAMAGE_INTERVAL:
		return
	var seconds := floorf(_damage_time / _DAMAGE_INTERVAL) * _DAMAGE_INTERVAL
	_damage_time -= seconds
	for player in Players.alive_with_role(Enums.Role.VILLAGER):
		if not is_inside(player.global_position):
			player.health.apply_damage(tuning.damage_per_second * seconds, 0, _CAUSE)
			if stage == 0:
				return


func _check_mage(delta: float) -> void:
	var power := GameEvents.system(&"power") as PowerManager
	if (power.current_power() if power else 0.0) >= _required:
		_below_threshold = 0.0
		return
	_below_threshold += delta
	if _below_threshold >= tuning.mage_grace_time:
		# Drain HP in half-second ticks instead of killing outright; power gains stop it.
		_mage_tick += delta
		if _mage_tick < _DAMAGE_INTERVAL:
			return
		var seconds := floorf(_mage_tick / _DAMAGE_INTERVAL) * _DAMAGE_INTERVAL
		_mage_tick -= seconds
		for mage in Players.alive_with_role(Enums.Role.MAGE):
			mage.health.apply_damage(tuning.mage_damage_per_second * seconds, 0, _CAUSE)


func _on_registered(id: int, _player_name: String) -> void:
	if _boundaries.is_empty() or not Net.is_server(self) or id == multiplayer.get_unique_id():
		return
	if stage > 0:
		_rpc_stage.rpc_id(id, stage, _required, _start_center, _start_radius, _target_center,
			_target_radius, _shrink_time, _stage_elapsed)
	if _warned_stage == stage + 1:
		_rpc_warning.rpc_id(id, _warned_stage, maxf(0.0, _boundaries[stage] - _hunt_elapsed))


func _on_session_ended(_reason: String) -> void:
	_reset()


func _reset() -> void:
	set_process(false)
	stage = 0
	zone_center = Vector3.ZERO
	zone_radius = _INACTIVE_RADIUS
	final_zone_center = Vector3.ZERO
	final_zone_radius = 0.0
	_boundaries.clear()
	_hunt_elapsed = 0.0
	_required = 0.0
	_warned_stage = 0
	_damage_time = 0.0
	_below_threshold = 0.0
	_mage_tick = 0.0
	if _visual:
		_visual.clear_zone()


@rpc("authority", "call_local", "reliable")
func _rpc_stage(next: int, threshold: float, origin: Vector3, radius: float,
		target: Vector3, target_radius: float, shrink_time: float, elapsed: float) -> void:
	stage = next
	_required = threshold
	_start_center = origin
	_start_radius = radius
	_target_center = target
	_target_radius = target_radius
	_shrink_time = maxf(0.001, shrink_time)
	_stage_elapsed = elapsed
	if stage == _FINAL_STAGE:
		final_zone_center = target
		final_zone_radius = target_radius
	set_process(true)
	_update_zone()
	var until_next := maxf(0.0, shrink_time - elapsed) if stage < _FINAL_STAGE else 0.0
	GameEvents.firestorm_stage.emit(stage, target, target_radius, _required, until_next)


@rpc("authority", "call_local", "reliable")
func _rpc_warning(next: int, seconds: float) -> void:
	_warned_stage = next
	GameEvents.firestorm_warning.emit(next, seconds)
