extends SceneTree
## Data-driven greybox town writer and synchronous chicken navmesh baker. Owner: S05.
## Public API: CLI --script tools/map/generate.gd -- --no-steam; reads layout.json, writes town.tscn.
## NET: offline authoring tool; the saved static scene is identical on every peer.

var _town: Node3D
var _region: NavigationRegion3D
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _shapes: Dictionary = {}
var _layout: Dictionary
var _coastal: Node3D
const WALL := 0.22
const STOREY := 2.7
const DOOR := 1.48
const DOOR_TOP := 2.02
const STAIR_WIDTH := 1.72
const STAIR_START := -2.55
const STAIR_END := 2.15


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	var path := ProjectSettings.globalize_path("res://../tools/map/layout.json")
	_layout = JSON.parse_string(FileAccess.get_file_as_string(path))
	_town = Node3D.new()
	_town.name = "Town"
	_town.set_meta("layout_version", _layout.version)
	_town.set_meta("footprint", Vector2(_layout.footprint[0], _layout.footprint[1]))
	root.add_child(_town)
	for key: String in _layout.palette:
		var rgb: Array = _layout.palette[key]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(rgb[0], rgb[1], rgb[2])
		mat.roughness = 1.0
		_materials[key] = mat
	_region = NavigationRegion3D.new()
	_region.name = "ChickenNavigation"
	_add(_town, _region)
	_ground()
	for district: Dictionary in _layout.districts:
		var neighbourhood := _container(_region, district.name, Vector3.ZERO, "map_district")
		for house: Array in district.houses:
			_house(neighbourhood, house)
	_street(_layout.spine, 3.2, "paving")
	var spine := _container(_town, "MainStreet", Vector3.ZERO)
	for point: Array in _layout.spine:
		_marker(spine, "Bend%02d" % spine.get_child_count(),
			Vector3(point[0], _ground_y(point[1]), point[1]), "map_main_street")
	for lane: Array in _layout.lanes:
		_street(lane, 1.55, "paving")
	_landmarks()
	_waterfront()
	_routes()
	var hide_scene := load("res://game/interact/hide_spot.tscn") as PackedScene
	for i in _layout.hide_spots.size():
		var spot := hide_scene.instantiate() as Node3D
		spot.name = "HideSpot%02d" % i
		spot.position = _v(_layout.hide_spots[i])
		_add(_region, spot)
	for group: String in ["villager_spawn", "mage_spawn", "chicken_spawn", "item_spawn"]:
		for i in _layout[group].size():
			var marker := Marker3D.new()
			marker.name = "%s_%02d" % [group, i]
			marker.position = _v(_layout[group][i])
			marker.add_to_group(group, true)
			_add(_town, marker)
	# Wait for instanced CSG hide crates to build before parsing source geometry.
	for i in 4:
		await physics_frame
	var nav := NavigationMesh.new()
	for key: String in _layout.navigation:
		nav.set(key, _layout.navigation[key])
	nav.agent_max_slope = 45
	nav.geometry_collision_mask = 1
	# WHY: collision ramps make stairs walkable; bake those instead of decorative treads.
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, _region)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	_region.navigation_mesh = nav
	if nav.get_polygon_count() == 0:
		push_error("[Map] Empty bake; scene was not saved")
		quit(1)
		return
	var scene := PackedScene.new()
	var result := scene.pack(_town)
	if result == OK:
		result = ResourceSaver.save(scene, "res://game/map/town.tscn")
	print("[Map] Generated town: %d nav polygons, save result %d" % [nav.get_polygon_count(), result])
	quit(0 if result == OK else 1)


