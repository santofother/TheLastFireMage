extends Node3D
## Headless checks that the blue villager shares the red rig and clips and plays every clip.
## Owner: blue villager integration. Public API: none; run through tools/tests/blue_villager_test.sh.
## NET: offline.

const RED_PATH := "res://game/player/villager/red-villager-animations.glb"
const BLUE_MESH_PATH := "res://game/player/villager/blue/blue-villager-mesh.glb"
const BLUE_SCENE_PATH := "res://game/player/villager/blue_villager.tscn"
const CLIPS: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"jump_start", &"jump_air", &"jump_land",
	&"climb_mantle", &"interact", &"pickup", &"carry_idle", &"carry_walk", &"put_down", &"hit_stun", &"knockback",
	&"death"]
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"jump_air", &"carry_idle", &"carry_walk"]
const BLUE_MESHES: Array[String] = ["BV_Accessories", "BV_Body", "BV_Face_Hair", "BV_Outfit"]
const BONE_COUNT := 35
const EPSILON := 0.0005

var _fails := 0


func _ready() -> void:
	var red: Node3D = load(RED_PATH).instantiate()
	add_child(red)
	var blue: Node3D = load(BLUE_SCENE_PATH).instantiate()
	add_child(blue)
	var red_anim := _player_of(red)
	var anim := _player_of(blue)
	var skeleton := blue.find_child("Skeleton3D", true, false) as Skeleton3D
	_check(skeleton != null and anim != null, "scene has skeleton and player")
	if skeleton != null and anim != null:
		_check_meshes(skeleton)
		_check_rig(skeleton, red.find_child("Skeleton3D", true, false) as Skeleton3D)
		_check_mesh_glb()
		_check_shared_clips(anim, red_anim)
		await _check_playback(anim, skeleton)
	if _fails == 0:
		print("[TEST] BLUE VILLAGER TEST PASSED")
	else:
		print("[TEST] FAIL blue villager: %d checks failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _player_of(root: Node) -> AnimationPlayer:
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("[TEST] FAIL ", what)


func _check_meshes(skeleton: Skeleton3D) -> void:
	var names: Array[String] = []
	var bounds := AABB()
	for child: Node in skeleton.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		names.append(String(mesh.name))
		_check(mesh.mesh != null and mesh.skin != null, "%s has mesh and skin" % mesh.name)
		_check(mesh.get_node_or_null(mesh.skeleton) == skeleton, "%s bound to shared skeleton" % mesh.name)
		_check_binds(mesh, skeleton)
		bounds = mesh.get_aabb() if names.size() == 1 else bounds.merge(mesh.get_aabb())
	names.sort()
	_check(names == BLUE_MESHES, "blue meshes only, got %s" % str(names))
	print("[TEST] blue bounds height %.4f" % bounds.size.y)
	_check(absf(bounds.size.y - 1.0) < 0.01, "1 m model height, got %f" % bounds.size.y)


## Every skin bind must name a real bone and match that bone's rest, or the body would deform wrongly.
func _check_binds(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	for i: int in mesh.skin.get_bind_count():
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(i))
		_check(bone >= 0, "%s bind %s resolves" % [mesh.name, mesh.skin.get_bind_name(i)])
		if bone >= 0:
			_check(_near_identity(skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(i)),
				"%s bind matches rest" % mesh.skin.get_bind_name(i))


func _near_identity(t: Transform3D) -> bool:
	return t.origin.length() < EPSILON and (t.basis.x - Vector3.RIGHT).length() < EPSILON \
		and (t.basis.y - Vector3.UP).length() < EPSILON and (t.basis.z - Vector3.BACK).length() < EPSILON


## Same bones and rests also pins scale and facing to the red villager's.
func _check_rig(skeleton: Skeleton3D, red: Skeleton3D) -> void:
	_check(skeleton.get_bone_count() == BONE_COUNT, "bone count %d" % skeleton.get_bone_count())
	_check(red.get_bone_count() == skeleton.get_bone_count(), "bone count matches red")
	for i: int in red.get_bone_count():
		var other := skeleton.find_bone(red.get_bone_name(i))
		_check(other >= 0, "bone %s present" % red.get_bone_name(i))


func _check_mesh_glb() -> void:
	var body: Node = load(BLUE_MESH_PATH).instantiate()
	_check(_player_of(body) == null or _player_of(body).get_animation_list().is_empty(), "blue GLB has no clips")
	var blue_bones := body.find_child("Skeleton3D", true, false) as Skeleton3D
	var red: Node = load(RED_PATH).instantiate()
	var red_bones := red.find_child("Skeleton3D", true, false) as Skeleton3D
	for i: int in red_bones.get_bone_count():
		var bone := blue_bones.find_bone(red_bones.get_bone_name(i))
		_check(bone >= 0 and _near_identity(
			red_bones.get_bone_global_rest(i).affine_inverse() * blue_bones.get_bone_global_rest(bone)),
			"rest of %s matches red" % red_bones.get_bone_name(i))
	body.free()
	red.free()


func _check_shared_clips(anim: AnimationPlayer, red_anim: AnimationPlayer) -> void:
	_check(anim.root_motion_track == NodePath(), "no root motion track")
	for clip: StringName in CLIPS:
		_check(anim.has_animation(clip), "clip %s exists" % clip)
		if anim.has_animation(clip):
			_check(anim.get_animation(clip) == red_anim.get_animation(clip), "clip %s is the red resource" % clip)
			var expected := Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
			_check(anim.get_animation(clip).loop_mode == expected, "loop mode of %s" % clip)


func _check_playback(anim: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var names: Array[StringName] = []
	names.assign(anim.get_animation_list())
	for clip: StringName in names:
		if clip == &"RESET":
			continue
		anim.play(clip)
		await get_tree().process_frame
		_check(anim.is_playing() and anim.current_animation == clip, "%s plays" % clip)
		var length := anim.get_animation(clip).length
		for fraction: float in [0.0, 0.5, 1.0]:
			anim.seek(length * fraction, true)
			for bone: int in skeleton.get_bone_count():
				var pose := skeleton.get_bone_global_pose(bone)
				_check(pose.is_finite(), "%s finite at %.1f" % [clip, fraction])
		print("[TEST] played ", clip)
