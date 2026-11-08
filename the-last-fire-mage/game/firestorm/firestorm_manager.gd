class_name FirestormManager
extends Node3D
## Shrinking safe zone and mage power threshold. Owner: S14.
## NET: server decides the plan, stages, warnings and damage. Peers animate from reliable snapshots.
## Public API: stage, zone_center, zone_radius, final_zone_center, final_zone_radius, is_inside(),
## required_power(), and GameEvents.firestorm_stage / firestorm_warning.

const _VISUAL := preload("res://game/firestorm/firestorm_visual.gd")
const _CAUSE := &"firestorm"
const _DAMAGE_INTERVAL := 0.5
const _INACTIVE_RADIUS := 1000.0
const _FALLBACK_THRESHOLDS := [0.0, 3.0, 6.0, 10.0]

## Current stage (0 = storm not started).
var stage := 0
## Current safe-zone center in world space, interpolated on every peer.
var zone_center := Vector3.ZERO
## Current safe-zone radius in meters, interpolated on every peer.
var zone_radius := _INACTIVE_RADIUS
## Destination announced as soon as the HUNT begins.
var final_zone_center := Vector3.ZERO
## Destination radius in meters.
var final_zone_radius := 0.0
## Local tuning copy with CLI overrides; the server decides which settings are in effect.
var tuning: FirestormTuning

var _visual: Node3D
var _start_center := Vector3.ZERO
var _start_radius := 0.0
var _start_time := 0.0
var _stage_duration := 0.0
var _stage_count := 0
var _elapsed := 0.0
var _required := 0.0
var _warned_stage := 0
var _damage_time := 0.0
var _below_threshold := 0.0


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
	var radius := maxf(1.0, tuning.start_radius)
	var final_radius := clampf(tuning.final_radius, 0.5, radius)
	var destination := _choose_destination(origin, radius - final_radius)
	var start := maxf(0.0, tuning.start_time)
	var count := maxi(1, tuning.stage_count)
	Net.broadcast(self, &"_rpc_plan", [origin, radius, destination, final_radius, start,
		(duration - start) / count, count, 0.0])


func _choose_destination(origin: Vector3, max_offset: float) -> Vector3:
	# WHY: spawn markers give every map reachable final areas without requiring new map content.
	# Keep the final disk inside the initial one so no land becomes safe again as it moves.
	var candidates: Array[Vector3] = []
	for marker in get_tree().get_nodes_in_group(&"villager_spawn"):
		if marker is Node3D:
			var pos: Vector3 = marker.global_position
			pos.y = origin.y
			if pos.distance_squared_to(origin) <= max_offset * max_offset:
				candidates.append(pos)
	return origin if candidates.is_empty() else candidates.pick_random()


func _process(delta: float) -> void:
	_elapsed += delta
	if Net.is_server(self):
		while stage < _stage_count and _elapsed >= _stage_start(stage + 1):
			var next := stage + 1
			Net.broadcast(self, &"_rpc_stage", [next, _threshold_for(next), _elapsed])
		if stage < _stage_count and _warned_stage != stage + 1:
			var seconds := _stage_start(stage + 1) - _elapsed
			if seconds <= tuning.warning_time:
				Net.broadcast(self, &"_rpc_warning", [stage + 1, seconds])
	if stage == 0:
		return
	_update_zone()
	if Net.is_server(self):
		var active_delta := minf(delta, _elapsed - _start_time)
		_damage_outside(active_delta)
		# Health signals can finish the round synchronously and reset the storm.
		if stage > 0:
			_check_mage(minf(delta, _elapsed - _stage_start(stage)))


func _stage_start(number: int) -> float:
	return _start_time + (number - 1) * _stage_duration


func _update_zone() -> void:
	# The final ring finishes closing halfway through its stage, leaving time for a last stand.
	var shrink_time := _stage_duration * (0.5 if stage == _stage_count else 1.0)
	var fraction := clampf((_elapsed - _stage_start(stage)) / shrink_time, 0.0, 1.0)
	var progress := (stage - 1 + fraction) / _stage_count
	zone_center = _start_center.lerp(final_zone_center, progress)
	zone_radius = lerpf(_start_radius, final_zone_radius, progress)
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
		for mage in Players.alive_with_role(Enums.Role.MAGE):
			mage.health.kill(0, _CAUSE)


func _on_registered(id: int, _player_name: String) -> void:
	if _stage_count == 0 or not Net.is_server(self) or id == multiplayer.get_unique_id():
		return
	_rpc_plan.rpc_id(id, _start_center, _start_radius, final_zone_center, final_zone_radius,
		_start_time, _stage_duration, _stage_count, _elapsed)
	if stage > 0:
		_rpc_stage.rpc_id(id, stage, _required, _elapsed)
	if _warned_stage == stage + 1:
		_rpc_warning.rpc_id(id, _warned_stage, maxf(0.0, _stage_start(_warned_stage) - _elapsed))


func _on_session_ended(_reason: String) -> void:
	_reset()


func _reset() -> void:
	set_process(false)
	stage = 0
	zone_center = Vector3.ZERO
	zone_radius = _INACTIVE_RADIUS
	final_zone_center = Vector3.ZERO
	final_zone_radius = 0.0
	_stage_count = 0
	_required = 0.0
	_warned_stage = 0
	_damage_time = 0.0
	_below_threshold = 0.0
	if _visual:
		_visual.clear_zone()


@rpc("authority", "call_local", "reliable")
func _rpc_plan(origin: Vector3, radius: float, destination: Vector3, final_radius: float,
		start: float, interval: float, count: int, elapsed: float) -> void:
	_reset()
	_start_center = origin
	_start_radius = radius
	final_zone_center = destination
	final_zone_radius = final_radius
	_start_time = start
	_stage_duration = interval
	_stage_count = count
	_elapsed = elapsed
	if _visual:
		_visual.set_destination(destination, final_radius)
	set_process(true)


@rpc("authority", "call_local", "reliable")
func _rpc_stage(next: int, threshold: float, elapsed: float) -> void:
	stage = next
	_required = threshold
	_elapsed = elapsed
	_update_zone()
	var target := float(stage) / _stage_count
	var until_next := maxf(0.0, _stage_start(stage + 1) - _elapsed) if stage < _stage_count else 0.0
	GameEvents.firestorm_stage.emit(stage, _start_center.lerp(final_zone_center, target),
		lerpf(_start_radius, final_zone_radius, target), _required, until_next)


@rpc("authority", "call_local", "reliable")
func _rpc_warning(next: int, seconds: float) -> void:
	_warned_stage = next
	GameEvents.firestorm_warning.emit(next, seconds)
