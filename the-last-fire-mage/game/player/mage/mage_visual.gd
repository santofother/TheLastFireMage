class_name MageVisual
extends Node3D
## Mage model: picks animation clips from Player state and plays confirmed casts. Owner: mage model integration.
## Child of Player, shown only while the role is MAGE (see `Player._update_role_visual`).
## NET: runs on every peer, visuals only. Uses replicated flags and observed position, like VillagerVisual.
## Never changes gameplay state.
##
## Public API:
## - `clip`: the clip currently selected (StringName).
## - `play_cast(ability)`: restart the one-shot for `&"knife"`, `&"ignite"` or `&"fire_wave"`.
## - `hand_position()`: global position of the right hand socket (flame anchor).

const IDLE := &"idle"
const WALK := &"walk"
const RUN := &"run"
const SPRINT := &"sprint"
const CAST_CLIPS := {&"knife": &"knife_attack", &"ignite": &"ignite", &"fire_wave": &"fire_wave"}

# WHY: measured sole speeds (m/s) from the asset's clip-manifest.json.
const WALK_NATIVE_SPEED := 1.0
const RUN_NATIVE_SPEED := 4.5
const SPRINT_NATIVE_SPEED := 7.0

const BLEND_TIME := 0.1 # TUNE
const IDLE_SPEED := 0.15 # TUNE: below this the mage stands still
const RUN_MIN_SPEED := 2.5 # TUNE: stalking walk below this, pursuit run above
const SPRINT_MIN_SPEED := 5.2 # TUNE: sprint clip above this
const MAX_OBSERVED_SPEED := 25.0
const SPEED_SMOOTHING := 12.0 # TUNE
const MAX_RATE := 1.4 # TUNE: limit on locomotion playback scaling
const PIVOT_HEIGHT := 0.65 # Model is 1.3 m tall; rotate corpse/tumble about its middle.

## Clip currently selected.
var clip: StringName = &""

var _player: Player
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _hand := -1
var _model: Node3D
var _last_position := Vector3.ZERO
var _planar := Vector3.ZERO
var _cast_left := 0.0
var _cast_clip: StringName = &""
var _tumble_angle := 0.0


func _ready() -> void:
	_player = get_parent() as Player
	_model = get_child(0) as Node3D
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	_hand = _skeleton.find_bone("hand_socket.R")
	_last_position = _player.global_position
	position.y = PIVOT_HEIGHT
	_model.position.y = -PIVOT_HEIGHT


## Restart the one-shot for a server-confirmed cast, even if the same one is still playing.
func play_cast(ability: StringName) -> void:
	if not CAST_CLIPS.has(ability) or _anim == null:
		return
	_cast_clip = CAST_CLIPS[ability]
	_cast_left = _anim.get_animation(_cast_clip).length
	clip = _cast_clip
	_anim.speed_scale = 1.0
	_anim.play(_cast_clip, 0.04)
	_anim.seek(0.0, true)


## Global position of the right hand (where the knife is held).
func hand_position() -> Vector3:
	return _skeleton.to_global(_skeleton.get_bone_global_pose(_hand).origin)


func _physics_process(delta: float) -> void:
	if not visible or _player.tuning == null:
		return
	var moved := _player.global_position - _last_position
	_last_position = _player.global_position
	var observed := Vector3(moved.x, 0.0, moved.z) / delta
	if observed.length() > MAX_OBSERVED_SPEED:
		observed = Vector3.ZERO
	_planar = _planar.lerp(observed, 1.0 - exp(-SPEED_SMOOTHING * delta))
	_cast_left = maxf(0.0, _cast_left - delta)
	_update_pose(delta)
	if _cast_left > 0.0 and _player.is_alive:
		return
	_select_locomotion()


# No death/tumble clips exist for the mage yet, so tip the whole model like the old capsule did.
func _update_pose(delta: float) -> void:
	var down := not _player.is_alive or _player.health.is_downed
	if down:
		rotation.x = -PI / 2.0
		position.y = _player.tuning.radius
		_tumble_angle = 0.0
		return
	_tumble_angle = _tumble_angle + _player.tuning.tumble_roll_speed * delta if _player.is_tumbling else 0.0
	rotation.x = _tumble_angle
	position.y = PIVOT_HEIGHT


func _select_locomotion() -> void:
	var speed := _planar.length()
	var backward := (_player.global_basis.inverse() * _planar).z > 0.0
	var direction := -1.0 if backward else 1.0
	if speed < IDLE_SPEED or not _player.is_alive:
		_play(IDLE, 1.0)
	elif _player.is_crouching or speed < RUN_MIN_SPEED:
		_play(WALK, direction * clampf(speed / WALK_NATIVE_SPEED, 0.5, 2.5))
	elif speed >= SPRINT_MIN_SPEED:
		_play(SPRINT, direction * clampf(speed / SPRINT_NATIVE_SPEED, 0.5, MAX_RATE))
	else:
		_play(RUN, direction * clampf(speed / RUN_NATIVE_SPEED, 0.5, MAX_RATE))


func _play(next: StringName, rate: float) -> void:
	_anim.speed_scale = rate
	if next == clip:
		return
	clip = next
	_anim.play(next, BLEND_TIME)
