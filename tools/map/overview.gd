extends SceneTree
## Renders one small greybox overview without opening the editor. Owner: S05.
## Public API: CLI --script ../tools/map/overview.gd -- --no-steam --preview-dir=/tmp.
## NET: offline preview tool; temporary lighting is never packed into the town.


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	root.size = Vector2i(1120, 820)
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(load("res://game/map/town.tscn").instantiate())
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.28, 0.38, 0.41)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.83, 0.87, 0.95)
	env.ambient_light_energy = 0.42
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -31, 0)
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 116
	camera.far = 600
	world.add_child(camera)
	var dir := "/tmp"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-dir="):
			dir = arg.trim_prefix("--preview-dir=")
	camera.position = Vector3(51, 108, 143)
	camera.look_at(Vector3(0, 0, 3))
	camera.current = true
	var ok := await _capture(dir.path_join("playable-v7-overview.png"))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 74
	camera.position = Vector3(-3.20, 4.54, -17.73)
	camera.look_at(Vector3(-11.2, 6.08, -17.79))
	ok = await _capture(dir.path_join("playable-v7-alley.png")) and ok
	quit(0 if ok else 1)


func _capture(path: String) -> bool:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	print("[Map] Preview ", path, ": ", result)
	return result == OK
