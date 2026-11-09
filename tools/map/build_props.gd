extends SceneTree
## Turns the imported CC0 models into game-ready prop scenes. Owner: furnishing pass (S05 follow-up).
## Run: godot --headless --path the-last-fire-mage --script ../tools/map/build_props.gd -- --no-steam
## Writes game/props/<name>.tscn. Every scene has its origin at floor centre and faces +Z, with metas
## `footprint` (Vector2, x and z metres) and `height`. The town generator reads those metas.
## NET: offline authoring tool.

const FANTASY := "res://game/map/props/third_party/quaternius_fantasy_props/"
const NATURE := "res://game/map/props/third_party/quaternius_stylized_nature/"
const FURNITURE_LAYER := 256
const OUT := "res://game/props/"

## TUNE: name -> model, fit axis ("h" height, otherwise longest side), metres, kind, yaw that faces +Z,
## and an optional y stretch for models whose proportions are too squat for the villagers.
## Sizes are for the 1.0 m villager and the 1.76 m doors, so furniture reads slightly oversized.
const PROPS := {
	"chair": [FANTASY + "Chair_1.gltf", "h", 0.82, "break", 0.0],
	"stool": [FANTASY + "Stool.gltf", "h", 0.40, "break", 0.0],
	"bench": [FANTASY + "Bench.gltf", "w", 1.10, "break", 0.0],
	"table": [FANTASY + "Table_Large.gltf", "w", 1.35, "break", 0.0, 1.4],
	"barrel": [FANTASY + "Barrel.gltf", "h", 0.72, "break", 0.0],
	"barrel_apples": [FANTASY + "Barrel_Apples.gltf", "h", 0.78, "break", 0.0],
	"crate": [FANTASY + "Crate_Wooden.gltf", "h", 0.52, "break", 0.0],
	"crate_apples": [FANTASY + "FarmCrate_Apple.gltf", "h", 0.42, "break", 0.0],
	"shelf": [FANTASY + "Shelf_Simple.gltf", "w", 0.95, "wall", 0.0],
	"bookcase": [FANTASY + "Bookcase_2.gltf", "h", 1.45, "break", 0.0],
	"cabinet": [FANTASY + "Cabinet.gltf", "w", 1.05, "break", 0.0],
	"nightstand": [FANTASY + "Nightstand_Shelf.gltf", "h", 0.50, "break", 0.0],
	"workbench": [FANTASY + "Workbench.gltf", "w", 1.35, "break", 0.0],
	"chest": [FANTASY + "Chest_Wood.gltf", "w", 0.72, "break", 0.0],
	"bed": [FANTASY + "Bed_Twin1.gltf", "l", 1.50, "solid", 0.0],
	"bed_alt": [FANTASY + "Bed_Twin2.gltf", "l", 1.50, "solid", 0.0],
	"cauldron": [FANTASY + "Cauldron.gltf", "h", 0.55, "solid", 0.0],
	"bucket": [FANTASY + "Bucket_Wooden_1.gltf", "h", 0.30, "decor", 0.0],
	"candle_stand": [FANTASY + "CandleStick_Stand.gltf", "h", 1.05, "solid", 0.0],
	"candles": [FANTASY + "CandleStick_Triple.gltf", "h", 0.30, "decor", 0.0],
	"books": [FANTASY + "Book_Stack_1.gltf", "h", 0.14, "decor", 0.0],
	"vase": [FANTASY + "Vase_2.gltf", "h", 0.50, "solid", 0.0],
	"tree_common_a": [NATURE + "CommonTree_1.gltf", "h", 6.4, "trunk", 0.0],
	"tree_common_b": [NATURE + "CommonTree_2.gltf", "h", 5.6, "trunk", 0.0],
	"tree_common_c": [NATURE + "CommonTree_3.gltf", "h", 7.0, "trunk", 0.0],
	"tree_olive_a": [NATURE + "TwistedTree_1.gltf", "h", 4.2, "trunk", 0.0],
	"tree_olive_b": [NATURE + "TwistedTree_2.gltf", "h", 3.8, "trunk", 0.0],
	"tree_olive_c": [NATURE + "TwistedTree_3.gltf", "h", 4.6, "trunk", 0.0],
	"tree_pine_a": [NATURE + "Pine_1.gltf", "h", 6.2, "trunk", 0.0],
	"tree_pine_b": [NATURE + "Pine_2.gltf", "h", 5.0, "trunk", 0.0],
	"bush": [NATURE + "Bush_Common.gltf", "h", 0.80, "decor", 0.0],
	"bush_flowers": [NATURE + "Bush_Common_Flowers.gltf", "h", 0.85, "decor", 0.0],
	"flowers_a": [NATURE + "Flower_3_Group.gltf", "h", 0.34, "decor", 0.0],
	"flowers_b": [NATURE + "Flower_4_Group.gltf", "h", 0.34, "decor", 0.0],
	"flower_a": [NATURE + "Flower_3_Single.gltf", "h", 0.30, "decor", 0.0],
	"flower_b": [NATURE + "Flower_4_Single.gltf", "h", 0.30, "decor", 0.0],
	"grass_short": [NATURE + "Grass_Common_Short.gltf", "h", 0.20, "decor", 0.0],
	"grass_tall": [NATURE + "Grass_Common_Tall.gltf", "h", 0.36, "decor", 0.0],
	"grass_wisp": [NATURE + "Grass_Wispy_Tall.gltf", "h", 0.42, "decor", 0.0],
	"fern": [NATURE + "Fern_1.gltf", "h", 0.42, "decor", 0.0],
	"clover": [NATURE + "Clover_1.gltf", "h", 0.12, "decor", 0.0],
}

