## Short-lived hit flash, procedural sound and victim camera shake / wave arc.
## Owner: S09. Public API: hit(point, victim), wave(origin, aim, reach, angle), locator(points, origin, reach, show_time). Cosmetic on each peer.
extends Node3D

## Displays confirmed damage at the target; shakes only the victim's local camera.
func hit(point: Vector3, victim: Player) -> void:
	global_position = point
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	var flash := _mesh(mesh)
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 0.01, 0.18)
	if victim and victim.is_local():
		var camera := victim.camera
		var shake := create_tween()
		shake.tween_property(camera, "h_offset", 0.065, 0.04)
		shake.tween_property(camera, "h_offset", -0.045, 0.05)
		shake.tween_property(camera, "h_offset", 0.0, 0.08)
	var sound := AudioStreamPlayer3D.new()
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 16000
	var data := PackedByteArray()
	data.resize(2400)
	for i in 1200:
		data.encode_s16(i * 2, int(sin(float(i) * 0.13) * 9000.0 * (1.0 - float(i) / 1200.0)))
	sample.data = data
	sound.stream = sample
	add_child(sound)
	sound.play()
	get_tree().create_timer(0.3).timeout.connect(queue_free)

## Expanding forward arc represents the server's instantaneous cone attack.
func wave(origin: Vector3, aim: Vector3, reach: float, angle: float) -> void:
	global_position = origin
	var forward := Vector3(aim.x, 0.0, aim.z).normalized()
	for i in 13:
		var mesh := SphereMesh.new()
		mesh.radius = 0.15
		mesh.height = 0.3
		var spark := _mesh(mesh)
		var direction := forward.rotated(Vector3.UP, deg_to_rad(lerpf(-angle * 0.5, angle * 0.5, float(i) / 12.0)))
		var tween := create_tween()
		tween.tween_property(spark, "position", direction * reach, 0.3)
		tween.parallel().tween_property(spark, "scale", Vector3.ONE * 0.1, 0.3)
	get_tree().create_timer(0.35).timeout.connect(queue_free)

## Locate: a ring sweeps out to `reach` so the cast always shows, then marks each villager through walls.
## WHY: the old fixed-size label rendered only a few pixels wide, too small to notice in play.
func locator(points: PackedVector3Array, origin: Vector3, reach: float, show_time: float) -> void:
	global_position = origin + Vector3.UP * 0.3
	var torus := TorusMesh.new()
	torus.inner_radius = 0.97
	torus.outer_radius = 1.0
	var ring := _mesh(torus)
	(ring.material_override as StandardMaterial3D).no_depth_test = true
	ring.scale = Vector3.ONE * 0.1
	var sweep := create_tween()
	sweep.tween_property(ring, "scale", Vector3(reach, 1.0, reach), 0.5)
	sweep.tween_callback(ring.queue_free)
	for point in points:
		var diamond := SphereMesh.new()
		diamond.radius = 0.28
		diamond.height = 0.8
		diamond.radial_segments = 4
		diamond.rings = 1
		var marker := _mesh(diamond)
		(marker.material_override as StandardMaterial3D).no_depth_test = true
		marker.global_position = point
		var pulse := create_tween().set_loops(int(ceil(show_time / 0.5)))
		pulse.tween_property(marker, "scale", Vector3.ONE * 1.35, 0.25)
		pulse.tween_property(marker, "scale", Vector3.ONE, 0.25)
	get_tree().create_timer(show_time).timeout.connect(queue_free)

func _mesh(shape: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.4, 0.05)
	node.material_override = material
	add_child(node)
	return node
