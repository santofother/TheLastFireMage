class_name SpectatorManager
extends Node3D
## Dead/late-join players watch as a third-person ghost on a one-way glass layer above the map, with fog beyond a radius. Owner: S11.
## Registered as GameEvents.system(&"spectator").
## NET: local only (each peer handles its own view). Reacts to GameEvents.player_died / player_revived /
## role_assigned for the local player. The corpse look is done by Player itself.
## Public API: `is_spectating`, `enter_spectator()`, `exit_spectator()`, `camera`, `focus` (ghost position on the glass).
## Signals: `spectating_changed(on)`.

## Fires when the local view enters or leaves the spectator camera.
signal spectating_changed(on: bool)

## One-way glass: back faces are culled, so it is invisible from below (living players never see it).
## Opaque dark fog outside `radius` around the ghost, clear inside, so the map shows through underneath.
const GLASS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform vec3 ghost_pos = vec3(0.0);
uniform float radius = 15.0;
uniform float edge = 5.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float d = distance(wpos.xz, ghost_pos.xz);
	float fog = smoothstep(radius - edge, radius, d);
	ALBEDO = mix(vec3(0.55, 0.75, 1.0), vec3(0.01, 0.01, 0.03), fog);
	ALPHA = mix(0.07, 0.97, fog);
}
"""

## True while the local view is the spectator camera.
var is_spectating := false
## The spectator third-person camera (created on first use).
var camera: Camera3D
## Ghost position on the glass layer (y = tuning.camera_height).
var focus := Vector3.ZERO
var tuning: SpectatorTuning

var _ghost: Node3D
var _ghost_anim: AnimationPlayer
var _ghost_clip: StringName = &""
var _ghost_for_peer := 0
var _last_focus := Vector3.ZERO
var _glass: MeshInstance3D
var _glass_mat: ShaderMaterial
var _yaw := 0.0
var _pitch := -0.45
var _prev_listener: Node3D
var _own_peer := 0


func _enter_tree() -> void:
	GameEvents.register_system(&"spectator", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/spectator/tuning_spectator.tres", "spectator") as SpectatorTuning
	set_process(false)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.player_revived.connect(_on_player_revived)
	GameEvents.role_assigned.connect(_on_role_assigned)


## Switch the local view to the spectator ghost.
func enter_spectator() -> void:
	if is_spectating:
		return
	var me := Players.local_player() as Player
	_ensure_nodes()
	if me != null:
		_own_peer = me.peer_id
		focus = Vector3(me.global_position.x, tuning.camera_height, me.global_position.z)
		_yaw = me.rotation.y
	_prev_listener = VoiceManager.listener
	is_spectating = true
	_build_ghost_model(me)
	_ghost.visible = true
	_glass.visible = true
	_update_view()
	camera.make_current()
	VoiceManager.listener = camera # WHY: dead players keep proximity voice, heard from where they watch
	_set_voice_group(&"dead")
	set_process(true)
	print("[Spectator] enter peer=%d" % _own_peer)
	spectating_changed.emit(true)


## Give the view back to the local player's camera.
func exit_spectator() -> void:
	if not is_spectating:
		return
	is_spectating = false
	var me := Players.local_player() as Player
	if me != null:
		me.camera.make_current()
		VoiceManager.listener = me
	elif is_instance_valid(_prev_listener):
		VoiceManager.listener = _prev_listener
	_set_voice_group(&"alive")
	_ghost.visible = false
	_glass.visible = false
	set_process(false)
	print("[Spectator] exit peer=%d" % _own_peer)
	spectating_changed.emit(false)


## Test hook: move the ghost by a ground-plane vector.
func move_focus(delta: Vector3) -> void:
	focus += Vector3(delta.x, 0.0, delta.z)


func _ensure_nodes() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "SpectatorCamera"
	camera.far = 500.0
	add_child(camera)
	# Local-only visuals (never networked): translucent ghost + the glass/fog plane.
	_ghost = Node3D.new()
	_ghost.top_level = true
	_ghost.visible = false
	add_child(_ghost)
	_glass = MeshInstance3D.new()
	var quad := PlaneMesh.new() # faces up (+Y): front face seen from above only
	quad.size = Vector2(1.0, 1.0)
	_glass.mesh = quad
	var shader := Shader.new()
	shader.code = GLASS_SHADER
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = shader
	_glass.material_override = _glass_mat
	_glass.top_level = true
	_glass.visible = false
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)


## Rebuild the ghost from the player's own villager model, so future model choices carry over.
## Falls back to a translucent capsule when the player has no villager model (e.g. the mage).
func _build_ghost_model(me: Player) -> void:
	for c in _ghost.get_children():
		c.queue_free()
	_ghost_anim = null
	_ghost_clip = &""
	var src := me.get_node_or_null("VillagerVisual/Model") as Node3D if me != null else null
	if src != null and src.scene_file_path != "":
		var model := (load(src.scene_file_path) as PackedScene).instantiate() as Node3D
		model.transform = src.transform
		# FIX(villager picker, Claude): the file path is always the red GLB, so reapply the player's chosen body.
		if me.villager_skin != 0:
			VillagerMeshSwap.apply(model.find_child("Skeleton3D", true, false) as Skeleton3D, VillagerSkins.scene(me.villager_skin))
		_ghost.add_child(model)
		_ghost_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		return
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	mesh.mesh = capsule
	mesh.position.y = 0.85
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.7, 0.85, 1.0, 0.45)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = gm
	_ghost.add_child(mesh)


func _animate_ghost(delta: float) -> void:
	if _ghost_anim == null:
		return
	var speed := Vector2(focus.x - _last_focus.x, focus.z - _last_focus.z).length() / maxf(delta, 0.0001)
	var next: StringName = &"idle"
	var rate := 1.0
	if speed > 12.0:
		next = &"sprint"
		rate = speed / 16.0
	elif speed > 0.5:
		next = &"run"
		rate = clampf(speed / 8.0, 0.5, 2.0)
	if next != _ghost_clip and _ghost_anim.has_animation(next):
		_ghost_clip = next
		_ghost_anim.play(next, 0.12)
	_ghost_anim.speed_scale = rate


func _unhandled_input(event: InputEvent) -> void:
	if is_spectating and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * tuning.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * tuning.mouse_sensitivity, -1.2, 0.2)


func _process(delta: float) -> void:
	if not is_spectating:
		return
	var dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if dir != Vector2.ZERO and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var speed := tuning.move_speed * (2.0 if Input.is_action_pressed(&"sprint") else 1.0)
		var basis := Basis(Vector3.UP, _yaw)
		focus += basis * Vector3(dir.x, 0.0, dir.y) * speed * delta
	_update_view()
	_animate_ghost(delta)
	_last_focus = focus


func _update_view() -> void:
	focus.y = tuning.camera_height
	_ghost.global_position = focus
	_ghost.global_rotation = Vector3(0, _yaw, 0)
	# Third-person boom: behind and above the ghost, looking at it.
	var boom := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3(0, 0, tuning.camera_distance)
	camera.global_position = focus + Vector3(0, 1.4, 0) + boom
	camera.look_at(focus + Vector3(0, 1.0, 0), Vector3.UP)
	# Glass sits at ghost's feet, large enough to cover the fog radius from any angle; fog centred on ghost.
	var size := (tuning.vision_radius + 60.0) * 2.0
	_glass.global_position = Vector3(focus.x, tuning.camera_height, focus.z)
	_glass.scale = Vector3(size, 1.0, size)
	_glass_mat.set_shader_parameter("ghost_pos", focus)
	_glass_mat.set_shader_parameter("radius", tuning.vision_radius)
	_glass_mat.set_shader_parameter("edge", tuning.fog_edge)


func _set_voice_group(group: StringName) -> void:
	# TODO(S12): VoiceManager.set_voice_group(peer, group) does not exist yet; call it once S12 lands.
	if VoiceManager.has_method(&"set_voice_group") and _own_peer != 0:
		VoiceManager.call(&"set_voice_group", _own_peer, group)


func _on_player_died(peer_id: int, _killer: int, _cause: StringName) -> void:
	var me := Players.local_player()
	if me != null and me.peer_id == peer_id:
		enter_spectator()


func _on_player_revived(peer_id: int) -> void:
	if is_spectating and peer_id == _own_peer:
		var me := Players.local_player() as Player
		if me == null or me.role != Enums.Role.SPECTATOR:
			exit_spectator()


func _on_role_assigned(peer_id: int, role: int) -> void:
	var me := Players.local_player()
	if me == null or me.peer_id != peer_id:
		return
	if role == Enums.Role.SPECTATOR:
		enter_spectator()
	elif is_spectating and me.is_alive:
		exit_spectator()