func _add(parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = _town


func _visual(parent: Node3D, label: String, pos: Vector3, size: Vector3, colour: String) -> MeshInstance3D:
	var mesh_key := "%s:%s" % [size, colour]
	if not _meshes.has(mesh_key):
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _materials[colour]
		_meshes[mesh_key] = mesh
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.position = pos
	visual.mesh = _meshes[mesh_key]
	_add(parent, visual)
	return visual


func _box(parent: Node3D, label: String, pos: Vector3, size: Vector3, colour: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	_add(parent, body)
	_visual(body, "Mesh", Vector3.ZERO, size, colour)
	if not _shapes.has(size):
		var shape := BoxShape3D.new()
		shape.size = size
		_shapes[size] = shape
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = _shapes[size]
	_add(body, collider)
	return body


func _v(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


func _container(parent: Node3D, label: String, pos: Vector3, group: String = "") -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = pos
	_add(parent, node)
	if not group.is_empty():
		node.add_to_group(group, true)
	return node


func _marker(parent: Node3D, label: String, pos: Vector3, group: String) -> Marker3D:
	var node := Marker3D.new()
	node.name = label
	node.position = pos
	node.add_to_group(group, true)
	_add(parent, node)
	return node


func _ground_y(z: float) -> float:
	var bands: Array = _layout.terrain
	for i in range(1, bands.size()):
		var a: Array = bands[i - 1]
		var b: Array = bands[i]
		if z <= b[0]:
			return lerpf(a[1], b[1], clampf(inverse_lerp(a[0], b[0], z), 0, 1))
	return bands[-1][1]


func _ground() -> void:
	var land := _container(_region, "Hillside", Vector3.ZERO)
	var bands: Array = _layout.terrain
	var half := float(_layout.footprint[0]) / 2
	for i in range(1, bands.size()):
		var a: Array = bands[i - 1]
		var b: Array = bands[i]
		_wedge(land, "Slope%d" % i, -half, half, Vector2(a[0], a[1]), Vector2(b[0], b[1]), -2.9, "earth")
		for side in [-1, 1]:
			var x := half * float(side)
			_wedge(land, "Ridge%d_%d" % [i, side], x - 0.55, x + 0.55,
				Vector2(a[0] + (0.55 if i == 1 else 0.0), a[1] + 4.4), Vector2(b[0], b[1] + 4.4), -2.9, "cliff")
	_box(land, "NorthRidge", Vector3(0, 6.3, bands[0][0]), Vector3(2 * half + 1.1, 9.6, 1.1), "cliff")


func _street(points: Array, width: float, colour: String) -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size()):
		var a := Vector2(points[i - 1][0], points[i - 1][1])
		var b := Vector2(points[i][0], points[i][1])
		var steps := ceili(a.distance_to(b) / 0.3)
		var across := (b - a).normalized().orthogonal() * width / 2
		for j in steps:
			var p := a.lerp(b, float(j) / steps)
			var q := a.lerp(b, float(j + 1) / steps)
			for point: Vector2 in [p + across, p - across, q - across, p + across, q - across, q + across]:
				mesh.add_vertex(Vector3(point.x, _ground_y(point.y) + (0.032 if colour == "square" else 0.023), point.y))
	mesh.generate_normals()
	var strip := MeshInstance3D.new()
	strip.mesh = mesh.commit()
	strip.material_override = _materials[colour]
	strip.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(_region, strip)


func _landmarks() -> void:
	for plaza: Array in _layout.plazas:
		var p := Vector3(plaza[1], _ground_y(plaza[2]), plaza[2])
		var node := _container(_region, plaza[0], p, "map_landmark")
		_street([[plaza[1], plaza[2] - plaza[4] / 2.0], [plaza[1], plaza[2] + plaza[4] / 2.0]], plaza[3], "square")
		match plaza[0]:
			"FishMarket":
				for side in [-1, 1]:
					_box(node, "StallLeg", Vector3(side * 1.48, 1.08, 0), Vector3(0.18, 2.16, 0.20), "wood")
				_box(node, "StallAwning", Vector3(0, 2.25, 0), Vector3(3.35, 0.18, 1.65), "indigo")
				_box(node, "FishCounter", Vector3(0, 0.36, 0), Vector3(1.8, 0.72, 0.75), "wood")
			"CisternSquare":
				_round_platform(node, "Cistern", 1.1, -0.48, 0.8, "stone")
				_round_platform(node, "Rim", 1.23, 0.8, 0.98, "ashlar")
			"ChapelSquare":
				_round_platform(node, "Plinth", 1.35, -0.1, 0.55, "stone")
				_box(node, "Pillar", Vector3(0, 1.39, 0), Vector3(0.53, 1.68, 0.53), "ashlar")
				_box(node, "Cap", Vector3(0, 2.29, 0), Vector3(0.74, 0.12, 0.74), "ochre")
	for bed: Array in _layout.gardens:
		_planter(_region, Vector3(bed[0], _ground_y(bed[1]), bed[1]), Vector2(bed[2], bed[3]))
	for spec: Array in _layout.nooks:
		var p := Vector3(spec[1], _ground_y(spec[2]), spec[2])
		var nook := _container(_region, spec[0], p, "map_nook")
		nook.rotation_degrees.y = spec[3]
		_box(nook, "Back", Vector3(0, 1.15, -1.55), Vector3(3.35, 2.3, 0.30), "stone")
		for side in [-1, 1]:
			_box(nook, "Side%d" % side, Vector3(side * 1.52, 1.15, 0.15), Vector3(0.30, 2.3, 3.1), "stone")


func _round_platform(parent: Node3D, label: String, radius: float, bottom: float, top: float, colour: String) -> void:
	var points := PackedVector3Array()
	for y: float in [bottom, top]:
		for i in 12:
			var angle := TAU * i / 12.0
			points.append(Vector3(radius * cos(angle), y, radius * sin(angle)))
	_solid(parent, label, points, colour)


func _planter(parent: Node3D, p: Vector3, size: Vector2) -> void:
	_box(parent, "Bed", p + Vector3(0, 0.18, 0), Vector3(size.x, 0.36, size.y), "stone")
	_visual(parent, "Planting", p + Vector3(0, 0.365, 0), Vector3(size.x - 0.16, 0.025, size.y - 0.16), "garden")


func _house(parent: Node3D, spec: Array) -> void:
	var style: Dictionary = _layout.templates[spec[1]]
	var x := float(spec[2])
	var z := float(spec[3])
	var levels := int(spec[4])
	var opts: Dictionary = spec[7] if spec.size() > 7 else {}
	var w := float(style.width)
	var d := float(style.depth)
	var sealed := int(opts.get("window_floor", -1))
	var house := _container(parent, spec[0], Vector3(x, _ground_y(z), z), "map_house")
	house.rotation_degrees.y = float(spec[5])
	house.set_meta("template", spec[1])
	house.set_meta("storeys", levels)
	for level in levels:
		var h := float(opts.get("top_height", STOREY)) if level == levels - 1 else STOREY
		var floor := _container(house, "Storey%d" % level, Vector3(0, level * STOREY, 0), "map_storey")
		var stairs: bool = level + 1 != sealed and (level != sealed or level < levels - 1)
		var stair_x := (-1 if level % 2 == 0 and level != sealed and spec[1] != "court" else 1) * (w / 2 - WALL - STAIR_WIDTH / 2)
		var arcade: bool = spec[1] == "passage" and level == 0
		var across := 0.0 if arcade else (1.65 if spec[1] == "court" else 0.0)
		var upper_door: bool = spec[1] == "through" and level == 1
		_facade(floor, "Front", d / 2, w, h, spec[6], level == 0, across)
		_facade(floor, "Back", -d / 2, w, h, spec[6], arcade or upper_door)
		for side in [-1, 1]:
			var face := _container(floor, "Side%d" % side, Vector3(side * (w - WALL) / 2, 0, 0))
			face.rotation.y = PI / 2
			var opening: bool = side == -1 and level == sealed
			var sill := float(opts.get("sill", 0.58))
			var window_x := -float(opts.get("window_z", 0.0))
			_wall(face, d - WALL * 2, h - 0.16, spec[6],
				[window_x, 1.72, sill, h - 0.20] if opening else [])
			if opening:
				_trim(face, window_x, 1.72, sill, h - 0.20, "open_window")
				_box(face, "VaultSill", Vector3(window_x, sill / 2, 0), Vector3(1.72, sill, 0.96), "open_window")
			else:
				_shutter(face, -2.1, h)
				_shutter(face, 2.1, h)
		if arcade:
			for side in [-1, 1]:
				var shop := _container(floor, "ShopWall%d" % side, Vector3(side * 1.25, 0, 0))
				shop.rotation.y = PI / 2
				_wall(shop, d - 2 * WALL, h - 0.16, "stone", [0.0, DOOR, 0.0, DOOR_TOP])
				_marker(shop, "ShopDoor", Vector3.ZERO, "map_room_opening")
		elif spec[1] == "court" and level == 0:
			var court := _container(floor, "CourtWall", Vector3.ZERO)
			court.rotation.y = PI / 2
			_wall(court, d - 2 * WALL, h - 0.16, "stone", [0.0, DOOR, 0.0, DOOR_TOP])
			_marker(court, "CourtDoor", Vector3.ZERO, "map_room_opening")
			_planter(floor, Vector3(-w / 4, 0, -1.7), Vector2(2.8, 2.8))
		else:
			var core := STAIR_WIDTH if stairs or (level > 0 and level != sealed) else 0.0
			var partition := _container(floor, "RoomDivider", Vector3(0, 0, -1.95 if level == sealed else 0.0))
			_wall(partition, w - 2 * WALL - 2 * core, h - 0.16, "interior", [0.0, DOOR, 0.0, DOOR_TOP])
			_marker(partition, "RoomDoor", Vector3.ZERO, "map_room_opening")
		if stairs:
			_stairs(floor, "Stairs", Vector3(stair_x, 0, STAIR_START), STAIR_WIDTH, STAIR_END - STAIR_START, h)
			# Courtyards leave the west half open to the sky.
			var west := 0.0 if spec[1] == "court" and level == 0 else -w / 2
			_cut_deck(floor, west, w / 2, d, h, stair_x, STAIR_WIDTH, STAIR_START - 0.12, STAIR_END, level == levels - 1)
		else:
			_deck(floor, "Ceiling", -w / 2, w / 2, -d / 2, d / 2, h, "roof" if level == levels - 1 else "interior")
	if spec[0] == "Chapel":
		var roof_y := levels * STOREY
		_box(house, "BellCrown", Vector3(0.6, roof_y + 0.53, 0.3), Vector3(1.9, 1.06, 1.9), "stone")
		_box(house, "Cornice", Vector3(0.6, roof_y + 1.12, 0.3), Vector3(2.04, 0.12, 2.04), "roof")
		_visual(house, "ChapelBanner", Vector3(0, roof_y - 1.22, d / 2 + 0.02), Vector3(0.82, 1.6, 0.055), "indigo")
	if spec[1] == "through":
		var end_z := float(opts.upper_lane_z)
		var bridge := _container(_region, "UpperWalk" + house.name, Vector3(x, 0, 0))
		_wedge(bridge, "RetainingWalk", -1.25, 1.25, Vector2(z - d / 2, house.position.y + STOREY),
			Vector2(end_z, _ground_y(end_z)), house.position.y - 0.2, "stone")


func _facade(floor: Node3D, label: String, z: float, width: float, h: float, colour: String, door: bool, x: float = 0.0) -> void:
	var face := _container(floor, label, Vector3(0, 0, z - signf(z) * WALL / 2))
	var cut := [x, DOOR, 0.0, DOOR_TOP] if door else []
	if floor.get_parent().get_meta("template") == "passage" and floor.name == "Storey0":
		cut = [0.0, 2.28, 0.0, h - 0.2]
	_wall(face, width, h - 0.16, colour, cut)
	_shutter(face, -width / 2 + 1.52, h)
	_shutter(face, width / 2 - 1.52, h)
	if door:
		var entry := _marker(floor, label + "Door", Vector3(x, 0, z), "map_house_exit")
		entry.rotation.y = 0 if z > 0 else PI


func _wall(parent: Node3D, width: float, h: float, colour: String, hole: Array) -> void:
	if hole.is_empty():
		_wall_piece(parent, "Wall", -width / 2, width / 2, 0, h, colour)
		return
	var left := float(hole[0]) - float(hole[1]) / 2
	var right := left + float(hole[1])
	_wall_piece(parent, "Left", -width / 2, left, 0, h, colour)
	_wall_piece(parent, "Right", right, width / 2, 0, h, colour)
	_wall_piece(parent, "Below", left, right, 0, hole[2], colour)
	_wall_piece(parent, "Header", left, right, hole[3], h, colour)


func _wall_piece(parent: Node3D, label: String, left: float, right: float, bottom: float, top: float, colour: String) -> void:
	if right > left and top > bottom:
		_box(parent, label, Vector3((left + right) / 2, (bottom + top) / 2, 0),
			Vector3(right - left, top - bottom, WALL), colour)


func _trim(parent: Node3D, x: float, w: float, bottom: float, top: float, colour: String) -> void:
	for side in [-1, 1]:
		_visual(parent, "Jamb", Vector3(x + side * (w / 2 + 0.045), (top + bottom) / 2, 0),
			Vector3(0.09, top - bottom, WALL + 0.07), colour)
	_visual(parent, "HeaderTrim", Vector3(x, top + 0.015, 0), Vector3(w + 0.18, 0.08, WALL + 0.07), colour)


func _shutter(parent: Node3D, x: float, height: float) -> void:
	var bottom := minf(0.91, height - 1.2)
	_trim(parent, x, 0.82, bottom, bottom + 0.88, "trim")
	_visual(parent, "Shutter", Vector3(x, bottom + 0.44, 0), Vector3(0.82, 0.88, WALL + 0.045), "shutter")


func _deck(parent: Node3D, label: String, x0: float, x1: float, z0: float, z1: float, y: float, colour: String) -> void:
	_box(parent, label, Vector3((x0 + x1) / 2, y - 0.08, (z0 + z1) / 2), Vector3(x1 - x0, 0.16, z1 - z0), colour)


func _cut_deck(parent: Node3D, west: float, east: float, d: float, h: float, sx: float, sw: float, z0: float, z1: float, roof: bool) -> void:
	var colour := "roof" if roof else "interior"
	var left := sx - sw / 2
	var right := sx + sw / 2
	_deck(parent, "DeckWest", west, left, -d / 2, d / 2, h, colour)
	_deck(parent, "DeckEast", right, east, -d / 2, d / 2, h, colour)
	_deck(parent, "FootLanding", left, right, -d / 2, z0, h, colour)
	_deck(parent, "TopLanding", left, right, z1, d / 2, h, colour)


func _stairs(parent: Node3D, label: String, pos: Vector3, width: float, run: float, rise: float) -> void:
	var stair := _container(parent, label, pos, "map_stair_ramp")
	_wedge(stair, "WalkableRamp", -width / 2, width / 2, Vector2.ZERO, Vector2(run, rise), -0.1, "")
	var steps := ceili(absf(rise) / 0.16)
	var tread := run / steps
	for i in steps:
		var top := rise * (float(i) + 0.5) / steps
		_visual(stair, "Tread%02d" % i, Vector3(0, top - 0.10, (i + 0.5) * tread),
			Vector3(width, 0.2, tread), "stone")
	_marker(stair, "Foot", Vector3(0, 0, -0.65), "map_stair_end")
	_marker(stair, "Landing", Vector3(0, rise, run + 0.65), "map_stair_end")


func _wedge(parent: Node3D, label: String, x0: float, x1: float, a: Vector2, b: Vector2, bottom: float, colour: String) -> void:
	_prism(parent, label, PackedVector2Array([Vector2(a.x, bottom), Vector2(b.x, bottom), b, a]), x0, x1, colour)


# Convex cross section in (z, y), extruded along x. Also used for the arch voussoirs.
func _prism(parent: Node3D, label: String, section: PackedVector2Array, x0: float, x1: float, colour: String) -> void:
	var points := PackedVector3Array()
	for x: float in [x0, x1]:
		for p in section:
			points.append(Vector3(x, p.y, p.x))
	_solid(parent, label, points, colour)


func _solid(parent: Node3D, label: String, points: PackedVector3Array, colour: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_mask = 0
	_add(parent, body)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_add(body, collider)
	if not colour.is_empty():
		_convex_visual(body, points, colour)


func _convex_visual(parent: Node3D, points: PackedVector3Array, colour: String) -> void:
	# Input vertices are two matching rings. Flat faces keep neighbouring sand and stone pieces seamless.
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_smooth_group(-1)
	var count := points.size() / 2
	var centre := Vector3.ZERO
	for p in points:
		centre += p / float(points.size())
	for i in range(1, count - 1):
		_triangle(mesh, points[0], points[i], points[i + 1], centre)
		_triangle(mesh, points[count], points[count + i], points[count + i + 1], centre)
	for i in count:
		var j := (i + 1) % count
		_triangle(mesh, points[i], points[j], points[j + count], centre)
		_triangle(mesh, points[i], points[j + count], points[i + count], centre)
	mesh.generate_normals()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh.commit()
	visual.material_override = _materials[colour]
	_add(parent, visual)


func _triangle(mesh: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3) -> void:
	var flip := (c - a).cross(b - a).dot(a - centre) < 0
	mesh.add_vertex(a)
	mesh.add_vertex(c if flip else b)
	mesh.add_vertex(b if flip else c)


func _waterfront() -> void:
	var data: Dictionary = _layout.waterfront
	_coastal = _container(_region, "Waterfront", Vector3.ZERO, "map_landmark")
	var quay: Array = data.quay
	var pier: Array = data.pier
	var bed := float(data.bed)
	_box(_town, "RecoveryShelf", Vector3(0, bed - 0.35, 51.5), Vector3(65, 0.7, 31), "seabed")
	var water := _visual(_town, "Sea", Vector3(0, data.water - 0.05, 0), Vector3(650, 0.1, 650), "sea")
	var sea := water.mesh.surface_get_material(0) as StandardMaterial3D
	sea.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sea.albedo_color.a = 0.78
	_box(_coastal, "QuayDeck", Vector3((quay[0] + quay[1]) / 2.0, -0.22, (quay[2] + quay[3]) / 2.0),
		Vector3(quay[1] - quay[0], 0.44, quay[3] - quay[2]), "paving")
	_box(_coastal, "DockDeck", Vector3((pier[0] + pier[1]) / 2.0, -0.22, (quay[3] + pier[2]) / 2.0),
		Vector3(pier[1] - pier[0], 0.44, pier[2] - quay[3]), "paving")
	var seafront := _container(_coastal, "QuayArcade", Vector3(0, 0, quay[3] - 0.76))
	seafront.rotation.y = PI / 2
	var span := 3.2
	var bays := floori((quay[1] - quay[0]) / span)
	span = (quay[1] - quay[0]) / bays
	for i in bays:
		_arch(seafront, quay[0] + (i + 0.5) * span, span, 0.95, bed)
	span = (pier[2] - quay[3]) / 6
	for x: float in [pier[0] + 0.65, pier[1] - 0.65]:
		var arcade := _container(_coastal, "DockArcade", Vector3(x, 0, 0))
		for i in 6:
			_arch(arcade, quay[3] + (i + 0.5) * span, span, 0.64, bed)
	_beach(data.beach, quay[3], bed)
	var access: Array = data.beach_stairs
	var stairs := _container(_coastal, "BeachSteps", Vector3(access[0], -1.15, access[1]))
	stairs.rotation.y = PI
	_stairs(stairs, "Steps", Vector3.ZERO, 4.0, access[1] - quay[3], 1.15)
	var slipway := _container(_coastal, "RecoverySteps", Vector3(23, bed, 49))
	slipway.rotation.y = PI
	_stairs(slipway, "Steps", Vector3.ZERO, 3.2, 49 - quay[3], -bed)
	for boat: Array in data.boats:
		_boat(boat, bed)


func _arch(parent: Node3D, z: float, span: float, width: float, bed: float) -> void:
	var bay := _container(parent, "StoneBay", Vector3(0, 0, z))
	var radius := span / 2 - 0.30
	var spring := -1.89
	for side in [-1, 1]:
		_box(bay, "Pier", Vector3(0, (bed - 0.44) / 2, side * (radius + 0.15)),
			Vector3(width * 2, -0.44 - bed, 0.30), "stone")
	for i in 10:
		var a := PI * float(i) / 10
		var b := PI * float(i + 1) / 10
		var p := Vector2(radius * cos(a), spring + radius * sin(a))
		var q := Vector2(radius * cos(b), spring + radius * sin(b))
		_prism(bay, "Voussoir%d" % i, PackedVector2Array([p, q, Vector2(q.x, -0.44), Vector2(p.x, -0.44)]),
			-width, width, "stone" if i % 2 == 0 else "ashlar")


func _beach(profile: Array, quay_edge: float, bed: float) -> void:
	# Each cross-section sets the inner flat sand and the curved waterline.
	var beach := _container(_coastal, "CrescentBeach", Vector3.ZERO)
	for i in range(1, profile.size()):
		var a: Array = profile[i - 1]
		var b: Array = profile[i]
		var aa := [Vector3(a[0], -1.15, quay_edge), Vector3(a[0], -1.15, a[1]), Vector3(a[0], bed, a[2])]
		var bb := [Vector3(b[0], -1.15, quay_edge), Vector3(b[0], -1.15, b[1]), Vector3(b[0], bed, b[2])]
		for band in 2:
			_sand_triangle(beach, [aa[band], bb[band], bb[band + 1]], bed)
			_sand_triangle(beach, [aa[band], bb[band + 1], aa[band + 1]], bed)


func _sand_triangle(parent: Node3D, corners: Array, bed: float) -> void:
	var points := PackedVector3Array()
	for p: Vector3 in corners:
		points.append(Vector3(p.x, bed - 0.28, p.z))
	points.append_array(PackedVector3Array(corners))
	_solid(parent, "SandBank", points, "sand")


func _boat(spec: Array, bed: float) -> void:
	var deck_y := float(spec[3])
	var boat := _container(_coastal, spec[0], Vector3(spec[1], deck_y, spec[2]), "map_boat")
	var w := float(spec[4]) / 2.0
	var d := float(spec[5]) / 2.0
	var outline := PackedVector2Array([Vector2(-w, -d * 0.50), Vector2(-w * 0.65, -d * 0.90),
		Vector2(0, -d), Vector2(w * 0.65, -d * 0.90), Vector2(w, -d * 0.50), Vector2(w, d * 0.66),
		Vector2(w * 0.60, d), Vector2(-w * 0.60, d), Vector2(-w, d * 0.66)])
	var points := PackedVector3Array()
	for p in outline:
		points.append(Vector3(p.x * 0.68, bed - deck_y - 0.05, p.y * 0.79))
	for p in outline:
		points.append(Vector3(p.x, 0, p.y))
	_solid(boat, "Hull", points, spec[6])
	var decking := SurfaceTool.new()
	decking.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, outline.size() - 1):
		for p: Vector2 in [outline[0], outline[i], outline[i + 1]]:
			decking.add_vertex(Vector3(p.x * 0.94, 0.012, p.y * 0.94))
	decking.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = "DeckPlanks"
	visual.mesh = decking.commit()
	visual.material_override = _materials["wood"]
	_add(boat, visual)
	for end in [-1, 1]:
		_visual(boat, "Gunwale", Vector3(0, 0.04, end * d * 0.73), Vector3(w * 1.32, 0.09, 0.15), spec[6])
	boat.set_meta("deck_size", Vector2(w * 2, d * 2))


func _routes() -> void:
	for platform: Array in _layout.roof_platforms:
		_deck(_region, platform[0], platform[1], platform[2], platform[3], platform[4], platform[5], "wood")
	for flight: Array in _layout.roof_stairs:
		var frame := _container(_region, flight[0], _v(flight[1]))
		frame.rotation_degrees.y = flight[2]
		_stairs(frame, "Steps", Vector3.ZERO, flight[3], flight[4], flight[5])
	for walk: Array in _layout.walk_links:
		var link := _marker(_town, walk[0] + "Route", _v(walk[1]), "map_walk_link")
		link.set_meta("landing", _v(walk[2]))
	for route: Array in _layout.routes:
		var marker := _marker(_town, route[0], _v(route[1]), "map_traversal")
		marker.set_meta("takeoff", _v(route[2]))
		marker.set_meta("landing", _v(route[3]))
		marker.set_meta("kind", route[4])
