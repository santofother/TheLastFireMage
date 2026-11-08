extends SceneTree
## Renders one small greybox overview without opening the editor. Owner: S05.
## Public API: CLI --script ../tools/map/overview.gd -- --no-steam; saves /tmp/s05-town-overview.png.
## NET: offline preview tool; temporary lighting is never packed into the town.


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	root.size = Vector2i(960, 720)
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(load("res://game/map/town.tscn").instantiate())
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.21, 0.30, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.89, 0.79)
	env.ambient_light_energy = 0.7
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 200
	camera.far = 600
	world.add_child(camera)
	camera.position = Vector3(95, 150, 145)
	camera.look_at(Vector3(0, 0, -2))
	camera.current = true
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("/tmp/s05-town-overview.png")
	print("[Map] Overview save result ", result)
	quit(0 if result == OK else 1)
