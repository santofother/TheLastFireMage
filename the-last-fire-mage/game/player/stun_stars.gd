class_name StunStars
extends Node3D
## Cartoon "seeing stars" ring: five outlined yellow stars and a little swirl orbit a stunned player's
## head on a tilted, wobbling ring. Owner: Player (bug-fixing-n-addiotions).
## NET: purely local visuals; every peer drives it from its own copy of the stun timer.
## Public API: `tick(delta, active, head_y)`.

const STAR_COUNT := 5
const RING_RADIUS := 0.42 ## TUNE: m
const SPIN_SPEED := 5.0 ## TUNE: rad/s

var _ring: Node3D
var _stars: Array[Node3D] = []
var _t := 0.0
var _pop := 0.0


func _init() -> void:
	name = "StunFx"
	visible = false
	_ring = Node3D.new()
	add_child(_ring)
	var fill := _material(Color(1.0, 0.86, 0.15), 1)
	var outline := _material(Color(0.12, 0.06, 0.02), 0)
	var star_mesh := _star_mesh(0.13, 0.055)
	var outline_mesh := _star_mesh(0.165, 0.08)
	for i in STAR_COUNT:
		var star := Node3D.new()
		var back := MeshInstance3D.new()
		back.mesh = outline_mesh
		back.material_override = outline
		back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var front := MeshInstance3D.new()
		front.mesh = star_mesh
		front.material_override = fill
		front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		star.add_child(back)
		star.add_child(front)
		_ring.add_child(star)
		_stars.append(star)
	# A thin white swirl ring under the stars, like a cartoon daze circle.
	var swirl := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.02
	torus.outer_radius = RING_RADIUS + 0.02
	torus.rings = 24
	torus.ring_segments = 6
	swirl.mesh = torus
	var swirl_mat := StandardMaterial3D.new()
	swirl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	swirl_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	swirl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	swirl.material_override = swirl_mat
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(swirl)


## Call every frame. `active` shows/hides; `head_y` is the local height of the top of the head.
func tick(delta: float, active: bool, head_y: float) -> void:
	if not active:
		visible = false
		_pop = 0.0
		return
	visible = true
	_t += delta
	_pop = minf(1.0, _pop + delta * 6.0)
	# Pop in with a little overshoot, then bob and wobble.
	var pop := 1.0 + sin(_pop * PI) * 0.35 if _pop < 1.0 else 1.0
	scale = Vector3.ONE * pop * _pop
	position.y = head_y + 0.28 + sin(_t * 4.0) * 0.04
	_ring.rotation = Vector3(sin(_t * 2.3) * 0.28, _t * SPIN_SPEED, cos(_t * 1.9) * 0.22)
	for i in _stars.size():
		var a := TAU * i / _stars.size()
		var star := _stars[i]
		star.position = Vector3(cos(a) * RING_RADIUS, sin(_t * 6.0 + a * 2.0) * 0.05, sin(a) * RING_RADIUS)
		var twinkle := 0.85 + 0.25 * sin(_t * 9.0 + a * 3.0)
		star.scale = Vector3.ONE * twinkle


func _material(color: Color, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.render_priority = priority
	return mat


# Flat five-point star in the XY plane (billboarded by the material).
func _star_mesh(outer: float, inner: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var points: Array[Vector3] = []
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := PI / 2.0 + TAU * i / 10.0
		points.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for i in 10:
		verts.append(Vector3.ZERO)
		verts.append(points[i])
		verts.append(points[(i + 1) % 10])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
