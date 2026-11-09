class_name BodyPoseOverlay
extends SkeletonModifier3D
## Bends the villager and mage rigs on top of their clips: ground crouch, mid-air leg tuck, optional climb.
## Owner: playtest batch. Added under Skeleton3D by VillagerVisual / MageVisual.
## NET: runs on every peer, visuals only. Reads replicated Player flags.
##
## Public API: `procedural_mantle` (play the built-in climb, for rigs with no climb clip),
## `crouch_weight`, `tuck_weight` (0..1, read by tests).

const BLEND_SPEED := 14.0 # TUNE: pose blend, per second
const TUCK_LEG_SHORTEN := 0.62 # TUNE: fraction of leg length pulled in for a tuck
const TUCK_HIP_SWING := 0.75 # TUNE: radians the knees come up toward the chest
const CROUCH_LEAN := 0.3 # TUNE: radians the spine leans forward in a crouch
const CLIMB_ARM_REACH := 2.6 # TUNE: radians the arms reach up at the start of a climb
const CLIMB_LEAN := 0.55 # TUNE: radians the chest pitches over the ledge

## Plays the built-in climb while `Player.is_mantling`.
var procedural_mantle := false
## Current ground crouch blend.
var crouch_weight := 0.0
## Current air tuck blend.
var tuck_weight := 0.0

var _player: Player
var _climb_time := -1.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if _player == null:
		_player = _find_player()
	if skeleton == null or _player == null or _player.tuning == null or not _player.is_alive:
		return
	var rate := 1.0 - exp(-BLEND_SPEED * delta)
	var tucked := _player.air_tuck_lift > 0.0
	crouch_weight = lerpf(crouch_weight, 1.0 if _player.is_crouching and not tucked else 0.0, rate)
	tuck_weight = lerpf(tuck_weight, 1.0 if tucked else 0.0, rate)
	_climb_time = _climb_time + delta if _player.is_mantling and procedural_mantle else -1.0 if not _player.is_mantling else 0.0
	var climb := clampf(_climb_time / _player.tuning.mantle_duration, 0.0, 1.0) if _climb_time >= 0.0 and procedural_mantle else -1.0
	if crouch_weight < 0.01 and tuck_weight < 0.01 and climb < 0.0:
		return
	var scale_y := maxf(skeleton.global_basis.get_scale().y, 0.001)
	var drop := (_player.tuning.height - _player.tuning.crouch_height) / scale_y * crouch_weight
	var body_tuck := tuck_weight
	var lean := CROUCH_LEAN * crouch_weight + 0.2 * tuck_weight
	if climb >= 0.0:
		var arc := sin(climb * PI)
		body_tuck = maxf(body_tuck, arc * 0.8)
		lean += CLIMB_LEAN * arc
		_arms(skeleton, lerpf(CLIMB_ARM_REACH, 0.5, smoothstep(0.1, 0.8, climb)) * minf(1.0, arc * 3.0))
	if drop > 0.0:
		_drop_pelvis(skeleton, drop)
	_rotate(skeleton, "spine", lean * 0.5)
	_rotate(skeleton, "chest", lean * 0.5)
	_leg(skeleton, "L", drop, body_tuck)
	_leg(skeleton, "R", drop, body_tuck)


func _find_player() -> Player:
	var node := get_parent()
	while node != null and not node is Player:
		node = node.get_parent()
	return node as Player


# Rotates a bone about the skeleton's side axis. WHY: the two rigs have different bone rolls, so a
# skeleton-space axis means the same thing on both. Positive leans toward the model's +Z (its front).
func _rotate(skeleton: Skeleton3D, bone_name: String, angle: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var axis := (skeleton.get_bone_global_pose(bone).basis.orthonormalized().inverse() * Vector3.RIGHT).normalized()
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(axis, angle))


func _drop_pelvis(skeleton: Skeleton3D, drop: float) -> void:
	var pelvis := skeleton.find_bone("pelvis")
	var parent := skeleton.get_bone_parent(pelvis)
	var offset := Vector3.DOWN * drop
	if parent >= 0:
		offset = skeleton.get_bone_global_pose(parent).basis.inverse() * offset
	skeleton.set_bone_pose_position(pelvis, skeleton.get_bone_pose_position(pelvis) + offset)


# Two-bone solve so a crouching foot stays on the floor and a tucked foot comes up to the body.
func _leg(skeleton: Skeleton3D, side: String, drop: float, tuck: float) -> void:
	var thigh := skeleton.find_bone("thigh.%s" % side)
	var shin := skeleton.find_bone("shin.%s" % side)
	var foot := skeleton.find_bone("foot.%s" % side)
	var upper := skeleton.get_bone_global_rest(thigh).origin.distance_to(skeleton.get_bone_global_rest(shin).origin)
	var lower := skeleton.get_bone_global_rest(shin).origin.distance_to(skeleton.get_bone_global_rest(foot).origin)
	var full := upper + lower
	var reach := clampf(full - drop - full * TUCK_LEG_SHORTEN * tuck, absf(upper - lower) + 0.01, full - 0.001)
	var hip := acos(clampf((upper * upper + reach * reach - lower * lower) / (2.0 * upper * reach), -1.0, 1.0))
	var knee := PI - acos(clampf((upper * upper + lower * lower - reach * reach) / (2.0 * upper * lower), -1.0, 1.0))
	var swing := hip + TUCK_HIP_SWING * tuck
	_rotate(skeleton, "thigh.%s" % side, -swing)
	_rotate(skeleton, "shin.%s" % side, knee)
	_rotate(skeleton, "foot.%s" % side, swing - knee)


func _arms(skeleton: Skeleton3D, angle: float) -> void:
	for side in ["L", "R"]:
		_rotate(skeleton, "upper_arm.%s" % side, -angle)
		_rotate(skeleton, "forearm.%s" % side, -angle * 0.15)
