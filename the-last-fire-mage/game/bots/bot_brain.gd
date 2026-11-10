class_name BotBrain
extends RefCounted
## Goal-driven input driver; assign to Player.input_driver. Owner: S07 (goals: bug-fixing-n-addiotions).
## NET: runs only on the player's authority, through fill_input(player, input, delta). It only writes
## PlayerInput (move, look, buttons), so bots drive exactly the human code path; the server still decides
## every outcome.
##
## Goals, highest priority first:
## - everyone: get back inside the firestorm safe zone (and stay away from its edge).
## - mage: chase and knife the nearest villager (downed ones too), else hunt chickens for power;
##   Ignite before closing in, Fire Wave at mid range, Locate when nobody is in sight.
## - villager: flee a nearby mage, revive a downed villager, else roam between points inside the zone.
## Stuck detection jumps and sidesteps when the bot pushes into a wall.
## When `player` is not a Player (unit tests), it falls back to the old random wander.
## `--bot-log` prints goal changes as `[Bot] <name> goal=<goal>`.

# TUNE: bot behaviour
const MAGE_CHASE_RANGE := 45.0 ## m: villagers farther than this are ignored in favour of chickens
const VILLAGER_FEAR_RANGE := 13.0 ## m: villagers flee a mage inside this
const REVIVE_RANGE := 30.0 ## m: villagers go help downed friends inside this
const ZONE_MARGIN := 6.0 ## m: stay this far inside the storm edge
const ROAM_RADIUS := 28.0 ## m: villager roam points around the zone / map centre
const ARRIVE := 1.6 ## m

var _rng := RandomNumberGenerator.new()
var _turn_in := 0.0
var _action_in := 0.0
var _move := Vector2.ZERO
var _sprint := false
var _turn := 0.0

var _roam := Vector3.INF
var _roam_left := 0.0
var _pause_left := 0.0
var _stuck_check := 0.0
var _last_pos := Vector3.INF
var _sidestep_left := 0.0
var _sidestep := 0.0
var _goal := &""


func _init() -> void:
	_rng.randomize()


## Fill held intent and one-tick actions without moving the player directly.
func fill_input(player: Node, input: PlayerInput, delta: float) -> void:
	input.clear()
	if not player is Player:
		_wander(input, delta)
		return
	var me := player as Player
	if not me.is_alive or me.health.is_downed or not me.can_control():
		return
	var target := Vector3.INF
	var sprint := false
	var zone := _zone_goal(me)
	if zone != Vector3.INF:
		target = zone
		sprint = true
		_set_goal(me, &"zone")
	elif me.role == Enums.Role.MAGE:
		var result := _mage(me, input, delta)
		target = result[0]
		sprint = result[1]
	else:
		var result := _villager(me, input, delta)
		target = result[0]
		sprint = result[1]
	if target == Vector3.INF:
		_face_pitch(me, input)
		return
	_steer(me, input, target, sprint, delta)


# ------------------------------------------------------------------ goals

## Point to run to when outside (or near the edge of) the shrinking safe zone, else INF.
func _zone_goal(me: Player) -> Vector3:
	var storm := GameEvents.system(&"firestorm") as FirestormManager
	if storm == null or storm.stage == 0:
		return Vector3.INF
	var offset := Vector2(me.global_position.x - storm.zone_center.x, me.global_position.z - storm.zone_center.z)
	var margin := minf(ZONE_MARGIN, storm.zone_radius * 0.4)
	if offset.length() <= storm.zone_radius - margin:
		return Vector3.INF
	return storm.zone_center


