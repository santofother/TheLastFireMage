extends SceneTree
## Turns the imported Zappy Pixel and Stylized Nature models into game-ready prop scenes. Owner: furnishing pass (S05 follow-up).
## Run: godot --headless --path the-last-fire-mage --script ../tools/map/build_props.gd -- --no-steam
## Writes game/props/<name>.tscn. Every scene has its origin at floor centre and faces +Z, with metas
## `footprint` (Vector2, x and z metres) and `height`. The town generator reads those metas.
## NET: offline authoring tool.

const INTERIOR := "res://game/map/props/third_party/zappypixel_interior/"
const NATURE := "res://game/map/props/third_party/stylized_nature_pack/"
## WHY: each nature FBX is a grid of many models, so a spec names one mesh as "file.fbx#Node".
const BUSHES := NATURE + "bushes.fbx#"
const FLOWER_BUSHES := NATURE + "flower_bushes.fbx#"
const FLOWERS := NATURE + "flowers.fbx#"
const GRASS := NATURE + "grass.fbx#"
const TREES := NATURE + "normal_trees.fbx#"
const PALMS := NATURE + "palm_trees.fbx#"
const MESH_DIR := NATURE + "meshes/"
const FURNITURE_LAYER := 256
const OUT := "res://game/props/"

## TUNE: name -> model, fit axis ("h" height, otherwise longest side), metres, kind, yaw that faces +Z,
## and an optional y stretch for models whose proportions are too squat for the villagers.
## Sizes are for the 1.0 m villager and the 1.76 m doors, so furniture reads slightly oversized.
## WHY: the interior pack has only 14 models, so one model can fill several roles (shelf_01 is really a low bench).
const PROPS := {
	"chair": [INTERIOR + "stool_01.glb", "h", 0.62, "break", 0.0],
	"stool": [INTERIOR + "stool_01.glb", "h", 0.50, "break", 0.0],
	"bench": [INTERIOR + "shelf_01.glb", "w", 1.10, "break", 0.0, 1.5],
	"table": [INTERIOR + "table_01.glb", "w", 1.35, "break", 0.0],
	"workbench": [INTERIOR + "table_01.glb", "w", 1.55, "break", 0.0],
	"crate": [INTERIOR + "box_05.glb", "w", 0.85, "break", 0.0, 1.25],
	"chest": [INTERIOR + "box_04_animation.glb", "w", 0.72, "break", 0.0],
	"shelf": [INTERIOR + "shelf_01.glb", "w", 0.95, "wall", 0.0, 2.2],
	"cauldron": [INTERIOR + "pot_03.glb", "h", 0.55, "solid", 0.0],
	"vase": [INTERIOR + "bottle_02.glb", "h", 0.50, "solid", 0.0],
	"candles": [INTERIOR + "candlestick_01.glb", "h", 0.30, "decor", 0.0],
	"books": [INTERIOR + "paper_01.glb", "w", 0.34, "decor", 0.0],
	"bottle": [INTERIOR + "bottle_06.glb", "h", 0.26, "decor", 0.0],
	"bowl": [INTERIOR + "bowl_04.glb", "w", 0.30, "decor", 0.0],
	"tree_common_a": [TREES + "NormalTree_1", "h", 6.4, "trunk", 0.0],
	"tree_common_b": [TREES + "NormalTree_2", "h", 5.6, "trunk", 0.0],
	"tree_common_c": [TREES + "NormalTree_3", "h", 5.0, "trunk", 0.0],
	"tree_small_a": [TREES + "NormalTree_4", "h", 4.4, "trunk", 0.0],
	"tree_small_b": [TREES + "NormalTree_5", "h", 3.2, "trunk", 0.0],
	"tree_palm_a": [PALMS + "PalmTree_1", "h", 5.6, "trunk", 0.0],
	"tree_palm_b": [PALMS + "PalmTree_2", "h", 5.0, "trunk", 0.0],
	"tree_palm_c": [PALMS + "PalmTree_3", "h", 4.4, "trunk", 0.0],
	"bush": [BUSHES + "Bush", "h", 0.80, "decor", 0.0],
	"bush_flowers": [BUSHES + "Bush_Flowers", "h", 0.85, "decor", 0.0],
	"flowers_a": [FLOWERS + "Flower_3_Clump", "h", 0.34, "decor", 0.0],
	"flowers_b": [FLOWERS + "Flower_4_Clump", "h", 0.34, "decor", 0.0],
	"flower_a": [FLOWERS + "Flower_1", "h", 0.30, "decor", 0.0],
	"flower_b": [FLOWERS + "Flower_2", "h", 0.30, "decor", 0.0],
	"grass_short": [GRASS + "Grass_Small", "h", 0.22, "decor", 0.0],
	"grass_tall": [GRASS + "Grass_Large_Extruded", "h", 0.36, "decor", 0.0],
	"grass_wisp": [GRASS + "Grass_Large_Extruded", "h", 0.46, "decor", 0.0],
	"fern": [BUSHES + "Plant_1", "h", 0.34, "decor", 0.0],
	"clover": [FLOWER_BUSHES + "Plant_2", "h", 0.14, "decor", 0.0],
}

