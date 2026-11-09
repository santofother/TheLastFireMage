extends SceneTree
## Data-driven greybox town writer and synchronous chicken navmesh baker. Owner: S05.
## Public API: CLI --script tools/map/generate.gd -- --no-steam; reads layout.json, writes town.tscn.
## NET: offline authoring tool; the saved static scene is identical on every peer.

var _town: Node3D
var _region: NavigationRegion3D
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _shapes: Dictionary = {}
var _surfaces: Dictionary = {}
var _layout: Dictionary
var _coastal: Node3D
const WALL := 0.22
const DOOR := 1.14
const DOOR_TOP := 1.76
const WINDOW_HALF := 0.775
const BEDROCK := -2.9
const SHELL_BOTTOM := -3.1
const STREET_LEDGE := 0.44 # How far a block below head height may project into a lane as narrow as 1.65 m.
const STREET_FOOTING := 0.4 # Stand point on a street block: clears the mage radius from the wall.
const HEADROOM := 1.55 # A ledge this far above the lane clears the mage's head.
const MAX_CLIMB_HOP := 0.83 # Matches the tallest hop the roof routes already use.
const MAX_STREET_HOP := 0.88 # Tallest block a standing jump clears from the lane.
const BLOCK_RUN := 1.1 # Lane run-up beside a street block.
const HOP := 1.84 # Spacing between facade climbing holds, matching the roof routes.
var _plan: Node3D
var _houses: Dictionary = {}
var _knots: Array[float] = []
## One entry per storey, consumed by furnish.gd.
var _rooms: Array[Dictionary] = []


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
	_build_town()
	_waterfront()
	_loft_link("SaltLoft", "Fishers", 22.5)
	_loft_link("BellLoft", "BellWalk", -45.0)
	var rope_edge := Vector3(-13.2, _roof_height(_houses.RopeHouse), 25.83)
	var salt_roof := Vector3(-13.2, _roof_height(_houses.SaltLoft), 24.25)
	_jump_link("SaltLoftRoofLanding", rope_edge, rope_edge, salt_roof, "roof_landing")
	# Jump down from Chapel instead of walking up from Bell Loft on a ramp.
	var chapel_edge := Vector3(2.45, _roof_height(_houses.Chapel), -46.85)
	var bell_roof := Vector3(2.45, _roof_height(_houses.BellLoft), -44.4)
	_jump_link("BellLoftRoofLanding", chapel_edge, chapel_edge, bell_roof, "roof_landing")
	for house: String in _layout.roof_from_neighbour:
		_neighbour_roof_link(house, _layout.roof_from_neighbour[house])
	_spawn_points()
	_finish_surfaces()
	# Wait for instanced CSG hide crates to build before parsing source geometry.
	for i in 4:
		await physics_frame
	# Furniture checks clearance against the finished collision, so it runs after the walls settle.
	load("res://../tools/map/furnish.gd").new().run(self)
	for i in 3:
		await physics_frame
	var nav := NavigationMesh.new()
	for key: String in _layout.navigation:
		nav.set(key, _layout.navigation[key])
	nav.agent_max_slope = 45
	# WHY: furniture carves the navmesh (layer 9) so chickens and bots route around it.
	nav.geometry_collision_mask = 1 | 256
	# WHY: collision ramps make stairs walkable; bake those instead of decorative treads.
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, _region)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	var first_spawn := get_first_node_in_group("villager_spawn") as Node3D
	_retain_navigation_component(nav, first_spawn.position)
	_region.navigation_mesh = nav
	if nav.get_polygon_count() == 0:
		push_error("[Map] Empty bake; scene was not saved")
		quit(1)
		return
	var scene := PackedScene.new()
	var result := scene.pack(_town)
	if result == OK:
		# A compact native scene avoids parsing several megabytes of mesh arrays during LAN join.
		result = ResourceSaver.save(scene, "res://game/map/town_geometry.scn", ResourceSaver.FLAG_COMPRESS)
	if result == OK:
		var entry := FileAccess.open("res://game/map/town.tscn", FileAccess.WRITE)
		if entry == null:
			result = FileAccess.get_open_error()
		else:
			entry.store_string("""[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://game/map/town_geometry.scn" id="1_geometry"]

[node name="Town" instance=ExtResource("1_geometry")]
""")
			result = entry.get_error()
	print("[Map] Generated town: %d nav polygons, save result %d" % [nav.get_polygon_count(), result])
	quit(0 if result == OK else 1)


func _retain_navigation_component(nav: NavigationMesh, anchor: Vector3) -> void:
	# The bake can leave islands on ledges and roofs. A chicken cannot jump to those surfaces.
	if nav.get_polygon_count() == 0:
		return
	var vertices := nav.get_vertices()
	var polygons: Array[PackedInt32Array] = []
	var adjacent: Array[Array] = []
	var edges: Dictionary[Vector2i, int] = {}
	var seed := 0
	var distance := INF
	for i in nav.get_polygon_count():
		var polygon := nav.get_polygon(i)
		polygons.append(polygon)
		adjacent.append([])
		var centre := Vector3.ZERO
		for j in polygon.size():
			var a := polygon[j]
			var b := polygon[(j + 1) % polygon.size()]
			centre += vertices[a] / float(polygon.size())
			var edge := Vector2i(mini(a, b), maxi(a, b))
			if edges.has(edge):
				var other := edges[edge]
				adjacent[other].append(i)
				adjacent[i].append(other)
			else:
				edges[edge] = i
		var d := centre.distance_squared_to(anchor)
		if d < distance:
			distance = d
			seed = i
	var connected := {seed: true}
	var pending: Array[int] = [seed]
	var cursor := 0
	while cursor < pending.size():
		for other: int in adjacent[pending[cursor]]:
			if not connected.has(other):
				connected[other] = true
				pending.append(other)
		cursor += 1
	nav.clear_polygons()
	for i in polygons.size():
		if connected.has(i):
			nav.add_polygon(polygons[i])


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
	if not colour.is_empty():
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


func _stairs(parent: Node3D, label: String, pos: Vector3, width: float, run: float, rise: float) -> void:
	var stair := _container(parent, label, pos, "map_stair_ramp")
	_wedge(stair, "WalkableRamp", -width / 2, width / 2, Vector2.ZERO, Vector2(run, rise), -0.1, "")
	var steps := ceili(absf(rise) / 0.16)
	var tread := run / steps
	for i in steps:
		var top := rise * (float(i) + 0.5) / steps
		_visual(stair, "Tread%02d" % i, Vector3(0, top - 0.10, (i + 0.5) * tread),
			Vector3(width, 0.2, tread), "stone")
		if label == "RockTreads":
			_visual(stair, "CutStoneEdge", Vector3(0, top - 0.027, i * tread + 0.014),
				Vector3(width - 0.07, 0.045, 0.035), "ashlar")
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
		_buffer_faces(parent, points, colour)