func _mage(me: Player, input: PlayerInput, delta: float) -> Array:
	var abilities := me.get_ability(&"MageAbilities") as MageAbilities
	var prey := _nearest_villager(me)
	var target_node: Node3D = prey
	if prey == null:
		target_node = _nearest_chicken(me)
	if target_node == null:
		_set_goal(me, &"search")
		if abilities and abilities.cooldown_left(&"locate") <= 0.0:
			input.ability_3_pressed = true
		return [_roam_point(me, delta), false]
	_set_goal(me, &"hunt_villager" if prey else &"hunt_chicken")
	var to := target_node.global_position - me.global_position
	var dist := Vector2(to.x, to.z).length()
	var facing := _facing(me, target_node.global_position)
	if abilities:
		var power := clampf(abilities.power_multiplier, 0.1, 10.0)
		var reach := abilities.tuning.knife_range * power
		if dist <= reach + 0.4 and facing > 0.85 and abilities.cooldown_left(&"knife") <= 0.0:
			input.primary = true
			input.primary_pressed = true
		if prey and dist < 7.0 and not abilities.is_ignited() and abilities.cooldown_left(&"ignite") <= 0.0:
			input.ability_1_pressed = true
		var wave := abilities.tuning.wave_range * power
		if prey and dist < wave * 0.8 and dist > reach and facing > 0.95 \
				and abilities.cooldown_left(&"fire_wave") <= 0.0:
			input.ability_2_pressed = true
	# Close the gap at a sprint, then walk the last metres so the knife lines up.
	return [target_node.global_position, dist > 3.0]


func _villager(me: Player, input: PlayerInput, delta: float) -> Array:
	var mage := _nearest_mage(me)
	if mage != null and me.global_position.distance_to(mage.global_position) < VILLAGER_FEAR_RANGE:
		_set_goal(me, &"flee")
		var away := me.global_position - mage.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		# Bias the escape toward the zone/map centre so bots don't run into the storm or the sea.
		var centre := _centre(me) - me.global_position
		centre.y = 0.0
		if centre.length() > 1.0:
			away = (away + centre.normalized() * 0.5).normalized()
		_roam = Vector3.INF
		return [me.global_position + away * 8.0, true]
	var friend := _nearest_downed(me)
	if friend != null:
		_set_goal(me, &"revive")
		var d := me.global_position.distance_to(friend.global_position)
		if d < 2.0:
			input.interact_held = true
			_turn_toward(me, input, friend.global_position, delta)
			return [Vector3.INF, false]
		return [friend.global_position, d > 6.0]
	_set_goal(me, &"roam")
	if _pause_left > 0.0:
		_pause_left -= delta
		return [Vector3.INF, false]
	return [_roam_point(me, delta), false]


# ------------------------------------------------------------------ steering

func _steer(me: Player, input: PlayerInput, target: Vector3, sprint: bool, delta: float) -> void:
	_turn_toward(me, input, target, delta)
	_face_pitch(me, input)
	var flat := Vector2(target.x - me.global_position.x, target.z - me.global_position.z)
	if flat.length() < 0.3:
		return
	# Walk forward (the body turns toward the target); slow down while turning hard.
	var facing := _facing(me, target)
	input.move = Vector2(0.0, -1.0) if facing > 0.3 else Vector2(0.0, -0.3)
	input.sprint = sprint and me.stamina > 0.5 and facing > 0.7
	_unstick(me, input, delta)


func _turn_toward(me: Player, input: PlayerInput, target: Vector3, delta: float) -> void:
	var to := target - me.global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - me.rotation.y, -PI, PI)
	# Player does rotate_y(-look_delta.x); cap the turn rate so bots look like they steer.
	input.look_delta.x = -clampf(diff, -8.0 * delta, 8.0 * delta)


func _face_pitch(me: Player, input: PlayerInput) -> void:
	# Level the camera slightly downward so the knife cone covers short villagers and chickens.
	input.look_delta.y = me.camera_rig.rotation.x + 0.12


# Pushing into a wall: after ~0.8 s of barely moving, jump and sidestep for a moment.
func _unstick(me: Player, input: PlayerInput, delta: float) -> void:
	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		input.move = Vector2(_sidestep, -0.4).normalized()
		return
	_stuck_check -= delta
	if _stuck_check > 0.0:
		return
	_stuck_check = 0.8
	var pos := me.global_position
	if _last_pos != Vector3.INF and Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() < 0.4:
		input.jump = true
		input.jump_pressed = true
		_sidestep = -1.0 if _rng.randf() < 0.5 else 1.0
		_sidestep_left = _rng.randf_range(0.5, 1.0)
		_roam = Vector3.INF # WHY: this roam point may be inside a wall; pick another
	_last_pos = pos


