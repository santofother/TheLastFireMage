class_name VillagerVisual
extends Node3D
## Red villager model: picks animation clips from Player state and carries props at the hands.
## Owner: villager model integration. Child of Player, which shows it for every role except the mage.
## NET: runs on every peer, visuals only. Reads replicated flags and observed position, so remote players
## animate the same as the owner. Never changes gameplay state, except moving `Player.carry_socket`.
##
## Public API:
## - `clip`: the clip currently selected (StringName). Tests and debug tools read it.

const DEATH := &"death"
const IDLE := &"idle"
const WALK := &"walk"
const RUN := &"run"
const SPRINT := &"sprint"
const JUMP_START := &"jump_start"
const JUMP_AIR := &"jump_air"
const JUMP_LAND := &"jump_land"
const MANTLE := &"climb_mantle"
const PICKUP := &"pickup"
const PUT_DOWN := &"put_down"
const CARRY_IDLE := &"carry_idle"
const CARRY_WALK := &"carry_walk"
const HIT_STUN := &"hit_stun"
const KNOCKBACK := &"knockback"

# WHY: native foot-contact speeds measured on these clips (m/s); see the asset's GODOT_INTEGRATION.md.
const WALK_NATIVE_SPEED := 0.29
const RUN_NATIVE_SPEED := 1.82
const SPRINT_NATIVE_SPEED := 2.78
const CARRY_NATIVE_SPEED := 0.22
const PICKUP_LENGTH := 1.6
# WHY: the game attaches instantly, so start pickup at the authored grip frame; the prop never teleports.
const PICKUP_GRIP_TIME := 0.72
# Chicken root offset from the hand midpoint, skeleton space (+Z forward), and pickup floor correction.
const PROP_ROOT_OFFSET := Vector3(0.0, -0.18, 0.12)
const GROUND_GRIP_CORRECTION := 0.06113556

const BLEND_TIME := 0.12 # TUNE: crossfade between clips
const IDLE_SPEED := 0.15 # TUNE: below this the character stands still
const RUN_MIN_SPEED := 0.9 # TUNE: walk clip below this, run clip above
const SPRINT_MIN_SPEED := 5.0 # TUNE: sprint clip above this
const MAX_SLOW_CLIP_RATE := 3.0 # TUNE: walk/carry stop speeding up here (they are slow gaits)
const JUMP_START_RATE := 3.0 # TUNE: the 1.23 s anticipation must fit a jump that leaves instantly
const LAND_RATE := 2.0 # TUNE
const PICKUP_RATE := 1.5 # TUNE
const PUT_DOWN_RATE := 2.0 # TUNE
const FALL_DELAY := 0.1 # TUNE: airborne this long before the fall pose; ignores small bumps
const MAX_OBSERVED_SPEED := 20.0 # Larger position jumps are teleports, not motion.
const SPEED_SMOOTHING := 12.0 # TUNE: higher = reacts sooner; remote positions only update at 20 Hz
const STRAFE_TURN := 10.0 # TUNE
const MAX_STRAFE_YAW := PI / 3.0 # TUNE: how far the body turns toward strafing

## Clip currently selected.
var clip: StringName = &""

var _player: Player
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _left_hand := -1
var _right_hand := -1
var _last_position := Vector3.ZERO
var _planar := Vector3.ZERO
var _rising := false
var _was_airborne := false
var _air_time := 0.0
var _stun_left := 0.0
var _stun_rate := 1.0
var _carrying := false
var _timed_clip: StringName = &""
var _timed_left := 0.0
var _timed_rate := 1.0
var _skin := 0 # The player scene starts with the red body.
var _overlay: BodyPoseOverlay


func _ready() -> void:
	_player = get_parent() as Player
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	_left_hand = _skeleton.find_bone("hand.L")
	_right_hand = _skeleton.find_bone("hand.R")
	_last_position = _player.global_position
	_player.stunned.connect(_on_stunned)
	_player.revived.connect(_on_revived)
	GameEvents.carry_changed.connect(_on_carry_changed)
	_overlay = BodyPoseOverlay.new()
	_skeleton.add_child(_overlay)


## Shows the body for a `VillagerSkins` id. Clips and skeleton are unaffected.
func set_skin(id: int) -> void:
	if id == _skin:
		return
	_skin = id
	VillagerMeshSwap.apply(_skeleton, VillagerSkins.scene(id))
	if _overlay != null:
		_skeleton.move_child(_overlay, -1) # WHY: keeps the body mesh as the skeleton's first child.
	print("[Game] Villager skin %d -> %s %s" % [_player.peer_id, VillagerSkins.NAMES[id], _skeleton.get_child(0).name])


func _physics_process(delta: float) -> void:
	if not visible or _player.tuning == null:
		return
	position.y = _player.visual_y_offset
	_sample_motion(delta)
	_update_strafe_yaw(delta)
	_stun_left = maxf(0.0, _stun_left - delta)
	_timed_left = maxf(0.0, _timed_left - delta)
	_update_air_edges(delta)
	_select_clip()


func _process(_delta: float) -> void:
	if visible and _carrying:
		_place_carry_socket()


# Observed motion works the same for the owner and for remote peers, which have no real velocity.
func _sample_motion(delta: float) -> void:
	var moved := _player.global_position - _last_position
	_last_position = _player.global_position
	_rising = moved.y > 0.001
	var observed := Vector3(moved.x, 0.0, moved.z) / delta
	if observed.length() > MAX_OBSERVED_SPEED:
		observed = Vector3.ZERO
	_planar = _planar.lerp(observed, 1.0 - exp(-SPEED_SMOOTHING * delta))