func _buffer_faces(parent: Node3D, points: PackedVector3Array, colour: String) -> void:
	if not _surfaces.has(parent):
		_surfaces[parent] = {}
	var surfaces: Dictionary = _surfaces[parent]
	if not surfaces.has(colour):
		var mesh := SurfaceTool.new()
		mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		mesh.set_smooth_group(-1)
		surfaces[colour] = mesh
	_ring_faces(surfaces[colour], points)


func _finish_surfaces() -> void:
	# Keep per-piece collision, while batching the rendered masonry by node and material.
	for parent: Node3D in _surfaces:
		var surfaces: Dictionary = _surfaces[parent]
		for colour: String in surfaces:
			var mesh: SurfaceTool = surfaces[colour]
			mesh.generate_normals()
			var visual := MeshInstance3D.new()
			visual.name = "Surface_" + colour
			visual.mesh = mesh.commit()
			visual.material_override = _materials[colour]
			_add(parent, visual)
	_surfaces.clear()


func _ring_faces(mesh: SurfaceTool, points: PackedVector3Array) -> void:
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
	_box(_town, "RecoveryShelf", Vector3(0, bed - 0.35, 56.0), Vector3(68, 0.7, 40), "")
	var water := MeshInstance3D.new()
	water.name = "Sea"
	water.position.y = data.water
	var surface := PlaneMesh.new()
	surface.size = Vector2(650, 650)
	var sea := _materials.sea as StandardMaterial3D
	sea.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sea.albedo_color.a = 0.78
	surface.material = sea
	water.mesh = surface
	_add(_town, water)
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
	var landing := _container(_coastal, "BoatLanding", Vector3(2.86, -0.64, 49.5))
	landing.rotation.y = -PI / 2
	_stairs(landing, "TideSteps", Vector3.ZERO, 1.38, 1.36, 0.64)
	_deck(_coastal, "LandingBoards", 2.85, 3.9, 48.71, 50.29, -0.64, "wood")
	# The low landing sits outside the promenade, reached by steps on the east face.
	for boat: Array in data.boats:
		_boat(boat)
	_jump_link("DockToGull", Vector3(1.72, -0.104, 49.5), Vector3(3.18, -0.64, 49.5),
		Vector3(6.34, -0.95, 49.5), "boat_walk")
	_jump_link("GullToOtter", Vector3(7.05, -0.95, 50.00), Vector3(7.05, -0.95, 51.68),
		Vector3(7.05, -1.14, 55.52), "boat_sprint")
	_rock(_coastal, Vector3(-32, -2.78, 44.2), Vector3(6.6, 3.5, 6.8), 0.29)
	_rock(_coastal, Vector3(-34, -2.7, 48), Vector3(5, 2.4, 6), -0.51)
	_rock(_coastal, Vector3(-31, -2.65, 51.5), Vector3(3.1, 1.45, 4.6), 0.23)
	_rock(_coastal, Vector3(-5.5, -2.68, 44.5), Vector3(2.3, 2.4, 4.9), -0.38)


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
	var beach := _container(_coastal, "CrescentBeach", Vector3.ZERO, "map_beach")
	for i in range(1, profile.size()):
		var a := _sand_section(profile[i - 1], quay_edge, bed)
		var b := _sand_section(profile[i], quay_edge, bed)
		for band in a.size() - 1:
			var colour: String = ["sand", "sand", "wet_sand", "foam", "shallows"][band]
			_quad(beach, "SandBank", [a[band], b[band], b[band + 1]], bed - 0.29, colour)
			_quad(beach, "SandBank", [a[band], b[band + 1], a[band + 1]], bed - 0.29, colour)


func _sand_section(row: Array, edge: float, bed: float) -> Array[Vector3]:
	var wet := lerpf(row[2], row[3], 0.19)
	var wash := lerpf(row[2], row[3], 0.30)
	return [Vector3(row[0], -1.15, edge), Vector3(row[0], -1.15, row[1]),
		Vector3(row[0], -2.04, row[2]), Vector3(row[0], -2.13, wet),
		Vector3(row[0], -2.19, wash), Vector3(row[0], bed, row[3])]


func _boat(spec: Array) -> void:
	var boat := _container(_coastal, spec[0], Vector3(spec[1], spec[3], spec[2]), "map_boat")
	boat.rotation.y = spec[4]
	var model_path := "res://game/map/props/fishing_boats/fishing_boat_%s.glb" % spec[5]
	var model := (load(model_path) as PackedScene).instantiate() as Node3D
	model.scale.y = 0.74
	_add(boat, model)
	# Compact convex deck proxy follows the Blender hull's usable interior.
	var points := PackedVector3Array()
	for y: float in [-0.15, 0.0]:
		for side: int in [-1, 1]:
			for p: Vector2 in [Vector2(0.02, -2.57), Vector2(0.60, -1.89), Vector2(0.91, -1.23),
					Vector2(1.045, -0.45), Vector2(1.05, 0.46), Vector2(0.92, 1.28),
					Vector2(0.73, 1.95), Vector2(0.57, 2.32)]:
				points.append(Vector3(p.x * side, y, p.y))
	_solid(boat, "DeckCollision", points, "")
	boat.set_meta("deck_size", Vector2(2.10, 4.7))


# Street samples are z, centre x, elevation and width; lot edges follow the same knots.
func _sample(rows: Array, z: float) -> Vector3:
	for i in range(1, rows.size()):
		var a: Array = rows[i - 1]
		var b: Array = rows[i]
		if z <= b[0] or i == rows.size() - 1:
			var t := clampf(inverse_lerp(a[0], b[0], z), 0, 1)
			return Vector3(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t)) if a.size() > 2 else Vector3(lerpf(a[1], b[1], t), 0, 0)
	return Vector3.ZERO


func _street_at(lane: int, z: float) -> Vector3:
	return _sample(_layout.streets[lane], z)


func _edges(band: int, z: float) -> Vector2:
	var west := _street_at(maxi(band - 1, 0), z)
	var east := _street_at(mini(band, 2), z)
	return Vector2(_sample(_layout.edges[0], z).x if band == 0 else west.x + west.z / 2,
		_sample(_layout.edges[1], z).x if band == 3 else east.x - east.z / 2)


func _intervals(z0: float, z1: float) -> Array[float]:
	var result: Array[float] = [z0]
	for z in _knots:
		if z > z0 + 0.001 and z < z1 - 0.001:
			result.append(z)
	result.append(z1)
	return result