## Wall fixtures: model, fit metres, light offset, light energy, yaw that points the mount at -Z.
const LIGHTS := {
	"torch": [FANTASY + "Torch_Metal.gltf", 0.62, Vector3(0, 0.52, 0.09), 1.5, 0.0],
	"lantern": [FANTASY + "Lantern_Wall.gltf", 0.52, Vector3(0, 0.1, 0.15), 1.3, 0.0],
}

## Pot plus a plant set into it: pot model, pot height, plant model, plant height.
const POTS := {
	"pot_plant_fern": [FANTASY + "Vase_4.gltf", 0.36, NATURE + "Fern_1.gltf", 0.26],
	"pot_plant_flowers": [FANTASY + "Vase_4.gltf", 0.32, NATURE + "Flower_4_Group.gltf", 0.30],
	"pot_plant_leafy": [FANTASY + "Vase_4.gltf", 0.34, NATURE + "Plant_1.gltf", 0.52],
	"pot_plant_tall": [FANTASY + "Vase_2.gltf", 0.42, NATURE + "Plant_1.gltf", 0.72],
}


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var failed := false
	for key: String in PROPS:
		failed = not _make_prop(key, PROPS[key]) or failed
	for key: String in LIGHTS:
		failed = not _make_light(key, LIGHTS[key]) or failed
	for key: String in POTS:
		failed = not _make_pot(key, POTS[key]) or failed
	print("[Props] Built %d scenes, failed=%s" % [PROPS.size() + LIGHTS.size() + POTS.size(), failed])
	quit(1 if failed else 0)


func _load_model(path: String, yaw: float) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Props] Missing model " + path)
		return null
	var model := packed.instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = yaw
	return model


# Bounds of every mesh under `node`, in `node`'s parent space.
func _bounds(node: Node3D) -> AABB:
	var holder := Node3D.new()
	root.add_child(holder)
	var parent := node.get_parent()
	if parent:
		parent.remove_child(node)
	holder.add_child(node)
	var box := AABB()
	var first := true
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		pending.append_array(current.get_children())
		if current is MeshInstance3D:
			var mesh_box: AABB = (current as MeshInstance3D).global_transform * (current as MeshInstance3D).get_aabb()
			box = mesh_box if first else box.merge(mesh_box)
			first = false
	holder.remove_child(node)
	holder.queue_free()
	if parent:
		parent.add_child(node)
	return box


# Scales and shifts the model so its footprint centres on the origin and its base is at y = 0.
func _fit(model: Node3D, axis: String, metres: float, y_stretch := 1.0) -> Vector3:
	var box := _bounds(model)
	var measure := box.size.y if axis == "h" else maxf(box.size.x, box.size.z)
	var factor := metres / measure
	model.scale = Vector3(factor, factor * y_stretch, factor)
	box = _bounds(model)
	var centre := box.get_center()
	model.position = Vector3(-centre.x, -box.position.y, -centre.z)
	return box.size


