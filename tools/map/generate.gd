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
	var size := Vector2(_layout.footprint[0], _layout.footprint[1])
	_box(_region, "TownFoundation", Vector3(0, -0.6, -2), Vector3(size.x, 1.2, size.y - 4), "paving")
	# WHY: sea is visual only; a low quay barrier contains actors without an invisible wall.
	var half := size / 2
	_visual(_town, "Sea", Vector3(0, -1.4, half.y + 6), Vector3(size.x + 20, 0.2, 24), "sea")
	_box(_region, "NorthBoundary", Vector3(0, 2, -half.y + 0.5), Vector3(size.x, 4, 1), "stone")
	for side in [-1, 1]:
		_box(_region, "Boundary%d" % side, Vector3(side * (half.x - 0.5), 2, -2), Vector3(1, 4, size.y - 6), "stone")
	# The foundation itself is the quay; a second flush slab caused coplanar flicker.
	_box(_region, "QuayWallWest", Vector3(-9, 0.65, 47.5), Vector3(86, 1.3, 1), "stone")
	_box(_region, "QuayWallEast", Vector3(47, 0.65, 47.5), Vector3(10, 1.3, 1), "stone")
	for district: Dictionary in _layout.districts:
		_district(district)
	for landmark: Dictionary in _layout.landmarks:
		var s := _v(landmark.size)
		var node := _box(_region, landmark.name, _v(landmark.position) + Vector3(0, s.y / 2, 0), s, landmark.colour)
		node.add_to_group("map_landmark", true)
		if landmark.name == "Mole":
			_box(_region, "MoleWestRail", Vector3(34.2, 0.7, 49), Vector3(0.4, 1.4, 6), "stone")
			_box(_region, "MoleEastRail", Vector3(41.8, 0.7, 49), Vector3(0.4, 1.4, 6), "stone")
			_box(_region, "MoleEndRail", Vector3(38, 0.7, 51.8), Vector3(7.2, 1.4, 0.4), "stone")
	for nook: Dictionary in _layout.nooks:
		var p := _v(nook.position)
		var node := Node3D.new()
		node.name = nook.name
		node.position = p
		node.add_to_group("map_nook", true)
		_add(_region, node)
		_box(node, "Back", Vector3(-nook.opening * 1.5, 1.2, 0), Vector3(0.4, 2.4, 3.6), "stone")
		_box(node, "SideN", Vector3(0, 1.2, -2), Vector3(3.4, 2.4, 0.4), "stone")
		_box(node, "SideS", Vector3(0, 1.2, 2), Vector3(3.4, 2.4, 0.4), "stone")
	for p: Array in _layout.mantle_ledges:
		var ledge := _box(_region, "MantleLedge%d" % _region.get_child_count(), _v(p) + Vector3(0, 0.8, 0), Vector3(2, 1.6, 2), "stone")
		ledge.add_to_group("map_mantle_ledge", true)
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


func _district(data: Dictionary) -> void:
	var district := Node3D.new()
	district.name = data.name
	district.add_to_group("map_district", true)
	_add(_region, district)
	var houses: Dictionary = {}
	for row in data.rows.size():
		for col in data.columns.size():
			if col == int(data.plaza_cell[0]) and row == int(data.plaza_cell[1]):
				continue
			var house := _house(district, "House%d_%d" % [col, row], Vector3(data.columns[col], 0, data.rows[row]), float(data.roof_heights[row]), col + row * 2)
			houses[Vector2i(col, row)] = house
	# Every north/south neighbour has a sloping plank. Upper rows also bridge east/west;
	# the lowest row keeps 3 m running jumps with alternate access through the roof network.
	for cell: Vector2i in houses:
		var house: Node3D = houses[cell]
		for dir: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT]:
			if not houses.has(cell + dir):
				continue
			var other: Node3D = houses[cell + dir]
			var top := float(house.get_meta("roof_height"))
			var other_top := float(other.get_meta("roof_height"))
			var mid := (house.position + other.position) / 2 + Vector3(0, (top + other_top) / 2 + 0.06, 0)
			if dir == Vector2i.DOWN or cell.y < data.rows.size() - 1:
				var span := Vector3(1.8, 0.2, sqrt(36.0 + pow(other_top - top, 2))) if dir == Vector2i.DOWN else Vector3(7, 0.2, 1.4)
				# Main roof starts east of the stairwell; the plank meets solid roof on both ends.
				if dir == Vector2i.DOWN:
					mid.x += 2
				else:
					mid.x += 1
					mid.z += float(_layout.house.depth) / 2 - 0.7
				var plank := _box(district, "Plank%d_%d_%d" % [cell.x, cell.y, dir.x], mid, span, "wood")
				if dir == Vector2i.DOWN:
					plank.rotation.x = -atan2(other_top - top, 6.0)
				plank.add_to_group("map_roof_plank", true)
			else:
				var gap := Marker3D.new()
				gap.name = "JumpGap%d_%d" % [cell.x, cell.y]
				mid.z += float(_layout.house.depth) / 2 - 0.7
				gap.position = mid - Vector3(0, 0.16, 0)
				gap.set_meta("gap_metres", float(data.columns[cell.x + 1] - data.columns[cell.x]) - float(_layout.house.width))
				gap.add_to_group("map_roof_gap", true)
				_add(district, gap)


