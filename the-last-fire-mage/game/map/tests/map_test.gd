extends Node3D
## Headless generated-town geometry, placement and navigation regression checks. Owner: S05.
## Public API: tools/tests/map_test.sh; exits nonzero on a broken map contract.
## NET: standalone test, no network session or gameplay managers required.

var _fails := 0
var _town: Node3D
var _space: PhysicsDirectSpaceState3D
var _nav_map: RID
var _diagnostics := 0


func _ready() -> void:
	get_tree().create_timer(60).timeout.connect(func() -> void: get_tree().quit(1))
	_nav_map = get_world_3d().navigation_map
	# WHY: synchronous setup avoids querying an empty initial map iteration in headless tests.
	NavigationServer3D.map_set_use_async_iterations(_nav_map, false)
	_town = load("res://game/map/town.tscn").instantiate()
	NavigationServer3D.region_set_use_async_iterations((_town.get_node("ChickenNavigation") as NavigationRegion3D).get_rid(), false)
	add_child(_town)
	_run.call_deferred()


func _run() -> void:
	for i in 5:
		await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	_nav_map = get_world_3d().navigation_map
	NavigationServer3D.map_force_update(_nav_map)
	for group: String in ["villager_spawn", "mage_spawn", "chicken_spawn", "item_spawn", "hide_spot"]:
		var minimum: int = {"villager_spawn": 8, "mage_spawn": 2, "chicken_spawn": 10, "item_spawn": 10, "hide_spot": 15}[group]
		_check(get_tree().get_nodes_in_group(group).size() >= minimum, "marker count %s" % group)
	_check(get_tree().get_nodes_in_group("mage_spawn").size() == 2, "exactly two mage starts")
	_check(_town.get_meta("footprint") == Vector2(104, 104), "compact 104 m footprint")
	_check(get_tree().get_nodes_in_group("map_district").size() == 4, "four districts")
	_check(get_tree().get_nodes_in_group("map_house").size() == 24, "24 individually placed buildings across four districts")
	var floors: Dictionary = {}
	var orientations: Dictionary = {}
	var setbacks: Dictionary = {}
	for building: Node3D in get_tree().get_nodes_in_group("map_house"):
		floors[int(building.get_meta("storeys"))] = true
		orientations[roundi(building.rotation_degrees.y)] = true
		setbacks[snappedf(building.position.z, 0.1)] = true
	_check(floors.has(1) and floors.has(2) and floors.has(3), "one-, two- and three-storey buildings")
	_check(orientations.size() >= 3 and setbacks.size() >= 16, "varied orientations and authored setbacks")
	_check(get_tree().get_nodes_in_group("map_nook").size() >= 4, "dead-end hiding nooks")
	_check(get_tree().get_nodes_in_group("map_landmark").size() >= 3, "landmark placeholders")
	var all_nodes := _town.find_children("*", "", true, false)
	var static_ok := true
	var lighting_ok := true
	for node: Node in all_nodes:
		if node is StaticBody3D:
			static_ok = static_ok and node.collision_layer == 1
		lighting_ok = lighting_ok and not (node is Light3D or node is WorldEnvironment)
	_check(static_ok, "static geometry uses world layer 1")
	_check(lighting_ok, "lighting belongs to main")
	var region := _town.get_node("ChickenNavigation") as NavigationRegion3D
	_check(region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0, "saved chicken navmesh has polygons")
	_check(region.navigation_mesh.cell_size == NavigationServer3D.map_get_cell_size(_nav_map), "nav voxel size matches main's default map")
	var placements_ok := true
	var connected_ok := true
	for group: String in ["villager_spawn", "mage_spawn", "chicken_spawn", "item_spawn"]:
		for marker: Node3D in get_tree().get_nodes_in_group(group):
			var p := marker.global_position
			var clear := _clear(p + Vector3(0, 0.75, 0), 1.4) and not _ray(p, p - Vector3(0, 2, 0)).is_empty()
			if not clear:
				print("[Map] Blocked start ", marker.name, " at ", p)
			placements_ok = placements_ok and clear
			connected_ok = connected_ok and _reachable(Vector3(0, 0, 0), p)
	_check(placements_ok, "all starts have ground and mage clearance")
	_check(connected_ok, "all starts connect to central plaza on navmesh")
	var hide_ok := true
	for spot: Node3D in get_tree().get_nodes_in_group("hide_spot"):
		hide_ok = hide_ok and spot.scene_file_path == "res://game/interact/hide_spot.tscn"
		hide_ok = hide_ok and _reachable(Vector3.ZERO, spot.global_position + Vector3(0, 0, 1.5))
	_check(hide_ok, "S10 hide instances are reachable for searching")
	var doors_ok := true
	for door: Node3D in get_tree().get_nodes_in_group("map_house_exit"):
		var house := door.get_parent() as Node3D
		var inside := house.global_position + Vector3(0, 1, 0)
		doors_ok = doors_ok and _ray(inside, door.global_position + Vector3(0, 0.9, 0)).is_empty()
		if house.position.y == 0:
			doors_ok = doors_ok and _reachable(house.global_position, door.global_position)
	_check(doors_ok, "all storey doors are open and ground entrances are navigable")
	var stairs_ok := true
	for ramp: Node3D in get_tree().get_nodes_in_group("map_stair_ramp"):
		var house := ramp.get_parent() as Node3D
		var wedge: ConvexPolygonShape3D = ramp.get_node("Collision").shape
		var points := wedge.points
		var start := (points[0] + points[1]) / 2
		var end := (points[4] + points[5]) / 2
		for step in 20:
			var feet := house.to_global(start.lerp(end, (step + 0.5) / 20))
			var floor_hit := _ray(feet + Vector3(0, 0.25, 0), feet - Vector3(0, 0.25, 0))
			stairs_ok = stairs_ok and not floor_hit.is_empty()
			if not floor_hit.is_empty():
				stairs_ok = stairs_ok and _clear(floor_hit.position + Vector3(0, 0.8, 0), 1.4)
	_check(stairs_ok, "1.4 m mage clears every roof staircase")
	var entries: Dictionary = {}
	var gaps_ok := true
	for gap: Node3D in get_tree().get_nodes_in_group("map_roof_gap"):
		var metres: float = gap.get_meta("gap_metres")
		var takeoff: Vector3 = gap.get_meta("takeoff")
		var landing: Vector3 = gap.get_meta("landing")
		var target := gap.get_parent().get_node(NodePath(gap.get_meta("target"))) as Node3D
		entries[target] = landing
		gaps_ok = gaps_ok and metres > 0 and metres <= 3.0
		gaps_ok = gaps_ok and _reachable(Vector3.ZERO, takeoff)
		gaps_ok = gaps_ok and _ray(gap.global_position, gap.global_position - Vector3(0, 1, 0)).is_empty()
		for p: Vector3 in [takeoff, landing]:
			gaps_ok = gaps_ok and not _ray(p + Vector3.UP, p - Vector3.UP).is_empty()
		_check(not target.get_node("Storey0").has_node("StairRamp"), "parkour building has no stairs from its ground room")
		_check(not _reachable_silent(Vector3.ZERO, landing), "upper entrance requires crossing the jump")
		await _jump_gap(takeoff, landing)
	_check(gaps_ok and entries.size() == 4, "four reachable neighbour-roof jumps with solid landings")
	var roofs_ok := true
	for access: Node3D in get_tree().get_nodes_in_group("map_roof_access"):
		var room := access.get_parent() as Node3D
		var building := room.get_parent() as Node3D
		var start: Vector3 = entries[building] if room.get_meta("parkour_only") else Vector3.ZERO
		roofs_ok = _reachable(start, access.global_position) and roofs_ok
	_check(roofs_ok, "every roof reachable by stairs after its street or parkour entrance")
	var ledges_ok := true
	for ledge: StaticBody3D in get_tree().get_nodes_in_group("map_mantle_ledge"):
		var shape: BoxShape3D = ledge.get_node("Collision").shape
		ledges_ok = ledges_ok and shape.size.y <= 2
	_check(ledges_ok, "mantle ledges at most 2 m")
	_check_surfaces()
	var heights: Dictionary = {}
	for house: Node3D in get_tree().get_nodes_in_group("map_storey"):
		if not house.get_meta("stairs"):
			continue
		var top: float = house.global_position.y + float(house.get_meta("roof_height"))
		if not heights.has(top):
			heights[top] = true
			await _walk_stairs(house)
	_check(heights.size() >= 3, "at least three traversable roof elevations")
	print("[TEST] MAP PASSED" if _fails == 0 else "[TEST] MAP FAILED (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _walk_stairs(house: Node3D) -> void:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	shape.shape = capsule
	shape.position.y = 0.7
	body.add_child(shape)
	add_child(body)
	var depth: float = house.get_meta("depth")
	body.global_position = house.to_global(Vector3(-float(house.get_meta("width")) / 2 + 1.4, 0.4, -depth / 2 + 1.1))
	var direction := house.global_basis * Vector3(0, 0, 3)
	for i in 240:
		await get_tree().physics_frame
		body.velocity = Vector3(direction.x, 0.0 if body.is_on_floor() else body.velocity.y - 9.8 / 60, direction.z)
		body.move_and_slide()
		if house.to_local(body.global_position).z > depth / 2 - 1.5:
			break
	print("[Map] Walk end ", body.global_position - house.global_position)
	_check(body.global_position.y >= house.global_position.y + float(house.get_meta("roof_height")) - 0.2, "mage capsule walks staircase without jumping or snagging")
	body.queue_free()


func _reachable(from: Vector3, to: Vector3) -> bool:
	var end := NavigationServer3D.map_get_closest_point(_nav_map, to)
	if Vector2(end.x - to.x, end.z - to.z).length() > 1.2 or absf(end.y - to.y) > 1.5:
		if _diagnostics < 12:
			print("[Map] Off mesh target ", to, " nearest ", end)
			_diagnostics += 1
		return false
	var path := NavigationServer3D.map_get_path(_nav_map, from, end, true)
	var ok := not path.is_empty() and path[-1].distance_to(end) < 0.1
	if not ok and _diagnostics < 12:
		print("[Map] Disconnected ", from, " -> ", to, " closest ", end, " path end ", path[-1] if not path.is_empty() else Vector3.INF)
		_diagnostics += 1
	return ok


func _clear(centre: Vector3, height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = centre
	query.collision_mask = 1
	return _space.intersect_shape(query).is_empty()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func _check(ok: bool, label: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _check_surfaces() -> void:
	# Test all outward face directions, including buildings rotated by quarter turns.
	var bounds: Array[AABB] = []
	var labels: Array[String] = []
	var clean := true
	for mesh: MeshInstance3D in _town.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh is BoxMesh or not _axis_aligned(mesh.global_basis):
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		for i in bounds.size():
			var other := bounds[i]
			for axis in 3:
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var area_u := minf(box.end[u], other.end[u]) - maxf(box.position[u], other.position[u])
				var area_v := minf(box.end[v], other.end[v]) - maxf(box.position[v], other.position[v])
				if area_u <= 0.001 or area_v <= 0.001:
					continue
				if absf(box.end[axis] - other.end[axis]) < 0.001 or absf(box.position[axis] - other.position[axis]) < 0.001:
					print("[Map] Coplanar faces: ", mesh.get_path(), " / ", labels[i])
					clean = false
		bounds.append(box)
		labels.append(str(mesh.get_path()))
	_check(clean, "no overlapping coplanar box faces")


func _axis_aligned(basis: Basis) -> bool:
	for axis: Vector3 in [basis.x, basis.y, basis.z]:
		if axis.abs()[axis.abs().max_axis_index()] < 0.9999:
			return false
	return true


func _reachable_silent(from: Vector3, to: Vector3) -> bool:
	var end := NavigationServer3D.map_get_closest_point(_nav_map, to)
	var path := NavigationServer3D.map_get_path(_nav_map, from, end, true)
	return not path.is_empty() and path[-1].distance_to(end) < 0.1


func _jump_gap(start: Vector3, end: Vector3) -> void:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.floor_snap_length = 0.3
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	collider.shape = capsule
	collider.position.y = 0.7
	body.add_child(collider)
	add_child(body)
	body.global_position = start + Vector3(0, 0.06, 0)
	for i in 10:
		await get_tree().physics_frame
		body.velocity.y -= 9.8 / 60
		body.move_and_slide()
	var grounded := body.is_on_floor()
	var direction := (end - start).normalized()
	var tuning := load("res://game/player/tuning_mage.tres") as PlayerTuning
	body.velocity.y = tuning.jump_velocity
	for i in 100:
		await get_tree().physics_frame
		var travel := direction * tuning.sprint_speed if (end - body.global_position).dot(direction) > 0.1 else Vector3.ZERO
		body.velocity = Vector3(travel.x, body.velocity.y - 9.8 / 60, travel.z)
		body.move_and_slide()
		if i > 10 and body.is_on_floor():
			break
	_check(grounded and body.is_on_floor() and body.global_position.distance_to(end) < 0.5, "mage capsule jumps into upper-storey entrance")
	body.queue_free()