func _body(kind: String) -> Node3D:
	var body: Node3D
	if kind == "break":
		body = StaticBody3D.new()
		body.set_script(load("res://game/props/breakable_prop.gd"))
	elif kind in ["solid", "trunk"]:
		body = StaticBody3D.new()
	else:
		body = Node3D.new()
	if body is StaticBody3D:
		(body as StaticBody3D).collision_layer = FURNITURE_LAYER
		(body as StaticBody3D).collision_mask = 0
	return body


func _collider(body: Node3D, kind: String, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	if kind == "trunk":
		var shape := CylinderShape3D.new()
		shape.radius = clampf(minf(size.x, size.z) * 0.07, 0.14, 0.26)
		shape.height = 2.4
		collider.shape = shape
		collider.position.y = 1.2
	else:
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x * 0.92, size.y, size.z * 0.92)
		collider.shape = shape
		collider.position.y = size.y / 2.0
	body.add_child(collider)
	collider.owner = body


func _save(root_node: Node3D, key: String) -> bool:
	root_node.name = key.to_pascal_case()
	var scene := PackedScene.new()
	var result := scene.pack(root_node)
	if result == OK:
		result = ResourceSaver.save(scene, OUT + key + ".tscn")
	root_node.free()
	if result != OK:
		push_error("[Props] Could not save %s: %d" % [key, result])
	return result == OK


func _make_prop(key: String, spec: Array) -> bool:
	var kind: String = spec[3]
	var body := _body("solid" if kind == "wall" else kind)
	var model := _load_model(spec[0], spec[4])
	if model == null:
		return false
	body.add_child(model)
	var size := _fit(model, spec[1], spec[2], float(spec[5]) if spec.size() > 5 else 1.0)
	model.owner = body
	body.set_meta("footprint", Vector2(size.x, size.z))
	body.set_meta("height", size.y)
	if body is StaticBody3D:
		_collider(body, kind, size)
	return _save(body, key)


func _make_light(key: String, spec: Array) -> bool:
	var body := Node3D.new()
	var model := _load_model(spec[0], spec[4])
	if model == null:
		return false
	body.add_child(model)
	var size := _fit(model, "h", spec[1])
	model.owner = body
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.position = spec[2]
	light.light_color = Color(1.0, 0.62, 0.32)
	light.light_energy = spec[3]
	light.omni_range = 4.6
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	# WHY: dozens of rooms have a light; only nearby ones should cost anything.
	light.distance_fade_enabled = true
	light.distance_fade_begin = 16.0
	light.distance_fade_length = 6.0
	body.add_child(light)
	light.owner = body
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var shape := SphereMesh.new()
	shape.radius = 0.055
	shape.height = 0.16
	shape.radial_segments = 6
	shape.rings = 3
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.62, 0.2)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.5, 0.12)
	fire.emission_energy_multiplier = 3.0
	shape.material = fire
	flame.mesh = shape
	flame.position = spec[2]
	body.add_child(flame)
	flame.owner = body
	body.set_meta("footprint", Vector2(size.x, size.z))
	body.set_meta("height", size.y)
	return _save(body, key)


func _make_pot(key: String, spec: Array) -> bool:
	var body := StaticBody3D.new()
	body.collision_layer = FURNITURE_LAYER
	body.collision_mask = 0
	var pot := _load_model(spec[0], 0.0)
	var plant := _load_model(spec[2], 0.0)
	if pot == null or plant == null:
		return false
	body.add_child(pot)
	var pot_size := _fit(pot, "h", spec[1])
	pot.owner = body
	plant.name = "Plant"
	body.add_child(plant)
	var plant_size := _fit(plant, "h", spec[3])
	plant.owner = body
	plant.position.y += pot_size.y * 0.82
	var size := Vector3(pot_size.x, pot_size.y, pot_size.z)
	_collider(body, "solid", size)
	body.set_meta("footprint", Vector2(size.x, size.z))
	body.set_meta("height", pot_size.y * 0.82 + plant_size.y)
	return _save(body, key)