func _roam_point(me: Player, delta: float) -> Vector3:
	_roam_left -= delta
	var arrived := _roam != Vector3.INF and Vector2(_roam.x - me.global_position.x,
		_roam.z - me.global_position.z).length() < ARRIVE
	if _roam == Vector3.INF or arrived or _roam_left <= 0.0:
		if arrived and me.role != Enums.Role.MAGE:
			_pause_left = _rng.randf_range(0.5, 2.5)
		var radius := ROAM_RADIUS
		var storm := GameEvents.system(&"firestorm") as FirestormManager
		if storm != null and storm.stage > 0:
			radius = maxf(2.0, minf(radius, storm.zone_radius - ZONE_MARGIN))
		var a := _rng.randf_range(-PI, PI)
		var r := sqrt(_rng.randf()) * radius
		_roam = _centre(me) + Vector3(cos(a) * r, 0.0, sin(a) * r)
		_roam_left = _rng.randf_range(6.0, 12.0)
	return _roam


func _centre(me: Player) -> Vector3:
	var storm := GameEvents.system(&"firestorm") as FirestormManager
	if storm != null and storm.stage > 0:
		return storm.zone_center
	var main := GameEvents.system(&"main")
	var map: Node3D = main.get_map() if main and main.has_method(&"get_map") else null
	if map != null:
		return map.global_position
	return me.global_position


# ------------------------------------------------------------------ queries

func _nearest_villager(me: Player) -> Player:
	var best: Player = null
	var best_d := MAGE_CHASE_RANGE
	for p in Players.alive_with_role(Enums.Role.VILLAGER):
		var d := me.global_position.distance_to(p.global_position)
		if p != me and d < best_d and _in_zone(p.global_position):
			best = p
			best_d = d
	return best


func _nearest_mage(me: Player) -> Player:
	var best: Player = null
	var best_d := INF
	for p in Players.alive_with_role(Enums.Role.MAGE):
		var d := me.global_position.distance_to(p.global_position)
		if p != me and d < best_d:
			best = p
			best_d = d
	return best


func _nearest_downed(me: Player) -> Player:
	var best: Player = null
	var best_d := REVIVE_RANGE
	for p in Players.alive_with_role(Enums.Role.VILLAGER):
		if p == me or not p.health.is_downed:
			continue
		var d := me.global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best


func _nearest_chicken(me: Player) -> Node3D:
	var manager := GameEvents.system(&"chickens") as ChickenManager
	if manager == null:
		return null
	var best: Node3D = null
	var best_d := INF
	for c in manager.get_chickens():
		var chicken := c as Node3D
		if chicken == null or chicken.get(&"is_hidden") or int(chicken.get(&"carrier_id")) != 0:
			continue
		var health := chicken.get_node_or_null(^"Health") as Health
		if health == null or not health.is_alive or not _in_zone(chicken.global_position):
			continue
		var d := me.global_position.distance_to(chicken.global_position)
		if d < best_d:
			best = chicken
			best_d = d
	return best


func _in_zone(pos: Vector3) -> bool:
	var storm := GameEvents.system(&"firestorm") as FirestormManager
	return storm == null or storm.is_inside(pos)


## Dot product between the body's forward and the flat direction to `pos` (1 = straight ahead).
func _facing(me: Player, pos: Vector3) -> float:
	var to := pos - me.global_position
	to.y = 0.0
	if to.length() < 0.01:
		return 1.0
	return (-me.global_basis.z).dot(to.normalized())


func _set_goal(me: Player, goal: StringName) -> void:
	if goal != _goal:
		_goal = goal
		if NetworkManager.args.has("bot-log"):
			print("[Bot] %s goal=%s" % [me.name, goal])


# Old random wander, kept for unit tests that drive the brain without a Player.
func _wander(input: PlayerInput, delta: float) -> void:
	_turn_in -= delta
	_action_in -= delta
	if _turn_in <= 0.0:
		_turn_in = _rng.randf_range(0.6, 2.0)
		_move = Vector2.from_angle(_rng.randf_range(-PI, PI))
		_sprint = _rng.randf() < 0.5
		_turn = _rng.randf_range(-1.5, 1.5)
	input.move = _move
	input.sprint = _sprint
	input.look_delta = Vector2(_turn * delta, 0.0)
	if _action_in <= 0.0:
		_action_in = _rng.randf_range(0.5, 1.8)
		match _rng.randi_range(0, 2):
			0:
				input.jump = true
				input.jump_pressed = true
			1:
				input.interact_pressed = true
			2:
				input.primary = true
				input.primary_pressed = true