func _house(parent: Node3D, label: String, pos: Vector3, top: float, variant: int) -> Node3D:
	var h: Dictionary = _layout.house
	var w := float(h.width)
	var d := float(h.depth)
	var colour: String = ["cream", "peach", "ochre"][variant % 3]
	var wall_top := top - 0.2
	var door := float(h.door_width)
	var door_height := float(h.door_height)
	var house := Node3D.new()
	house.name = label
	house.position = pos
	house.set_meta("roof_height", top)
	house.add_to_group("map_house", true)
	_add(parent, house)
	_box(house, "WestWall", Vector3(-w / 2 + 0.2, wall_top / 2, 0), Vector3(0.4, wall_top, d - 0.8), colour)
	_box(house, "EastWall", Vector3(w / 2 - 0.2, wall_top / 2, 0), Vector3(0.4, wall_top, d - 0.8), colour)
	for side in [-1, 1]:
		var z: float = side * (d / 2 - 0.2)
		for lr in [-1, 1]:
			_box(house, "DoorWing%d_%d" % [side, lr], Vector3(lr * (w + door) / 4, wall_top / 2, z), Vector3((w - door) / 2, wall_top, 0.4), colour)
		_box(house, "Lintel%d" % side, Vector3(0, (wall_top + door_height) / 2, z), Vector3(door, wall_top - door_height, 0.4), colour)
		var exit_marker := Marker3D.new()
		exit_marker.name = "Door%d" % side
		exit_marker.position = Vector3(0, 0.1, side * (d / 2 + 1))
		exit_marker.add_to_group("map_house_exit", true)
		_add(house, exit_marker)
	# An open stairwell avoids the ceiling cutting off the last few stair treads.
	var stair_x := -w / 2 + 0.4 + float(h.stair_width) / 2
	var roof_left := -w / 2 + 0.4 + float(h.stair_width)
	_box(house, "Roof", Vector3((roof_left + w / 2) / 2, top - 0.1, 0), Vector3(w / 2 - roof_left, 0.2, d), "roof")
	_box(house, "StairLanding", Vector3(stair_x, top - 0.1, d / 2 - 1.3), Vector3(h.stair_width, 0.2, 2.6), "roof")
	var steps := roundi(top / float(h.stair_rise))
	# End treads at the landing edge instead of drawing through its top.
	var run := (d - 3.2) / steps
	for step in steps:
		var rise := (step + 1) * float(h.stair_rise)
		_visual(house, "Stair%02d" % step, Vector3(stair_x, rise / 2, -d / 2 + 0.6 + (step + 0.5) * run), Vector3(h.stair_width, rise, run), "stone")
	# WHY: a smooth collision wedge prevents CharacterBody3D snagging on every riser.
	var ramp := StaticBody3D.new()
	ramp.name = "StairRamp"
	ramp.collision_layer = 1
	ramp.collision_mask = 0
	ramp.add_to_group("map_stair_ramp", true)
	_add(house, ramp)
	var wedge := ConvexPolygonShape3D.new()
	var x0 := stair_x - float(h.stair_width) / 2
	var x1 := stair_x + float(h.stair_width) / 2
	var z0 := -d / 2 + 0.6
	var z1 := z0 + steps * run
	wedge.points = PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0),
		Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x0, top, z1), Vector3(x1, top, z1)])
	var ramp_collision := CollisionShape3D.new()
	ramp_collision.name = "Collision"
	ramp_collision.shape = wedge
	_add(ramp, ramp_collision)
	var route := Marker3D.new()
	route.name = "RoofAccess"
	route.position = Vector3(stair_x, top, -d / 2 + 0.6 + steps * run + 0.3)
	route.add_to_group("map_roof_access", true)
	_add(house, route)
	# Low pitched roof sections preserve a walkable terrace around the stair and bridges.
	if variant % 3 != 0:
		for side in [-1, 1]:
			var cap := _box(house, "RoofPitch%d" % side, Vector3(2.2 + side, top + 0.55, 0), Vector3(2.2, 0.16, 3.6), "roof")
			cap.rotation.z = -side * deg_to_rad(25)
	for side in [-1, 1]:
		_visual(house, "Shutter%d" % side, Vector3(3, 1.8, side * (d / 2 + 0.04)), Vector3(1.1, 1.1, 0.08), "wood")
		if variant % 2 == 0:
			_visual(house, "Banner%d" % side, Vector3(-1.8, wall_top - 0.8, side * (d / 2 + 0.06)), Vector3(0.6, 1.2, 0.08), "purple")
	return house


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