func _quad(parent: Node3D, label: String, top: Array, bottom: float, colour: String, thickness := 0.0) -> void:
	var points := PackedVector3Array()
	for p: Vector3 in top:
		points.append(Vector3(p.x, p.y - thickness if thickness > 0 else bottom, p.z))
	points.append_array(PackedVector3Array(top))
	_solid(parent, label, points, colour)


func _build_town() -> void:
	_plan = _container(_region, "StreetFabric", Vector3.ZERO)
	for rows: Array in _layout.streets + _layout.edges:
		for row: Array in rows:
			var z := float(row[0])
			if z not in _knots:
				_knots.append(z)
	_knots.sort()
	for lane in 3:
		var rows: Array = _layout.streets[lane]
		var street := _container(_plan, ["LimekilnLane", "WindingSpine", "RoccaLane"][lane], Vector3.ZERO)
		for i in range(1, rows.size()):
			var a: Array = rows[i - 1]
			var b: Array = rows[i]
			_quad(street, "Paving", [Vector3(a[1] - a[3] / 2, a[2], a[0]), Vector3(a[1] + a[3] / 2, a[2], a[0]),
				Vector3(b[1] + b[3] / 2, b[2], b[0]), Vector3(b[1] - b[3] / 2, b[2], b[0])], BEDROCK, "paving")
		for row: Array in rows:
			_marker(street, "Bend%02d" % street.get_child_count(), Vector3(row[1], row[2], row[0]),
				"map_main_street" if lane == 1 else "map_side_street")
	for band in 4:
		var district: Dictionary = _layout.districts[band]
		var neighbourhood := _container(_region, district.name, Vector3.ZERO, "map_district")
		for spec: Array in district.lots:
			_lot(neighbourhood, band, spec)
	for cut: Array in _layout.cuts:
		_cut(cut)
	_bookends()


func _plot_point(band: int, u: float, y: float, z: float) -> Vector3:
	var edge := _edges(band, z)
	return Vector3(lerpf(edge.x, edge.y, u), y, z)


func _plot_box(parent: Node3D, label: String, band: int, u0: float, u1: float, z0: float, z1: float,
		bottom: float, top: float, colour: String) -> void:
	if z1 - z0 < 0.002 or u1 - u0 < 0.002 or top - bottom < 0.002:
		return
	var sections := _intervals(z0, z1)
	for i in range(1, sections.size()):
		var a := sections[i - 1]
		var b := sections[i]
		_quad(parent, label, [_plot_point(band, u0, top, a), _plot_point(band, u1, top, a),
			_plot_point(band, u1, top, b), _plot_point(band, u0, top, b)], bottom, colour)


func _lot(parent: Node3D, band: int, spec: Array) -> void:
	var z0 := float(spec[1])
	var z1 := float(spec[2])
	var levels := int(spec[3])
	var east: bool = spec[4] == "east"
	var entry_z := lerpf(z0, z1, 0.33 if levels == 3 else 0.68)
	if spec[0] == "SaltLoft":
		entry_z = 22.5
	if spec[0] == "BellLoft":
		entry_z = -45.0
	var lane := band if east else band - 1
	var height := _street_at(lane, entry_z).y
	var house := _container(parent, spec[0], Vector3.ZERO, "map_house" if levels > 0 else "map_court")
	var edge := _edges(band, entry_z)
	var wall_u := clampf(WALL / (edge.y - edge.x), 0.012, 0.052)
	var door_u := 1.0 if east else 0.0
	var spacing := 2.28 + 0.08 * (String(spec[0]).length() % 4)
	var loft: bool = spec.size() > 8 and spec[8] == "loft"
	var passage: bool = spec[5] == "passage"
	# CONTRACT: no flight of stairs reaches a roof; every roof is climbed or jumped to.
	var parkour: bool = levels >= 1 and not loft
	# A sealed house has no street door. Its top-floor rear window is the only way inside.
	var sealed: bool = spec[0] in _layout.sealed_doors
	var back_u := 1.0 - door_u
	var back_lane := band - 1 if east else band
	# Put the window at the opposite end from the stair that serves this room.
	var route_dir := -1.0 if levels == 2 else 1.0
	if passage:
		entry_z = (z0 + z1) * 0.5
		height = _street_at(lane, entry_z).y
	if spec[0] == "BellLoft":
		spacing = 2.76
	if spec[0] == "SaltLoft":
		spacing = 2.55
	if spec[0] == "JuniperCourt":
		entry_z = 0.45
		height = 1.78 # Keep the engine's void return at (0, 2, 0) inside this public court.
	house.set_meta("template", spec[5])
	house.set_meta("storeys", levels)
	house.set_meta("sealed", sealed)
	_houses[spec[0]] = {"node": house, "band": band, "spec": spec, "base": height, "spacing": spacing,
		"entry_z": entry_z, "east": east, "lane": lane}
	if band in [0, 3]:
		_bluff(house, band, z0, z1, height, String(spec[0]).hash())
	if levels == 0:
		_garden(house, band, z0, z1, height, wall_u, door_u, entry_z)
		return
	_plot_box(house, "StoneFooting", band, 0, 1, z0, z1, SHELL_BOTTOM, height, "deep_stone")
	_threshold(house, band, lane, door_u, entry_z, height, DOOR)
	var roof_colour: String = ["roof", "tile_sienna", "tile_dusk"][String(spec[0]).hash() % 3]
	if passage:
		_threshold(house, band, band - 1 if east else band, 1.0 - door_u, entry_z, height, 1.46)
	for level in levels:
		var y := height + level * spacing
		var floor := _container(house, "Storey%d" % level, Vector3.ZERO, "map_storey")
		var roof := level == levels - 1
		var covered := passage and level == 0
		var route_z := z1 - 1.08 if route_dir < 0.0 else z0 + 1.08
		# A one-storey front wall keeps its door; its climb starts from the street instead of a window.
		var window_z := route_z if parkour and roof and levels >= 2 else entry_z
		for side in 2:
			var front := is_equal_approx(float(side), door_u)
			var door := level == 0 and (front or covered) and not sealed
			var window := roof and levels >= 2 and (front and (loft or parkour) or sealed and not front)
			_face(floor, band, side, z0, z1, y, y + spacing - 0.14, wall_u, spec[6], window_z,
				1.50 if covered else (WINDOW_HALF * 2.0 if window else (DOOR if door else 0.0)),
				(0.24 if parkour else 0.26) if window else 0.0, spacing - 0.17 if window else DOOR_TOP,
				front or covered, window and parkour)
			if door:
				_door_link(floor, "StreetDoor", _plot_point(band, side, y, entry_z), Vector3.RIGHT if side else Vector3.LEFT)
		# Double skins meet at the party line. Side walls enclose split-level neighbours independently.
		for end in [z0, z1 - WALL]:
			_plot_box(floor, "PartyWall", band, 0, 1, end, end + WALL, y, y + spacing - 0.14, spec[6])
		# Stairs change ends each floor so the next flight never hangs over the previous landing.
		var at_north := level % 2 == 0
		var stair_z := z0 + 1.02 if at_north else z1 - 1.02
		var stairs := not (loft and level >= levels - 2) and not (parkour and roof)
		var split := (z0 + z1) * 0.5 if not covered else entry_z - 0.94
		_partition(floor, band, split, y, spacing, wall_u, spec[5] in ["court", "chapel"])
		if covered:
			_partition(floor, band, entry_z + 0.94, y, spacing, wall_u, false)
		if level == 0 and spec[0] == "Porters":
			var aisle := split + 0.55
			_walk_link("PortersRearRoom", _plot_point(band, 0.64, y, aisle), _plot_point(band, 0.046, y, aisle))
		var top := y + spacing
		_rooms.append({"house": String(spec[0]), "floor": floor, "band": band, "z0": z0, "z1": z1, "y": y, "level": level,
			"levels": levels, "split": split, "covered": covered, "entry_z": entry_z, "template": String(spec[5]), "loft": loft})
		if stairs:
			_lot_stair(floor, band, stair_z, z0, z1, y, spacing, roof, roof_colour, split, spec[5] in ["court", "chapel"])
		else:
			_plot_box(floor, "Ceiling", band, 0, 1, z0, z1, top - 0.14, top, roof_colour if roof else "interior")
		if roof:
			_roof(house, band, z0, z1, top, spec[7], roof_colour, door_u if parkour else -1.0)
			if parkour and levels >= 2:
				_facade_route(floor, band, door_u, route_z, route_dir, y, top)
				if sealed:
					_rear_window_climb(floor, band, back_u, route_z, route_dir, y, back_lane)
			elif parkour and not _layout.roof_from_neighbour.has(spec[0]):
				_street_roof_route(floor, band, door_u, lane, y, top, z0, z1, entry_z)
		if sealed and level == 0:
			_facade_box(floor, "BoardedDoor", band, door_u, entry_z, DOOR / 2, -0.02, 0.06, y, y + DOOR_TOP, "wood")
	if spec[0] == "Chapel":
		var tower := _plot_point(band, 0.30, height + levels * spacing, -51.1)
		_box(house, "BellTower", tower + Vector3.UP * 0.88, Vector3(1.65, 1.76, 1.65), "ashlar")
		_box(house, "BellCornice", tower + Vector3.UP * 1.79, Vector3(1.94, 0.18, 1.94), "roof")