func _update_strafe_yaw(delta: float) -> void:
	var target := 0.0
	var local := _player.global_basis.inverse() * _planar
	if local.length() > RUN_MIN_SPEED and _player.is_alive and not _player.is_tumbling:
		target = atan2(local.x, local.z) if _moving_backward(local) else -atan2(local.x, -local.z)
	target = clampf(target, -MAX_STRAFE_YAW, MAX_STRAFE_YAW)
	rotation.y = lerp_angle(rotation.y, target, 1.0 - exp(-STRAFE_TURN * delta))


func _moving_backward(local: Vector3) -> bool:
	return local.z > absf(local.x) * 0.5


func _update_air_edges(delta: float) -> void:
	var airborne := _player.is_airborne
	_air_time = _air_time + delta if airborne else 0.0
	if airborne and not _was_airborne and _rising and _player.can_control():
		_start_timed(JUMP_START, JUMP_START_RATE)
	elif not airborne and _was_airborne and clip in [JUMP_START, JUMP_AIR]:
		_start_timed(JUMP_LAND, LAND_RATE)
	_was_airborne = airborne


func _start_timed(timed: StringName, rate: float, from_time := 0.0) -> void:
	_timed_clip = timed
	_timed_rate = rate
	_timed_left = (_anim.get_animation(timed).length - from_time) / rate


func _select_clip() -> void:
	if not _player.is_alive or _player.health.is_downed:
		_timed_left = 0.0
		_play(DEATH, 1.0)
	elif _player.is_tumbling:
		_timed_left = 0.0
		_play(KNOCKBACK, _anim.get_animation(KNOCKBACK).length / _player.tuning.tumble_duration)
	elif _stun_left > 0.0:
		_timed_left = 0.0
		_play(HIT_STUN, _stun_rate)
	elif _player.is_mantling:
		_timed_left = 0.0
		_play(MANTLE, _anim.get_animation(MANTLE).length / _player.tuning.mantle_duration)
	elif _timed_left > 0.0 and not (_timed_clip != JUMP_START and _planar.length() > RUN_MIN_SPEED):
		_play(_timed_clip, _timed_rate)
	elif _player.is_airborne and _air_time >= FALL_DELAY:
		_timed_left = 0.0
		_play(JUMP_AIR, 1.0)
	else:
		_timed_left = 0.0
		_select_ground_clip()


func _select_ground_clip() -> void:
	var speed := _planar.length()
	var direction := -1.0 if _moving_backward(_player.global_basis.inverse() * _planar) else 1.0
	if speed < IDLE_SPEED:
		_play(CARRY_IDLE if _carrying else IDLE, 1.0)
	elif _carrying:
		_play(CARRY_WALK, direction * minf(speed / CARRY_NATIVE_SPEED, MAX_SLOW_CLIP_RATE))
	elif _player.is_crouching or speed < RUN_MIN_SPEED:
		# WHY: no crouch clip exists; BodyPoseOverlay bends the legs on top of the slow walk.
		_play(WALK, direction * minf(speed / WALK_NATIVE_SPEED, MAX_SLOW_CLIP_RATE))
	elif speed >= SPRINT_MIN_SPEED:
		_play(SPRINT, direction * speed / SPRINT_NATIVE_SPEED)
	else:
		_play(RUN, direction * speed / RUN_NATIVE_SPEED)


func _play(next: StringName, rate: float) -> void:
	_anim.speed_scale = rate
	if next == clip:
		return
	clip = next
	_anim.play(next, BLEND_TIME)
	if next == PICKUP:
		_anim.seek(PICKUP_GRIP_TIME, true)


# Same placement as the asset's rv_carry_socket.gd adapter. CONTRACT: Chicken follows this socket on every peer.
func _place_carry_socket() -> void:
	var midpoint := (_skeleton.get_bone_global_pose(_left_hand).origin
		+ _skeleton.get_bone_global_pose(_right_hand).origin) * 0.5
	var offset := PROP_ROOT_OFFSET
	if clip == PICKUP or clip == PUT_DOWN:
		var u := clampf(_anim.current_animation_position / PICKUP_LENGTH, 0.0, 1.0)
		if clip == PUT_DOWN:
			u = 1.0 - u
		var grip := smoothstep(0.0, 0.45, u) if u < 0.45 else 1.0 - smoothstep(0.45, 0.87, u)
		offset.y -= GROUND_GRIP_CORRECTION * grip
	_player.carry_socket.global_transform = Transform3D(_skeleton.global_basis.orthonormalized(),
		_skeleton.to_global(midpoint + offset))


func _on_stunned(seconds: float) -> void:
	_stun_left = seconds
	_stun_rate = clampf(_anim.get_animation(HIT_STUN).length / maxf(seconds, 0.01), 0.35, 2.0)
	clip = &"" # Restart the hit reaction when stunned again.


func _on_revived() -> void:
	_stun_left = 0.0
	_timed_left = 0.0
	_carrying = false


# NET: fires on all peers.
func _on_carry_changed(peer_id: int, kind: StringName) -> void:
	if peer_id != _player.peer_id:
		return
	var carrying := kind != &""
	if carrying == _carrying:
		return
	_carrying = carrying
	if carrying:
		_start_timed(PICKUP, PICKUP_RATE, PICKUP_GRIP_TIME)
	else:
		_start_timed(PUT_DOWN, PUT_DOWN_RATE)
