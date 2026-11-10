class_name FirestormManager
extends Node3D
## Shrinking safe zone and mage power threshold. Owner: S14.
## Rings (Fortnite-style): `tuning.ring_count` circles, ring 1 covers ~first_ring_fraction of the map at a random
## spot, each next ring is a random circle inside the previous one, and the last covers final_ring_fraction of
## the map (it never closes to a point). Stage k = the storm closing from ring k-1 onto ring k.
## NET: server decides the plan, stages, warnings and damage. Peers animate the current shrink from reliable snapshots.
## Public API: stage, ring_count(), zone_center, zone_radius, final_zone_center, final_zone_radius, is_inside(),
## required_power(), ring_fraction(k), and GameEvents.firestorm_stage / firestorm_warning.

const _VISUAL := preload("res://game/firestorm/firestorm_visual.gd")
const _CAUSE := &"firestorm"
const _DAMAGE_INTERVAL := 0.5
const _INACTIVE_RADIUS := 1000.0
const _FALLBACK_THRESHOLDS := [0.0, 3.0, 6.0]
const _MAX_THRESHOLD_INDEX := 2 # WHY: the last ring keeps the old final-stage requirement (tier 3), whatever the ring count

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
var _map_origin := Vector3.ZERO
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
## TUNE: seconds between "you're outside the next ring" pings while the zone closes.
const _OUT_PING_EVERY := 10.0
const _OUT_PING_SHOW := 3.0
var _out_ping_clock := 0.0
var _out_ping_label: Label
var _out_ping_left := 0.0
var _final_stage := 3 # NET: server copy of ring_count for this round; peers learn it in _rpc_stage


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


## Number of rings (stages) this round.
func ring_count() -> int:
	return _final_stage


## Fraction of tuning.map_area that ring `k` (1-based) covers: geometric from first to final fraction.
func ring_fraction(k: int) -> float:
	var n := maxi(1, tuning.ring_count)
	if n == 1:
		return tuning.final_ring_fraction
	var t := float(clampi(k, 1, n) - 1) / float(n - 1)
	return tuning.first_ring_fraction * pow(tuning.final_ring_fraction / tuning.first_ring_fraction, t)


func _on_phase(phase: int, duration: float) -> void:
	if phase != Enums.Phase.HUNT:
		_reset()
		return
	if not Net.is_server(self) or duration <= 0.0 or tuning.start_time >= duration:
		return

	var main := GameEvents.system(&"main")
	var map: Node3D = main.get_map() if main else null
	var origin := map.global_position if map else global_position
	_final_stage = maxi(1, tuning.ring_count)
	var start := maxf(0.0, tuning.start_time)
	var hold := clampf(tuning.final_hold_time, 0.0, (duration - start) * 0.5)
	var closed := duration - hold
	# Rings close one after another, evenly spread from start_time until the final hold.
	_boundaries.clear()
	for i in _final_stage + 1:
		_boundaries.append(lerpf(start, closed, float(i) / float(_final_stage)))
	_map_origin = origin
	_target_center = origin
	_target_radius = maxf(1.0, tuning.start_radius)
	set_process(true)


## Random center for a ring of `radius` inside the disk (center, outer). Prefers centers on the playable
## rectangle (tuning.map_size around the map origin) so rings don't drift out over the sea.
func _random_center(center: Vector3, outer: float, radius: float) -> Vector3:
	var max_offset := maxf(0.0, outer - radius)
	var half := tuning.map_size * 0.5
	for i in 32:
		var angle := randf() * TAU
		var pos := center + Vector3(cos(angle), 0.0, sin(angle)) * max_offset * sqrt(randf())
		if absf(pos.x - _map_origin.x) <= half.x and absf(pos.z - _map_origin.z) <= half.y:
			return pos
	return center


func _process(delta: float) -> void:
	_stage_elapsed += delta
	if Net.is_server(self):
		_hunt_elapsed += delta
		while stage < _final_stage and _hunt_elapsed >= _boundaries[stage]:
			_start_next_stage()
		if stage < _final_stage and _warned_stage != stage + 1:
			var seconds := _boundaries[stage] - _hunt_elapsed
			if seconds <= tuning.warning_time:
				Net.broadcast(self, &"_rpc_warning", [stage + 1, seconds])
	if stage == 0:
		return
	_update_zone()
	_out_of_ring_ping(delta)
	if Net.is_server(self):
		_damage_outside(minf(delta, _hunt_elapsed - _boundaries[0]))
		# Health signals can finish the round synchronously and reset the storm.
		if stage > 0:
			_check_mage(minf(delta, _stage_elapsed))