func _face(parent: Node3D, band: int, side: int, z0: float, z1: float, y: float, top: float,
		u: float, colour: String, at: float, width: float, sill: float, header: float, facing: bool,
		parkour: bool) -> void:
	var left := 0.0 if side == 0 else 1.0 - u
	var right := u if side == 0 else 1.0
	if width > 0:
		var start := at - width / 2
		var end := at + width / 2
		_plot_box(parent, "JambNorth", band, left, right, z0, start, y, top, colour)
		_plot_box(parent, "JambSouth", band, left, right, end, z1, y, top, colour)
		_plot_box(parent, "Lintel", band, left, right, start, end, y + header, top, "ashlar")
		if not parkour:
			_plot_box(parent, "Sill", band, left, right, start, end, y, y + sill, "ashlar")
	else:
		_plot_box(parent, "Facade", band, left, right, z0, z1, y, top, colour)
	if not parkour and (facing or (band == 0 and side == 0) or (band == 3 and side == 1)):
		var span := _edges(band, at)
		var w := span.y - span.x
		var trim := u * 0.32
		var outer := -trim if side == 0 else 1.0 + trim
		var inner := 0.01 if side == 0 else 0.99
		for z: float in [lerpf(z0, z1, 0.23), lerpf(z0, z1, 0.77)]:
			if width == 0 or absf(z - at) > width / 2 + 0.45:
				var shutter_width := clampf((z1 - z0) * 0.095 + w * 0.002, 0.51, 0.79)
				_plot_box(parent, "Shutter", band, minf(outer, inner), maxf(outer, inner),
					z - shutter_width / 2, z + shutter_width / 2, y + 0.91, y + 1.64, "shutter")


func _door_link(parent: Node3D, label: String, at: Vector3, normal: Vector3) -> void:
	var door := _marker(parent, label, at, "map_house_exit" if label == "StreetDoor" else "map_room_opening")
	door.rotation.y = atan2(normal.x, normal.z)


func _threshold(parent: Node3D, band: int, lane: int, side: float, z: float, y: float, width: float) -> void:
	var outer: Array[Vector3] = []
	for at: float in [z - width * 0.52, z + width * 0.52]:
		var road := _street_at(lane, at)
		var door := _plot_point(band, side, y + 0.006, at)
		outer.append(door)
		outer.append(Vector3(lerpf(door.x, road.x, 0.64), road.y + 0.008, at))
	# Split the twisted threshold into two planar wedges.
	_quad(parent, "Doorstep", [outer[0], outer[1], outer[3]], 0, "ashlar", 0.16)
	_quad(parent, "Doorstep", [outer[0], outer[3], outer[2]], 0, "ashlar", 0.16)


func _partition(parent: Node3D, band: int, at: float, y: float, height: float, skin: float, offset: bool) -> void:
	var edge := _edges(band, at)
	var width := (edge.y - edge.x)
	var centre := 0.64 if offset else 0.48
	var half := DOOR / width / 2
	var start := at - 0.09
	var end := at + 0.09
	_plot_box(parent, "RoomWall", band, skin * 0.85, centre - half, start, end, y, y + height - 0.14, "interior")
	_plot_box(parent, "RoomWall", band, centre + half, 1.0 - skin * 0.85, start, end, y, y + height - 0.14, "interior")
	_plot_box(parent, "RoomLintel", band, centre - half, centre + half, start, end, y + DOOR_TOP, y + height - 0.14, "ashlar")
	_door_link(parent, "RoomDoor", _plot_point(band, centre, y, at), Vector3.BACK)


