class_name SpectatorManager
extends Node3D
## Dead/late-join players watch from a top-down camera with limited vision. Owner: S11.
## Registered as GameEvents.system(&"spectator").
## NET: local only (each peer handles its own view). Reacts to GameEvents.player_died / player_revived /
## role_assigned for the local player. The corpse look is done by Player itself.
## Public API: `is_spectating`, `enter_spectator()`, `exit_spectator()`, `camera`, `focus`.
## Signals: `spectating_changed(on)`.

## Fires when the local view enters or leaves the spectator camera.
signal spectating_changed(on: bool)

const FOG_SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius_px = 300.0;
uniform float edge_px = 80.0;
void fragment() {
	float d = distance(FRAGCOORD.xy, center);
	COLOR = vec4(0.0, 0.0, 0.02, smoothstep(radius_px - edge_px, radius_px, d) * 0.97);
}
"""

## True while the local view is the spectator camera.
var is_spectating := false
## The spectator camera (created on first use). Looks straight down.
var camera: Camera3D
## Ground point (x, z) the camera is centred on.
var focus := Vector3.ZERO
var tuning: SpectatorTuning

var _fog_layer: CanvasLayer
var _fog_mat: ShaderMaterial
var _prev_listener: Node3D
var _own_peer := 0


func _enter_tree() -> void:
	GameEvents.register_system(&"spectator", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/spectator/tuning_spectator.tres", "spectator") as SpectatorTuning
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.player_revived.connect(_on_player_revived)
	GameEvents.role_assigned.connect(_on_role_assigned)


## Switch the local view to the spectator camera.
func enter_spectator() -> void:
	if is_spectating:
		return
	var me := Players.local_player() as Player
	_ensure_nodes()
	if me != null:
		_own_peer = me.peer_id
		focus = Vector3(me.global_position.x, 0.0, me.global_position.z)
	_prev_listener = VoiceManager.listener
	is_spectating = true
	_place_camera()
	camera.make_current()
	VoiceManager.listener = camera # WHY: dead players keep proximity voice, heard from where they watch
	_set_voice_group(&"dead")
	_fog_layer.visible = true
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
	_fog_layer.visible = false
	set_process(false)
	print("[Spectator] exit peer=%d" % _own_peer)
	spectating_changed.emit(false)


## Test hook: move the camera focus by a ground-plane vector.
func move_focus(delta: Vector3) -> void:
	focus += Vector3(delta.x, 0.0, delta.z)


func _ensure_nodes() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "SpectatorCamera"
	camera.far = 500.0
	camera.cull_mask = 0xFFFFF # no special layers: no player highlighting for ghosts
	add_child(camera)
	camera.global_rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_fog_layer = CanvasLayer.new()
	_fog_layer.layer = 5
	_fog_layer.visible = false
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = FOG_SHADER
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = shader
	rect.material = _fog_mat
	_fog_layer.add_child(rect)
	add_child(_fog_layer)


func _process(delta: float) -> void:
	if not is_spectating:
		return
	var dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if dir != Vector2.ZERO and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var speed := tuning.move_speed * (2.0 if Input.is_action_pressed(&"sprint") else 1.0)
		focus += Vector3(dir.x, 0.0, dir.y) * speed * delta
	_place_camera()
	_update_fog()


func _place_camera() -> void:
	# Separate height layer: camera floats above the map regardless of terrain.
	camera.global_position = Vector3(focus.x, tuning.camera_height, focus.z)


func _update_fog() -> void:
	if not camera.current or DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	var c := camera.unproject_position(Vector3(focus.x, 0.0, focus.z))
	var e := camera.unproject_position(Vector3(focus.x + tuning.vision_radius, 0.0, focus.z))
	var scale_px := vp.get_visible_rect().size.y / maxf(get_window().content_scale_size.y, 1.0) \
			if get_window().content_scale_size.y > 0 else 1.0
	_fog_mat.set_shader_parameter("center", c * scale_px)
	_fog_mat.set_shader_parameter("radius_px", c.distance_to(e) * scale_px)
	_fog_mat.set_shader_parameter("edge_px", c.distance_to(e) * scale_px * 0.25)


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