## Wall fixtures: a candlestick on a small bracket. The model has its own flame, so only a light is added.
## Model, fit metres, light offset, light energy, yaw.
## WHY: the interior pack has no wall light, so the bracket is shelf_01 shrunk and deepened.
const BRACKET := INTERIOR + "shelf_01.glb"
const LIGHTS := {
	"torch": [INTERIOR + "candlestick_01.glb", 0.34, Vector3(0, 0.40, 0.16), 1.1, 0.0],
	"lantern": [INTERIOR + "candlestick_01.glb", 0.28, Vector3(0, 0.34, 0.16), 0.95, 0.0],
}

## Pot plus a plant set into it: pot model, pot height, plant model, plant height.
## WHY: the pack's only pot is the cauldron, so planters are its brown bowl.
const PLANT_SEAT := 0.6
const POTS := {
	"pot_plant_fern": [INTERIOR + "bowl_05.glb", 0.24, BUSHES + "Plant_1", 0.34],
	"pot_plant_flowers": [INTERIOR + "bowl_05.glb", 0.22, FLOWERS + "Flower_1_Clump", 0.36],
	"pot_plant_leafy": [INTERIOR + "bowl_05.glb", 0.24, FLOWER_BUSHES + "Plant_2", 0.36],
	"pot_plant_tall": [INTERIOR + "bowl_05.glb", 0.28, FLOWER_BUSHES + "Plant_Flowers", 0.62],
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
	if path.contains("#"):
		return _extract_mesh(path, yaw)
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Props] Missing model " + path)
		return null
	var model := packed.instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = yaw
	return model


# Pulls one named mesh out of a multi-model FBX and saves it as its own resource, so scenes reference
# it instead of inlining thousands of vertices as text.
func _extract_mesh(path: String, yaw: float) -> Node3D:
	var parts := path.split("#")
	var packed := load(parts[0]) as PackedScene
	if packed == null:
		push_error("[Props] Missing model " + parts[0])
		return null
	var source := packed.instantiate()
	var found := source.get_node_or_null(parts[1]) as MeshInstance3D
	if found == null:
		push_error("[Props] No mesh %s in %s" % [parts[1], parts[0]])
		source.free()
		return null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	var mesh_path := MESH_DIR + parts[1].to_snake_case() + ".res"
	if ResourceSaver.save(found.mesh, mesh_path) != OK:
		push_error("[Props] Could not save " + mesh_path)
		source.free()
		return null
	var model := Node3D.new()
	model.name = "Model"
	model.rotation.y = yaw
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = load(mesh_path) as Mesh
	# Keep the FBX rotation and unit scale but drop its offset within the grid.
	mesh.transform = Transform3D(found.transform.basis, Vector3.ZERO)
	model.add_child(mesh)
	source.free()
	return model


# Extracted models are plain nodes whose children must be owned to be saved; instanced ones are not.
func _adopt(model: Node3D, body: Node3D) -> void:
	model.owner = body
	if model.scene_file_path.is_empty():
		for child: Node in model.get_children():
			child.owner = body


# WHY: leaning palms and spreading trees have a canopy far from the trunk, so the bounds centre would
# leave the collider and the planting point beside the trunk. Uses the bark, always surface 0.
func _centre_on_trunk(model: Node3D) -> void:
	var mesh_node := model.get_node("Mesh") as MeshInstance3D
	var to_parent := model.transform * mesh_node.transform
	var points: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lowest := INF
	for point: Vector3 in points:
		lowest = minf(lowest, (to_parent * point).y)
	var sum := Vector2.ZERO
	var count := 0
	for point: Vector3 in points:
		var moved := to_parent * point
		if moved.y < lowest + 0.25:
			sum += Vector2(moved.x, moved.z)
			count += 1
	var base := sum / float(count)
	model.position -= Vector3(base.x, 0.0, base.y)


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
	if kind == "trunk":
		_centre_on_trunk(model)
	_adopt(model, body)
	body.set_meta("footprint", Vector2(size.x, size.z))
	body.set_meta("height", size.y)
	if body is StaticBody3D:
		_collider(body, kind, size)
	return _save(body, key)


func _make_light(key: String, spec: Array) -> bool:
	var body := Node3D.new()
	var bracket := _load_model(BRACKET, 0.0)
	var model := _load_model(spec[0], spec[4])
	if bracket == null or model == null:
		return false
	bracket.name = "Bracket"
	body.add_child(bracket)
	_fit(bracket, "w", 0.42, 0.5)
	bracket.scale.z *= 2.6
	bracket.position = Vector3.ZERO
	var bracket_box := _bounds(bracket)
	bracket.position = -Vector3(bracket_box.get_center().x, bracket_box.position.y, bracket_box.get_center().z)
	_adopt(bracket, body)
	body.add_child(model)
	var candle := _fit(model, "h", spec[1])
	model.position.y += bracket_box.size.y
	_adopt(model, body)
	var size := Vector3(maxf(bracket_box.size.x, candle.x), bracket_box.size.y + candle.y, maxf(bracket_box.size.z, candle.z))
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
	_adopt(pot, body)
	plant.name = "Plant"
	body.add_child(plant)
	var plant_size := _fit(plant, "h", spec[3])
	_adopt(plant, body)
	# WHY: the planter is a shallow bowl, so the plant sits just inside its rim.
	plant.position.y += pot_size.y * PLANT_SEAT
	var size := Vector3(pot_size.x, pot_size.y, pot_size.z)
	_collider(body, "solid", size)
	body.set_meta("footprint", Vector2(size.x, size.z))
	body.set_meta("height", pot_size.y * PLANT_SEAT + plant_size.y)
	return _save(body, key)