func _lot_stair(parent: Node3D, band: int, z: float, z0: float, z1: float, y: float, rise: float,
		roof: bool, tile: String, split: float, offset_door: bool) -> void:
	var edge := _edges(band, z)
	var width := edge.y - edge.x
	var run := minf(4.05, width - 1.86)
	var lo := 0.5 - run / width / 2
	var hi := 1.0 - lo
	var half := 0.65
	var top := y + rise
	var stair := _container(parent, "Stairs", Vector3.ZERO, "map_stair_ramp")
	var treads := SurfaceTool.new()
	treads.begin(Mesh.PRIMITIVE_TRIANGLES)
	treads.set_smooth_group(-1)
	var sections := _intervals(z - half, z + half)
	for i in range(1, sections.size()):
		var a := sections[i - 1]
		var b := sections[i]
		_quad(stair, "WalkableRamp", [_plot_point(band, lo, y, a), _plot_point(band, hi, top, a),
			_plot_point(band, hi, top, b), _plot_point(band, lo, y, b)], 0, "", 0.19)
		for tread in 14:
			var t0 := float(tread) / 14.0
			var t1 := float(tread + 1) / 14.0
			var tread_y := lerpf(y, top, (t0 + t1) / 2.0)
			# Mesh only: collision follows the continuous slope under the stone steps.
			var points := PackedVector3Array()
			for h: float in [tread_y - 0.17, tread_y]:
				points.append_array([_plot_point(band, lerpf(lo, hi, t0), h, a), _plot_point(band, lerpf(lo, hi, t1), h, a),
					_plot_point(band, lerpf(lo, hi, t1), h, b), _plot_point(band, lerpf(lo, hi, t0), h, b)])
			_ring_faces(treads, points)
	treads.generate_normals()
	var step_mesh := MeshInstance3D.new()
	step_mesh.name = "StoneTreads"
	step_mesh.mesh = treads.commit()
	step_mesh.material_override = _materials.stone
	_add(stair, step_mesh)
	var foot := _plot_point(band, lo - 0.35 / width, y, z)
	var landing := _plot_point(band, hi + 0.42 / width, top, z)
	_marker(stair, "Foot", foot, "map_stair_end")
	_marker(stair, "Landing", landing, "map_stair_end")
	var house := String(parent.get_parent().name)
	if house in ["LanternHouse", "RopeHouse", "Dyeworks", "Netmakers"]:
		var label := house + String(parent.name)
		var toward_room := signf(split - z)
		var clear_z := z + toward_room * 0.91
		var aisle := Vector3(foot.x, y, clear_z)
		var room := _plot_point(band, 0.64 if offset_door else 0.48, y, split)
		room.z -= toward_room * 0.52
		_walk_link(label + "RoomToAisle", room, aisle)
		_walk_link(label + "AisleToStair", aisle, foot)
		_walk_link(label + "LandingApproach", landing, Vector3(landing.x, top, clear_z))
	var colour := tile if roof else "interior"
	_plot_box(parent, "DeckNorth", band, 0, 1, z0, z - half, top - 0.14, top, colour)
	_plot_box(parent, "DeckSouth", band, 0, 1, z + half, z1, top - 0.14, top, colour)
	_plot_box(parent, "DeckWest", band, 0, lo - 0.04 / width, z - half, z + half, top - 0.14, top, colour)
	_plot_box(parent, "DeckEast", band, hi, 1, z - half, z + half, top - 0.14, top, colour)


func _roof(parent: Node3D, band: int, z0: float, z1: float, y: float, style: String, tile: String,
		landing_side: float) -> void:
	if style == "flat":
		return
	# Keep the stair landings and the approach from the eaves board clear.
	z0 += 1.78
	z1 -= 1.78
	var z_mid := (z0 + z1) / 2
	var across := style == "gable" and (_edges(band, z_mid).y - _edges(band, z_mid).x) > 10.4
	var parts := [z0, z0 + 1.05, z_mid, z1 - 1.05, z1] if z1 - z0 > 2.5 else [z0, z_mid, z1]
	for j in range(1, parts.size()):
		var sections := _intervals(parts[j - 1], parts[j])
		for i in range(1, sections.size()):
			var a := sections[i - 1]
			var b := sections[i]
			for side in 2:
				var lo := float(side) * 0.5
				var hi := lo + 0.5
				var roof := []
				for p: Vector2 in [Vector2(lo, a), Vector2(hi, a), Vector2(hi, b), Vector2(lo, b)]:
					var f := p.x if style == "shed" else 1.0 - absf(p.x - 0.5) * 2
					if across:
						f = 1.0 - absf(p.y - z_mid) / (z_mid - z0)
					if style == "hip":
						f *= 0.38 + 0.62 * (1.0 - absf(p.y - z_mid) / (z_mid - z0))
					f *= clampf(minf(p.y - z0, z1 - p.y) / 1.05, 0.0, 1.0)
					var u := p.x
					if is_equal_approx(u, landing_side):
						var edges := _edges(band, p.y)
						u = lerpf(u, 0.5, minf(0.94, 2.8 / (edges.y - edges.x)))
					roof.append(_plot_point(band, u, y + 0.017 + f * (0.47 if style == "shed" else 0.62), p.y))
				_quad(parent, "TileRoof", [roof[0], roof[1], roof[2]], y - 0.014, tile)
				_quad(parent, "TileRoof", [roof[0], roof[2], roof[3]], y - 0.014, tile)


# Positive depth is outside the wall, regardless of which street the house fronts.
func _facade_point(band: int, side: float, z: float, depth: float, y: float) -> Vector3:
	return _plot_point(band, side, y, z) + Vector3.RIGHT * (2.0 * side - 1.0) * depth


func _facade_box(parent: Node3D, label: String, band: int, side: float, z: float, half: float,
		inner: float, outer: float, bottom: float, top: float, colour: String) -> void:
	var sections := _intervals(z - half, z + half)
	for i in range(1, sections.size()):
		var a := sections[i - 1]
		var b := sections[i]
		_quad(parent, label, [_facade_point(band, side, a, inner, top), _facade_point(band, side, a, outer, top),
			_facade_point(band, side, b, outer, top), _facade_point(band, side, b, inner, top)], bottom, colour)


# Follow facade bends so the ramp meets the sill without a lip, even at a street knot.
func _window_ledge(parent: Node3D, band: int, side: float, z: float, y: float, sill: float, outer: float) -> void:
	var sections := _intervals(z - WINDOW_HALF, z + WINDOW_HALF)
	for i in range(1, sections.size()):
		var a := sections[i - 1]
		var b := sections[i]
		_quad(parent, "WindowApproach", [
			_facade_point(band, side, a, -1.20, y + 0.006),
			_facade_point(band, side, a, -0.55, sill),
			_facade_point(band, side, b, -0.55, sill),
			_facade_point(band, side, b, -1.20, y + 0.006)], y - 0.07, "wood")
	_facade_box(parent, "WindowLedge", band, side, z, WINDOW_HALF, -0.55, outer, y, sill, "ashlar")


