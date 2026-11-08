extends Node3D
## Local firestorm wall, rune animation, destination beacon, and stage tint. Owner: S14.
## NET: presentation only; each peer may instantiate this for synchronized zone values.
## Public API: set_zone(center, radius, stage), set_destination(center, radius), clear_zone().

const WALL_SHADER := preload("res://game/firestorm/firestorm_wall.gdshader")
const RUNE_TEXTURE := preload("res://game/firestorm/firestorm_runes.png")

const WALL_HEIGHT := 30.0
const BEACON_HEIGHT := 48.0
const STAGE_TINTS: Array[Color] = [Color(1.0, 0.52, 0.24), Color(1.0, 0.34, 0.12), Color(0.92, 0.19, 0.08), Color(0.68, 0.08, 0.12)]

var _wall: MeshInstance3D
var _wall_material: ShaderMaterial
var _embers: GPUParticles3D
var _beacon: Node3D
var _destination_ring: MeshInstance3D
var _destination_radius := 0.0
var _environment: WorldEnvironment
var _original_environment: Environment
var _ember_material: ParticleProcessMaterial
var _last_stage := -1


func _ready() -> void:
	# Headless runs still keep the API/state valid without allocating render resources.
	if DisplayServer.get_name() == "headless":
		return
	_build_wall()
	_build_embers()
	_build_beacon()


## Update the wall center and radius each frame; shader/material setup only changes on stage edges.
func set_zone(center: Vector3, radius: float, stage: int) -> void:
	if _wall == null:
		return
	_wall.visible = true
	_wall.position = center + Vector3.UP * WALL_HEIGHT * 0.5
	_wall.scale = Vector3(radius, 1.0, radius)
	_wall_material.set_shader_parameter("circumference", TAU * radius)
	_embers.visible = true
	_embers.emitting = true
	_embers.position = center + Vector3.UP * WALL_HEIGHT * 0.25
	_ember_material.emission_ring_radius = radius
	_ember_material.emission_ring_inner_radius = radius * 0.98
	_beacon.visible = radius > _destination_radius + 0.05
	if stage != _last_stage:
		_last_stage = stage
		_wall_material.set_shader_parameter("stage_energy", 1.0 + float(maxi(stage - 1, 0)) * 0.16)
		_set_environment_stage(stage)


## Show a distant marker for the pre-announced final safe area.
func set_destination(center: Vector3, radius: float) -> void:
	if _beacon == null:
		return
	_beacon.visible = true
	_beacon.position = center
	_destination_radius = radius
	_destination_ring.scale = Vector3(radius, 1.0, radius)


## Hide all firestorm visuals and restore the shared world environment's original colors.
func clear_zone() -> void:
	_last_stage = -1
	if _wall != null:
		_wall.visible = false
	if _embers != null:
		_embers.emitting = false
		_embers.visible = false
	if _beacon != null:
		_beacon.visible = false
	_restore_environment()


func _build_wall() -> void:
	if _wall != null:
		return
	_wall = MeshInstance3D.new()
	_wall.name = "FirestormWall"
	_wall.top_level = true
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = WALL_HEIGHT
	cylinder.radial_segments = 96
	cylinder.rings = 4
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	_wall.mesh = cylinder
	_wall_material = ShaderMaterial.new()
	_wall_material.shader = WALL_SHADER
	_wall_material.set_shader_parameter("rune_texture", RUNE_TEXTURE)
	_wall.material_override = _wall_material
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.visible = false
	add_child(_wall)


func _build_embers() -> void:
	_embers = GPUParticles3D.new()
	_embers.name = "FirestormEmbers"
	_embers.top_level = true
	_embers.amount = 420
	_embers.lifetime = 3.2
	_embers.emitting = false
	_embers.visibility_aabb = AABB(Vector3(-150, -18, -150), Vector3(300, 55, 300))
	_ember_material = ParticleProcessMaterial.new()
	_ember_material.direction = Vector3.UP
	_ember_material.spread = 22.0
	_ember_material.initial_velocity_min = 1.2
	_ember_material.initial_velocity_max = 4.0
	_ember_material.gravity = Vector3(0.0, 0.4, 0.0)
	_ember_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_ember_material.emission_ring_height = WALL_HEIGHT * 0.5
	_ember_material.emission_ring_axis = Vector3.UP
	_embers.process_material = _ember_material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_mat.albedo_color = Color(1.0, 0.3, 0.06)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.12, 0.015)
	ember_mat.emission_energy_multiplier = 2.0
	quad.material = ember_mat
	_embers.draw_pass_1 = quad
	_embers.visible = false
	add_child(_embers)


func _build_beacon() -> void:
	if _beacon != null:
		return
	_beacon = Node3D.new()
	_beacon.name = "DestinationBeacon"
	_beacon.top_level = true
	_beacon.visible = false
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.12
	shaft_mesh.bottom_radius = 0.45
	shaft_mesh.height = BEACON_HEIGHT
	shaft_mesh.radial_segments = 12
	shaft.mesh = shaft_mesh
	shaft.position.y = BEACON_HEIGHT * 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.68, 0.24, 0.58)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.32, 0.08)
	material.emission_energy_multiplier = 1.6
	shaft.material_override = material
	_beacon.add_child(shaft)
	_destination_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.94
	ring_mesh.outer_radius = 1.0
	_destination_ring.mesh = ring_mesh
	_destination_ring.position.y = 0.12
	_destination_ring.material_override = material
	_beacon.add_child(_destination_ring)
	var label := Label3D.new()
	label.text = "FINAL SAFE ZONE"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.81, 0.47)
	label.font_size = 36
	label.pixel_size = 0.04
	label.position.y = BEACON_HEIGHT + 1.0
	_beacon.add_child(label)
	add_child(_beacon)


func _set_environment_stage(stage: int) -> void:
	if not is_instance_valid(_environment):
		_environment = get_tree().get_first_node_in_group(&"world_environment") as WorldEnvironment
	if _environment == null or _environment.environment == null:
		return
	if _original_environment == null:
		_original_environment = _environment.environment
		_environment.environment = _original_environment.duplicate(true) as Environment

	var env := _environment.environment
	var tint := STAGE_TINTS[clampi(stage - 1, 0, STAGE_TINTS.size() - 1)]
	var strength := 0.12 + 0.08 * float(clampi(stage, 1, 4))
	env.background_color = _original_environment.background_color.lerp(tint, strength)
	env.fog_enabled = true
	env.fog_light_color = _original_environment.fog_light_color.lerp(tint, strength)
	env.fog_sky_affect = _original_environment.fog_sky_affect if _original_environment.fog_enabled else 0.12
	env.fog_density = maxf(_original_environment.fog_density if _original_environment.fog_enabled else 0.0,
		0.012 * strength)
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		var original_sky := _original_environment.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = original_sky.sky_top_color.lerp(tint, strength)
		sky.sky_horizon_color = original_sky.sky_horizon_color.lerp(tint, strength)


func _restore_environment() -> void:
	if is_instance_valid(_environment) and _original_environment:
		_environment.environment = _original_environment
	_original_environment = null