## NET: local only (each peer, own player). While the zone is still closing, tells a living player standing
## outside the NEXT ring (target) to move, at most every _OUT_PING_EVERY seconds.
func _out_of_ring_ping(delta: float) -> void:
	if _out_ping_label != null and _out_ping_left > 0.0:
		_out_ping_left -= delta
		_out_ping_label.modulate.a = clampf(_out_ping_left, 0.0, 1.0)
		_out_ping_label.visible = _out_ping_left > 0.0
	var me := Players.local_player() as Player
	var closing := _stage_elapsed < _shrink_time
	var outside := me != null and me.is_alive and me.role != Enums.Role.SPECTATOR \
		and Vector2(me.global_position.x - _target_center.x, me.global_position.z - _target_center.z).length() > _target_radius
	if not closing or not outside:
		_out_ping_clock = 0.0
		return
	_out_ping_clock -= delta
	if _out_ping_clock > 0.0:
		return
	_out_ping_clock = _OUT_PING_EVERY
	print("[Firestorm] out-of-ring ping")
	if DisplayServer.get_name() == "headless":
		return
	if _out_ping_label == null:
		var layer := CanvasLayer.new()
		add_child(layer)
		_out_ping_label = Label.new()
		_out_ping_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_out_ping_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_out_ping_label.position.y = 90.0
		_out_ping_label.add_theme_font_size_override(&"font_size", 26)
		_out_ping_label.add_theme_color_override(&"font_color", Color(1.0, 0.55, 0.2))
		_out_ping_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		_out_ping_label.add_theme_constant_override(&"outline_size", 8)
		layer.add_child(_out_ping_label)
	_out_ping_label.text = "You are outside the next safe ring - move in!"
	_out_ping_left = _OUT_PING_SHOW
	_out_ping_label.visible = true


func _start_next_stage() -> void:
	var next := stage + 1
	var radius := clampf(sqrt(maxf(0.0, tuning.map_area) * ring_fraction(next) / PI), 0.5, _target_radius)
	var center := _random_center(_target_center, _target_radius, radius)
	Net.broadcast(self, &"_rpc_stage", [next, _threshold_for(next), _target_center, _target_radius,
		center, radius, _boundaries[next] - _boundaries[stage], _hunt_elapsed - _boundaries[stage], _final_stage])


func _update_zone() -> void:
	var fraction := clampf(_stage_elapsed / _shrink_time, 0.0, 1.0)
	zone_center = _start_center.lerp(_target_center, fraction)
	zone_radius = lerpf(_start_radius, _target_radius, fraction)
	if _visual:
		_visual.set_zone(zone_center, zone_radius, stage)


func _threshold_for(number: int) -> float:
	# Spread the rings over power tiers 1..3 (index 0..2) so more rings don't demand more power.
	var index := _MAX_THRESHOLD_INDEX
	if _final_stage > 1:
		index = roundi(float(number - 1) * _MAX_THRESHOLD_INDEX / float(_final_stage - 1))
	var power := GameEvents.system(&"power") as PowerManager
	if power and not power.tuning.tier_thresholds.is_empty():
		var thresholds := power.tuning.tier_thresholds
		return thresholds[mini(index, thresholds.size() - 1)]
	return _FALLBACK_THRESHOLDS[mini(index, _FALLBACK_THRESHOLDS.size() - 1)]


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
			_target_radius, _shrink_time, _stage_elapsed, _final_stage)
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
	_out_ping_clock = 0.0
	_out_ping_left = 0.0
	if _out_ping_label != null:
		_out_ping_label.visible = false
	if _visual:
		_visual.clear_zone()


@rpc("authority", "call_local", "reliable")
func _rpc_stage(next: int, threshold: float, origin: Vector3, radius: float,
		target: Vector3, target_radius: float, shrink_time: float, elapsed: float, rings: int) -> void:
	stage = next
	_final_stage = rings
	_required = threshold
	_start_center = origin
	_start_radius = radius
	_target_center = target
	_target_radius = target_radius
	_shrink_time = maxf(0.001, shrink_time)
	_stage_elapsed = elapsed
	if stage == _final_stage:
		final_zone_center = target
		final_zone_radius = target_radius
	set_process(true)
	_update_zone()
	var until_next := maxf(0.0, shrink_time - elapsed) if stage < _final_stage else 0.0
	GameEvents.firestorm_stage.emit(stage, target, target_radius, _required, until_next)


@rpc("authority", "call_local", "reliable")
func _rpc_warning(next: int, seconds: float) -> void:
	_warned_stage = next
	GameEvents.firestorm_warning.emit(next, seconds)