func _facade_route(parent: Node3D, band: int, side: float, z: float, direction: float, y: float, roof: float) -> void:
	var house := String(parent.get_parent().name)
	# The sharper bends need a little more clearance from the wall and shutters.
	var ledge_depth := 0.95 if house in ["Chapel", "Coopers", "LanternHouse"] else 0.88
	var planter_z := z + direction * 1.84
	var plank_z := z + direction * 3.68
	var sill := y + 0.24
	var planter := y + 1.07
	var plank := maxf(roof - 0.74, y + 1.94)
	_window_ledge(parent, band, side, z, y, sill, 0.82)
	_facade_box(parent, "FlowerBox", band, side, planter_z, 0.64, 0.0, ledge_depth, planter - 0.25, planter, "tile_sienna")
	_facade_box(parent, "ClosedShutter", band, side, planter_z, 0.42, -0.02, 0.09, planter + 0.09, planter + 0.86, "shutter")
	for offset: float in [-0.40, 0.0, 0.40]:
		var leaves := _facade_point(band, side, planter_z + offset, 0.15, planter + 0.09)
		_visual(parent, "Leaves", leaves, Vector3(0.18, 0.18, 0.22), "garden")
		_visual(parent, "Blossom", leaves + Vector3.UP * 0.12, Vector3(0.13, 0.09, 0.13), "rose")
	_facade_box(parent, "EavesPlank", band, side, plank_z, 0.70, 0.0, ledge_depth, plank - 0.12, plank, "wood")
	_facade_box(parent, "ClosedShutter", band, side, plank_z, 0.38, -0.02, 0.09, plank - 0.94, plank - 0.23, "shutter")
	var window := _facade_point(band, side, z, 0.52, sill)
	var flowers := _facade_point(band, side, planter_z, ledge_depth - 0.30, planter)
	var board := _facade_point(band, side, plank_z, ledge_depth - 0.31, plank)
	var landing := _facade_point(band, side, plank_z, -0.55, roof)
	_walk_link(house + "OpenWindow", _facade_point(band, side, z, -1.22, y), window)
	_jump_link(house + "FlowerBox", window, window, flowers, "roof_parkour")
	_jump_link(house + "EavesPlank", flowers, flowers, board, "roof_parkour")
	_jump_link(house + "RoofLanding", board, board, landing, "roof_landing")


# WHY: only the block stands in the lane. Everything above it clears the mage's head, so streets stay open.
func _street_block(parent: Node3D, label: String, band: int, side: float, z: float, away: float, lane: int, top: float, target: Vector3) -> Vector3:
	var house := String(parent.get_parent().name)
	var ground := _street_at(lane, z).y
	_facade_box(parent, "MountingBlock", band, side, z, 0.6, 0.0, STREET_LEDGE, ground - 0.05, top, "ashlar")
	var point := _facade_point(band, side, z, STREET_FOOTING, top)
	# WHY: a short run along the wall clears the block without pressing into a wall that would trigger a mantle.
	var foot_z := z + away * BLOCK_RUN
	var foot := _facade_point(band, side, foot_z, 0.55, _street_at(lane, foot_z).y)
	_jump_link(house + label + "Block", foot, foot, point, "roof_block")
	_jump_link(house + label + "Ledge", point, point, target, "roof_parkour")
	return point


# One-storey fronts keep their door, so the block and plank sit wherever the lane is widest beside it.
func _street_roof_route(parent: Node3D, band: int, side: float, lane: int, y: float, roof: float,
		z0: float, z1: float, door_z: float) -> void:
	var house := String(parent.get_parent().name)
	var clear_of_door := DOOR / 2 + 0.75
	var best_z := INF
	var best_dir := 1.0
	var widest := 0.0
	for direction: float in [1.0, -1.0]:
		var z := z0 + 0.85
		while z <= z1 - 0.85:
			var plank_z := z + direction * HOP
			var fits := plank_z >= z0 + 0.8 and plank_z <= z1 - 0.8 and absf(z - door_z) > clear_of_door and absf(plank_z - door_z) > clear_of_door
			var width: float = _street_at(lane, z).z
			var ground: float = _street_at(lane, z).y
			var foot_ground: float = _street_at(lane, z - direction * BLOCK_RUN).y
			if fits and width > widest and _block_top(y, roof, _highest_street(lane, plank_z), ground) - foot_ground <= MAX_STREET_HOP:
				best_z = z
				best_dir = direction
				widest = width
			z += 0.2
	assert(widest > 0.0, house + " has no room for a street roof route")
	var plank_z := best_z + best_dir * HOP
	var plank := _plank_top(y, roof, _highest_street(lane, plank_z))
	var top := _block_top(y, roof, _highest_street(lane, plank_z), _street_at(lane, best_z).y)
	_facade_box(parent, "EavesPlank", band, side, plank_z, 0.70, 0.0, 0.88, plank - 0.12, plank, "wood")
	var board := _facade_point(band, side, plank_z, 0.57, plank)
	_street_block(parent, "Street", band, side, best_z, -best_dir, lane, top, board)
	_jump_link(house + "RoofLanding", board, board, _facade_point(band, side, plank_z, -0.55, roof), "roof_landing")


# A plank must clear heads at its uphill end, not just its middle.
func _highest_street(lane: int, z: float) -> float:
	return maxf(_street_at(lane, z - 0.75).y, _street_at(lane, z + 0.75).y)


func _plank_top(y: float, roof: float, ground: float) -> float:
	return maxf(roof - MAX_CLIMB_HOP, maxf(y, ground) + HEADROOM)


func _block_top(y: float, roof: float, plank_ground: float, ground: float) -> float:
	return maxf(_plank_top(y, roof, plank_ground) - MAX_CLIMB_HOP, ground + 0.5)


# Sealed houses: a block and one overhead ledge climb from the rear lane to a top-floor window.
func _rear_window_climb(parent: Node3D, band: int, side: float, z: float, direction: float, y: float, lane: int) -> void:
	var house := String(parent.get_parent().name)
	var sill := y + 0.24
	_window_ledge(parent, band, side, z, y, sill, 0.82)
	var window := _facade_point(band, side, z, 0.52, sill)
	_walk_link(house + "RearWindowIn", window, _facade_point(band, side, z, -1.22, y))
	var ledge_z := z + direction * HOP
	var ledge := maxf(sill - MAX_CLIMB_HOP, _highest_street(lane, ledge_z) + HEADROOM)
	_facade_box(parent, "ClimbLedge", band, side, ledge_z, 0.62, 0.0, 0.82, ledge - 0.18, ledge, "wood")
	var point := _facade_point(band, side, ledge_z, 0.52, ledge)
	_jump_link(house + "RearWindow", point, point, window, "roof_parkour")
	var block_z := z + direction * HOP * 2.0
	_street_block(parent, "Rear", band, side, block_z, direction, lane, maxf(ledge - MAX_CLIMB_HOP, _street_at(lane, block_z).y + 0.5), point)


