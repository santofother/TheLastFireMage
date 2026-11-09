## Short-lived hit flash, procedural sound and victim camera shake / wave arc.
## Owner: S09. Public API: hit(point, victim), wave(origin, aim, reach, angle), locator(points). Cosmetic on each peer.
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

## FIX(S14, Codex): Briefly marks the sensed positions through walls for the local mage.
func locator(points: PackedVector3Array) -> void:
	for point in points:
		var marker := Label3D.new()
		marker.text = "◇"
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.fixed_size = true
		marker.font_size = 32
		marker.pixel_size = 0.001
		marker.modulate = Color(1.0, 0.56, 0.2)
		add_child(marker)
		marker.global_position = point
	get_tree().create_timer(0.8).timeout.connect(queue_free)

func _mesh(shape: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.4, 0.05)
	node.material_override = material
	add_child(node)
	return node