func _garden(parent: Node3D, band: int, z0: float, z1: float, y: float, wall: float, side: float, at: float) -> void:
	_plot_box(parent, "CourtFoundation", band, 0, 1, z0, z1, SHELL_BOTTOM, y, "deep_stone")
	_plot_box(parent, "CourtFloor", band, 0, 1, z0, z1, y - 0.025, y + 0.002, "square")
	_plot_box(parent, "GardenGround", band, 0.18 if side else 0.39, 0.61 if side else 0.82,
		z0 + 0.64, z1 - 0.64, y, y + 0.022, "garden")
	var lane := band if side else band - 1
	_threshold(parent, band, lane, side, at, y, 1.8)
	var road := _street_at(lane, at)
	var landing := _plot_point(band, 0.89 if side else 0.11, y, at)
	_walk_link(String(parent.name) + "Gate", Vector3(road.x, road.y, at), landing)
	for k in 2:
		var u := float(k)
		if u != side:
			var neighbour := band if k == 1 else band - 1
			var wall_height := maxf(0.72, _street_at(clampi(neighbour, 0, 2), at).y - y + 0.72)
			_plot_box(parent, "GardenWall", band, 1.0 - wall if k else 0.0, 1.0 if k else wall,
				z0, z1, y, y + wall_height, "stone")
	if parent.name in [&"CisternYard", &"OliveYard", &"CuttersYard"]:
		parent.add_to_group("map_nook", true)


func _cut(spec: Array) -> void:
	var band := int(spec[1])
	var z := float(spec[2])
	var west := _street_at(band - 1, z)
	var east := _street_at(band, z)
	var uphill_east := east.y > west.y
	var low := west if uphill_east else east
	var high := east if uphill_east else west
	var direction := 1.0 if uphill_east else -1.0
	var width := float(spec[3]) - 0.34
	var run := float(spec[4])
	var x0 := high.x - direction * (high.z / 2 + 0.42 + run)
	var x1 := x0 + direction * run
	var stair := _container(_plan, spec[0], Vector3(x0, low.y, z), "map_rock_cut")
	stair.rotation_degrees.y = 90.0 * direction
	_stairs(stair, "RockTreads", Vector3.ZERO, width, run, high.y - low.y)
	# Landings let the cut make its last turn inside each street's narrow footprint.
	_cut_landing(stair, "FootShelf", z, width, low, x0, low.y, direction, true)
	_cut_landing(stair, "HeadShelf", z, width, high, x1, high.y, direction, false)
	var cliff := _container(stair, "CarvedRock", Vector3.ZERO)
	for i in 5:
		var pos := (float(i) + 0.5) * run / 5.0
		var rise := (high.y - low.y) * pos / run
		_box(cliff, "RockCourse", Vector3(-width / 2 - 0.09, rise * 0.5 - 0.2, pos),
			Vector3(0.19, rise + 0.5, run / 5.0), "cliff" if i % 2 else "rock_light")


func _cut_landing(stair: Node3D, label: String, z: float, width: float, road: Vector3,
		end: float, y: float, direction: float, foot: bool) -> void:
	var x := road.x + direction * road.z * (0.19 if foot else -0.19)
	var pts := [Vector3(x, y + 0.005, z - width / 2), Vector3(end, y, z - width / 2),
		Vector3(end, y, z + width / 2), Vector3(x, y + 0.005, z + width / 2)]
	for i in pts.size():
		pts[i] = stair.to_local(pts[i])
	_quad(stair, label, pts, BEDROCK - stair.position.y, "stone")
	_walk_link(label + String(stair.name), Vector3(x, y, z), Vector3(end - direction * (0.42 if foot else -0.42), y, z))


func _walk_link(label: String, start: Vector3, end: Vector3) -> void:
	var marker := _marker(_town, label, start, "map_walk_link")
	marker.set_meta("landing", end)


func _bookends() -> void:
	var apron := _container(_plan, "FishMarket", Vector3.ZERO, "map_landmark")
	# Share the quay's boundary without laying two surfaces over the same stretch of paving.
	_deck(apron, "MarketApron", -30, 30, 32, _layout.waterfront.quay[2], 0, "square")
	_box(apron, "StallLeg", Vector3(0.1, 0.92, 34.7), Vector3(0.16, 1.84, 0.16), "wood")
	_box(apron, "StallLeg", Vector3(2.7, 0.92, 34.7), Vector3(0.16, 1.84, 0.16), "wood")
	_box(apron, "StallAwning", Vector3(1.4, 1.95, 34.7), Vector3(3.06, 0.18, 1.33), "indigo")
	var chapel := _container(_plan, "ChapelSquare", Vector3.ZERO, "map_landmark")
	_quad(chapel, "ChapelForecourt", [Vector3(-24, 8.2, -53), Vector3(25, 8.2, -53),
		Vector3(17, 8.2, -61.6), Vector3(-15, 8.2, -60.2)], BEDROCK, "square")
	_ridge_spur(chapel, Vector3(-11, 7.1, -61.9), Vector3(9, 7.6, 5.8))
	_ridge_spur(chapel, Vector3(0, 7.5, -63.1), Vector3(16, 10.1, 7.0))
	_ridge_spur(chapel, Vector3(13, 7.2, -62.0), Vector3(11, 8.2, 5.7))
	var cistern := _container(_plan, "CisternSquare", Vector3.ZERO, "map_landmark")
	var rim := _plot_point(1, 0.41, float(_houses.CisternYard.base), -0.10)
	_round_platform(cistern, "Cistern", rim, 0.90, 0.68, "stone")
	_round_platform(cistern, "Coping", rim + Vector3.UP * 0.68, 1.02, 0.12, "ashlar")


func _round_platform(parent: Node3D, label: String, p: Vector3, radius: float, height: float, colour: String) -> void:
	var outline: Array[Vector3] = []
	for i in 12:
		var angle := TAU * i / 12.0
		outline.append(p + Vector3(radius * cos(angle), height, radius * sin(angle)))
	_quad(parent, label, outline, p.y, colour)


func _ridge_spur(parent: Node3D, p: Vector3, size: Vector3) -> void:
	var ring: Array[Vector3] = []
	for i in 7:
		var angle := TAU * i / 7.0
		ring.append(p + Vector3(cos(angle) * size.x * 0.64, 0, sin(angle) * size.z * 0.6))
	var tip := p + Vector3(-size.x * 0.13, size.y, -0.7)
	# Steep faces bound the upper edge, with no flat plateau outside the chapel court.
	for i in ring.size():
		_quad(parent, "RoccaSpur", [ring[i], ring[(i + 1) % ring.size()], tip], BEDROCK,
			"rock_light" if i in [0, 3, 4] else "cliff")



func _rock(parent: Node3D, p: Vector3, size: Vector3, yaw: float) -> void:
	var rock := _container(parent, "Limestone", p)
	rock.rotation.y = yaw
	var ring := PackedVector3Array()
	for h in 2:
		for i in 7:
			var angle := TAU * i / 7.0
			var taper := (0.93 if h == 0 else 0.57) + 0.10 * sin(float(i) * 8.0)
			ring.append(Vector3(cos(angle) * size.x * taper / 2, 0.0 if h == 0 else size.y * (0.86 + 0.11 * cos(angle)),
				sin(angle) * size.z * taper / 2))
	_solid(rock, "Rock", ring, "rock_light" if yaw > 0 else "cliff")


func _bluff(parent: Node3D, band: int, z0: float, z1: float, y: float, seed: int) -> void:
	var side := -1.0 if band == 0 else 1.0
	var u := 0.0 if band == 0 else 1.0
	var intervals := _intervals(z0, z1)
	for i in range(1, intervals.size()):
		var a := _plot_point(band, u, y - 0.045, intervals[i - 1])
		var b := _plot_point(band, u, y - 0.045, intervals[i])
		var width := minf(4.3, (y - BEDROCK) * 0.62)
		var c := Vector3(a.x + side * width * (0.79 + 0.13 * sin(a.z)), BEDROCK, a.z)
		var d := Vector3(b.x + side * width * (0.81 + 0.13 * sin(b.z)), BEDROCK, b.z)
		var middle := a.lerp(d, 0.46)
		middle.x += side * width * 0.075
		_quad(parent, "LimestoneFace", [a, b, middle], BEDROCK - 0.2, "rock_light" if (seed + i) % 3 else "cliff")
		_quad(parent, "LimestoneFace", [b, d, middle], BEDROCK - 0.2, "cliff")
		_quad(parent, "LimestoneFace", [a, middle, c], BEDROCK - 0.2, "deep_stone")
		_quad(parent, "LimestoneFace", [middle, d, c], BEDROCK - 0.2, "rock_light")


func _roof_height(house: Dictionary) -> float:
	return house.base + house.spacing * house.spec[3]


# WHY: these two lanes bend too sharply for a street block, so their roofs are reached by jumping from next door.
func _neighbour_roof_link(house: String, neighbour: String) -> void:
	var lot: Dictionary = _houses[house]
	var edge := float(lot.spec[2])
	# WHY: a standing hop from the edge. A running jump down carries the mage clean across a one-storey roof.
	var start := _plot_point(lot.band, 0.5, _roof_height(_houses[neighbour]), edge + 0.45)
	var takeoff := start
	var land := Vector3(start.x, _roof_height(lot), edge - 0.6)
	_jump_link(house + "RoofLanding", start, takeoff, land, "roof_landing")


func _loft_link(label: String, neighbour: String, z: float) -> void:
	var loft: Dictionary = _houses[label]
	var approach: Dictionary = _houses[neighbour]
	var face: Vector3 = _plot_point(loft.band, 0.0, loft.base + loft.spacing, z)
	var bank: Vector3 = _plot_point(approach.band, 1.0, approach.base + approach.spacing, z)
	var start := bank - Vector3.RIGHT * 1.57
	var takeoff := bank - Vector3.RIGHT * 0.15
	var land := face + Vector3.RIGHT * 0.53
	_jump_link(label + "Window", start, takeoff, land, "window_jump")


func _jump_link(label: String, start: Vector3, takeoff: Vector3, end: Vector3, kind: String) -> void:
	var marker := _marker(_town, label, start, "map_traversal")
	marker.set_meta("takeoff", takeoff)
	marker.set_meta("landing", end)
	marker.set_meta("kind", kind)


func _spawn_points() -> void:
	# On lane centrelines and on the apron; entry and prop locations move independently.
	var groups := {
		"villager_spawn": [[-20, 34], [-13, 34], [-6.4, 34.5], [-2, 33.5], [9, 34], [17, 34],
			[0, 12], [1, 8], [2, 13], [1, -23], [0, -36], [2, -42]],
		"mage_spawn": [[-5.2, 34.9], [1, -49], [3.5, 34.9], [2, -48]],
		"chicken_spawn": [[-22, 34], [-13.5, 34], [-5, 34], [10, 34], [23, 34],
			[0, 5], [1, 11], [1, -4], [2, 9], [0, -25], [1, -23], [2, -16], [0, -46], [2, -45]],
		"item_spawn": [[-23, 34], [-16, 34], [-8, 34], [-2, 34], [22, 34],
			[0, 15], [1, 4], [2, 7], [0, -24], [1, -27], [2, -21], [1, -48]],
	}
	for group: String in groups:
		for i in groups[group].size():
			var entry: Array = groups[group][i]
			var z := float(entry[1])
			var road := _street_at(int(entry[0]), z) if z <= 32 else Vector3(entry[0], 0, 0)
			_marker(_town, "%s_%02d" % [group, i], Vector3(road.x, road.y + 0.08, z), group)
	var hide_scene := load("res://game/interact/hide_spot.tscn") as PackedScene
	for label: String in ["CuttersYard", "LimeKiln", "IndigoCourt", "DyersGarden", "CisternYard", "OliveYard",
			"JuniperCourt", "CandleCourt", "LaurelYard", "SailYard", "Fishers", "Menders", "Porters", "KilnAnnex", "Netmakers", "Sailmakers"]:
		var lot: Dictionary = _houses[label]
		var spot := hide_scene.instantiate() as Node3D
		spot.name = "Hide" + label
		var spec: Array = lot.spec
		var courtyard: bool = spec[3] == 0
		var z := lerpf(spec[1], spec[2], 0.76 if label == "Porters" else 0.80)
		var u := 0.57 if courtyard else (0.32 if lot.east else 0.68)
		if label == "Porters":
			u = 0.52
		spot.position = _plot_point(lot.band, u,
			lot.base + (0.022 if courtyard else 0.0), z)
		_add(_region, spot)


func _deck(parent: Node3D, label: String, x0: float, x1: float, z0: float, z1: float, y: float, colour: String) -> void:
	_box(parent, label, Vector3((x0 + x1) / 2, y - 0.08, (z0 + z1) / 2), Vector3(x1 - x0, 0.16, z1 - z0), colour)
