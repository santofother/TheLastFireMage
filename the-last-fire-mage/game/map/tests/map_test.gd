extends Node3D
## Saved village contracts, traversal and Fire Wave integration checks. Owner: S05.
## Public API: tools/tests/map_test.sh. Standalone authority runs the real Player and MageAbilities.
## NET: offline.

const PLAYER := preload("res://game/player/player.tscn")
const COVERAGE := preload("res://game/map/tests/flame_coverage.gd")
const ANCHOR := Vector3(-5, 0, 34)

class Driver extends RefCounted:
	var moving := false
	var sprint := false
	var jump := false

	## Supply the same PlayerInput used by device controls.
	func fill_input(_player: Player, intent: PlayerInput, _delta: float) -> void:
		intent.clear()
		intent.move = Vector2(0, -1) if moving else Vector2.ZERO
		intent.sprint = sprint
		intent.jump_pressed = jump
		jump = false

var _fails := 0
var _town: Node3D
var _space: PhysicsDirectSpaceState3D
var _nav: RID
var _player: Player
var _driver := Driver.new()
var _camera_checks := 0
var _camera_tucks := 0
var _camera_clear := true
var _links: Array[PackedVector3Array] = []


func _ready() -> void:
	get_tree().create_timer(950).timeout.connect(func() -> void:
		print("[TEST] FAIL map traversal timed out")
		get_tree().quit(1))
	_town = load("res://game/map/town.tscn").instantiate()
	add_child(_town)
	_nav = get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(_nav, false)
	var region := _town.get_node("ChickenNavigation") as NavigationRegion3D
	NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
	_run.call_deferred()


func _run() -> void:
	for i in 5:
		await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	NavigationServer3D.map_force_update(_nav)
	_contracts()
	_player = _spawn(ANCHOR + Vector3.UP * 0.08, Enums.Role.MAGE, false)
	_player.input_driver = _driver
	for name: String in ["WindingSpine", "LimekilnLane", "RoccaLane"]:
		var lane: Node3D = _town.find_child(name, true, false)
		var bends := lane.find_children("Bend*", "Marker3D", false, false)
		var walked := true
		for i in range(1, bends.size()):
			var start: Vector3 = bends[i - 1].global_position
			var finish: Vector3 = bends[i].global_position
			var passed := await _walk(start, finish)
			if passed:
				_links.append(PackedVector3Array([start, finish]))
			walked = walked and passed
		_check(walked, "standing mage walks all of " + name)
	_check(await _walk(Vector3(-1, 0, 34), Vector3(-1, 0, 50)),
		"market, quay and pier stay walkable across the paving seams")
	var doors_ok := true
	var doors := get_tree().get_nodes_in_group("map_house_exit") + get_tree().get_nodes_in_group("map_room_opening")
	for door: Marker3D in doors:
		var outward := door.global_basis.z
		var edge := door.global_position
		var passed := await _walk(edge + outward * 0.52, edge - outward * 0.52)
		if not passed:
			print("[Map] Door ", door.get_parent().get_path())
		if passed:
			_links.append(PackedVector3Array([edge + outward * 0.52, edge - outward * 0.52]))
		doors_ok = doors_ok and passed
	_check(doors_ok, "mage walks all exterior and interior doorways")
	var stairs_ok := true
	for stair: Node3D in get_tree().get_nodes_in_group("map_stair_ramp"):
		var foot: Vector3 = stair.get_node("Foot").global_position
		var top: Vector3 = stair.get_node("Landing").global_position
		var up := await _walk(foot, top)
		var down := await _walk(top, foot)
		if up and down:
			_links.append(PackedVector3Array([foot, top]))
		if not (up and down):
			print("[Map] Stair ", stair.get_path())
		stairs_ok = stairs_ok and up and down
	_check(stairs_ok, "mage walks all stairs including both waterfront returns")
	for link: Marker3D in get_tree().get_nodes_in_group("map_walk_link"):
		var start := link.global_position
		var end: Vector3 = link.get_meta("landing")
		var ok := await _walk(start, end)
		_check(ok, "mage walks " + str(link.name))
		if ok:
			_links.append(PackedVector3Array([start, end]))
	for role: int in [Enums.Role.MAGE, Enums.Role.VILLAGER]:
		_player.set_role(role)
		for route: Marker3D in get_tree().get_nodes_in_group("map_traversal"):
			var start := route.global_position
			var takeoff: Vector3 = route.get_meta("takeoff")
			var finish: Vector3 = route.get_meta("landing")
			var label := "%s %s" % ["mage" if role == Enums.Role.MAGE else "villager", route.name]
			var kind: String = route.get_meta("kind")
			var mantle := kind == "window_mantle"
			var roof := _town.find_child(String(route.name).trim_suffix("RoofLanding"), true, false) if kind == "roof_landing" else null
			var entered := await _jump(start, takeoff, finish, mantle, kind == "boat_sprint", roof)
			_check(entered, label)
			if kind.begins_with("roof_"):
				if entered and role == Enums.Role.MAGE:
					_links.append(PackedVector3Array([start, _player.global_position if roof else finish]))
				continue
			var direction := _flat(finish - start).normalized()
			var window := kind.begins_with("window")
			var reverse_start := finish + direction * (1.5 if window else 0.48)
			var reverse_trigger := finish + direction * (0.50 if window else -0.72)
			var reverse_finish := start + direction * (0.65 if window else 0.0)
			var returned: bool
			if kind.begins_with("boat_"):
				reverse_start = Vector3(8.0, -0.95, 49.5) if route.name == "DockToGull" else finish + direction * 1.38
				reverse_trigger = Vector3(7.44, -0.95, 49.5) if route.name == "DockToGull" else finish - direction * 0.63
				reverse_finish = Vector3(3.68, -0.64, 49.5) if route.name == "DockToGull" else Vector3(7.05, -0.95, 51.55)
				returned = await _jump(reverse_start, reverse_trigger, reverse_finish, false, kind == "boat_sprint")
			else:
				returned = await _jump(reverse_start, reverse_trigger, reverse_finish, false)
			_check(returned, label + " return")
			if entered and returned and role == Enums.Role.MAGE:
				_links.append(PackedVector3Array([start, finish]))
	print("[Map] Camera samples ", _camera_checks, " retractions ", _camera_tucks, " clear=", _camera_clear)
	_check(_camera_clear and _camera_checks > 100 and _camera_tucks > 0,
		"spring arm retracts in tight routes and camera near plane stays clear along tested routes")
	await _water_return()
	await _fire_wave()
	_player.queue_free()
	await get_tree().physics_frame
	_coverage()
	print("[TEST] MAP PASSED" if _fails == 0 else "[TEST] MAP FAILED (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _contracts() -> void:
	_check(_town.get_meta("layout_version") == "salmara-party-walls-v4", "new village is the production town")
	var apron := _town.find_child("MarketApron", true, false) as StaticBody3D
	var quay := _town.find_child("QuayDeck", true, false) as StaticBody3D
	var pier := _town.find_child("DockDeck", true, false) as StaticBody3D
	var previous := -INF
	var paving_is_flush := true
	for piece: StaticBody3D in [apron, quay, pier]:
		var mesh := piece.get_node("Mesh") as MeshInstance3D
		var bounds := mesh.global_transform * mesh.get_aabb()
		paving_is_flush = paving_is_flush and absf(bounds.end.y) < 0.001
		paving_is_flush = paving_is_flush and (previous == -INF or absf(bounds.position.z - previous) < 0.001)
		previous = bounds.end.z
	_check(paving_is_flush, "waterfront paving shares edges without coplanar overlap")
	_check(get_tree().get_nodes_in_group("map_district").size() == 4, "four connected wards")
	_check(get_tree().get_nodes_in_group("map_nook").size() >= 3, "dead ends")
	_check(get_tree().get_nodes_in_group("map_landmark").size() >= 4, "plazas and waterfront")
	_check(get_tree().get_nodes_in_group("map_boat").size() >= 4, "playable boats")
	var templates: Dictionary = {}
	var heights: Dictionary = {}
	for house: Node3D in get_tree().get_nodes_in_group("map_house"):
		templates[house.get_meta("template")] = true
		heights[house.get_meta("storeys")] = true
		var storeys := int(house.get_meta("storeys"))
		if storeys >= 2:
			var stair := house.get_node("Storey%d" % (storeys - 1)).has_node("Stairs")
			var walk_up := house.name in [&"Dyeworks", &"WatchHouse"]
			_check(stair == walk_up and _town.has_node(String(house.name) + "RoofLanding") != walk_up,
				"%s has its intended roof access" % house.name)
	_check(templates.size() == 4 and heights.size() == 3, "four interior layouts and one to three storeys")
	for node in _town.find_children("*", "StaticBody3D", true, false):
		# Furniture has its own layer so flame and the camera ignore it; cliff trees have no collision at all.
		if not node.collision_layer in [1, 256, 0]:
			_check(false, "world collision layer " + str(node.get_path()))
	_check(_town.find_children("*", "DirectionalLight3D", true, false).is_empty(), "sun and sky lighting stays in main")
	_check_furnishing()
	var region := _town.get_node("ChickenNavigation") as NavigationRegion3D
	_check(region.navigation_mesh.get_polygon_count() > 0 and
		is_equal_approx(region.navigation_mesh.cell_size, NavigationServer3D.map_get_cell_size(_nav)),
		"saved chicken navigation matches world voxels")
	var starts := {"villager_spawn": 8, "mage_spawn": 2, "chicken_spawn": 10, "item_spawn": 10}
	for group: String in starts:
		var markers := get_tree().get_nodes_in_group(group)
		_check(markers.size() >= int(starts[group]), "marker count " + group)
		for marker: Node3D in markers:
			var point := marker.global_position
			if not _clear(point, 0.35, 1.4) or _ray(point, point - Vector3.UP * 0.3).is_empty() or not _reachable(point):
				_check(false, "%s %s has clear connected footing at %s" % [group, marker.name, point])
	var hides := get_tree().get_nodes_in_group("hide_spot")
	_check(hides.size() >= 15, "existing hide spot population")
	for spot: Node3D in hides:
		var searchable := false
		for offset: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]:
			searchable = searchable or _reachable(spot.global_position + offset * 1.1)
		if not searchable or spot.scene_file_path != "res://game/interact/hide_spot.tscn":
			_check(false, "searchable hide spot %s" % spot.global_position)
	var recovery := _ray(Vector3(0, 2, 0), Vector3.ZERO)
	_check(not recovery.is_empty() and _clear(Vector3(0, 2, 0), 0.35, 1.4), "existing void recovery has clear footing")
	for name: String in ["SaltLoft", "BellLoft"]:
		var house := _town.find_child(name, true, false) as Node3D
		var level := int(house.get_meta("storeys")) - 1
		var top := house.get_node("Storey%d" % level) as Node3D
		var below := house.get_node("Storey%d" % (level - 1))
		var route: Marker3D = _town.get_node(name + "Window")
		var inside: Vector3 = route.get_meta("landing")
		var outside := route.global_position
		_check(below.has_node("Ceiling") and not below.has_node("Stairs") and
			top.has_node("Ceiling") and top.find_children("StreetDoor", "Marker3D", false, false).is_empty() and
			_ray(Vector3(outside.x, inside.y + 0.87, inside.z), inside + Vector3.UP * 0.87).is_empty(),
			name + " has a real window and a continuous floor with no stair or door entrance")
	_check(get_tree().get_nodes_in_group("map_rock_cut").size() == 2, "two traversable rock cuts")
	_check(get_tree().get_nodes_in_group("map_court").size() >= 6, "pocket courts provide green ground")



func _spawn(at: Vector3, role: int, bot: bool) -> Player:
	var player := PLAYER.instantiate() as Player
	player.position = at
	player.is_bot = bot
	add_child(player)
	player.set_role(role)
	return player


func _place(start: Vector3, direction: Vector3) -> void:
	_driver.moving = false
	_driver.sprint = false
	_player.rotation.y = atan2(-direction.x, -direction.z)
	_player.teleport(start + Vector3.UP * 0.06)
	for i in 10:
		await get_tree().physics_frame


func _walk(start: Vector3, finish: Vector3) -> bool:
	var direction := _flat(finish - start).normalized()
	await _place(start, direction)
	var grounded := _player.is_on_floor()
	_driver.moving = true
	for i in ceili(_flat(finish - start).length() * 19) + 70:
		await get_tree().physics_frame
		_check_camera()
		if _flat(finish - _player.global_position).dot(direction) <= 0.14 and _player.is_on_floor():
			break
	_driver.moving = false
	var ok := grounded and _player.is_on_floor() and _player.global_position.distance_to(finish) < 0.34
	if not ok:
		print("[Map] Walk ", start, " -> ", finish, " ended at ", _player.global_position)
	return ok


func _jump(start: Vector3, takeoff: Vector3, finish: Vector3, needs_mantle: bool, sprint := false, roof: Node = null) -> bool:
	var direction := _flat(finish - start).normalized()
	await _place(start, direction)
	if not _player.is_on_floor():
		print("[Map] No takeoff footing at ", start, " settled at ", _player.global_position)
		return false
	_driver.moving = true
	_driver.sprint = needs_mantle or sprint
	var jumped := false
	var was_airborne := false
	var pulled := false
	var ok := false
	for i in 130:
		await get_tree().physics_frame
		_check_camera()
		if not jumped and (takeoff - _player.global_position).dot(direction) < 0.06:
			_driver.jump = true
			jumped = true
		was_airborne = was_airborne or not _player.is_on_floor()
		pulled = pulled or _player.is_mantling
		var position := _player.global_position
		if jumped and was_airborne and _player.is_on_floor() and _flat(finish - position).dot(direction) < 0.38:
			var at_height := absf(position.y - finish.y) < 0.13
			if roof != null:
				# The final jump can land on the flat eave or higher on that house's pitched tiles.
				var hit := _ray(position + Vector3.UP * 0.1, position - Vector3.UP * 0.24)
				var surface: Node = hit.get("collider")
				at_height = position.y >= finish.y - 0.04 and surface != null and roof.is_ancestor_of(surface)
			if at_height:
				ok = not needs_mantle or pulled
				break
		if position.y < minf(start.y, finish.y) - 0.45:
			break
	_driver.moving = false
	_driver.sprint = false
	if not ok:
		print("[Map] Jump ", start, " via ", takeoff, " -> ", finish, " ended at ", _player.global_position,
			" (jump=", jumped, " mantle=", pulled, ")")
	return ok


func _check_camera() -> void:
	var arm := _player.camera.get_parent() as SpringArm3D
	if not _player.camera.current or arm.get_hit_length() <= 0:
		return
	_camera_checks += 1
	if arm.get_hit_length() < _player.tuning.camera_distance - 0.2:
		_camera_tucks += 1
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.022
	query.shape = probe
	query.transform.origin = _player.camera.global_position - _player.camera.global_basis.z * (_player.camera.near + 0.025)
	query.collision_mask = 1 | 16
	var clear := _space.intersect_shape(query, 1).is_empty()
	if not clear and _camera_clear:
		print("[Map] Camera inside geometry at ", _player.camera.global_position, " player ", _player.global_position,
			" spring ", arm.get_hit_length(), " role ", _player.role)
	_camera_clear = _camera_clear and clear


func _coverage() -> void:
	var crates: Array[AABB] = []
	for spot: Node3D in get_tree().get_nodes_in_group("hide_spot"):
		var crate := spot.get_node("Crate") as CSGBox3D
		crates.append(crate.global_transform * AABB(-crate.size / 2, crate.size))
	var tuning := preload("res://game/mage/tuning_mage_combat.tres") as MageCombatTuning
	var missing := COVERAGE.new().audit(_space, ANCHOR, _links, crates, tuning)
	var zones: Dictionary = {}
	for point in missing:
		var hit := _ray(point + Vector3.UP * 0.04, point - Vector3.UP * 0.04)
		var node: Node = hit.get("collider")
		if is_instance_valid(node):
			while node != _town and node.get_parent() != _town and not node.is_in_group("map_house") and not node.is_in_group("map_court") and not node.is_in_group("map_landmark"):
				node = node.get_parent()
			var key := "%s @%.1f" % [node.name, snappedf(point.y, 0.5)]
			zones[key] = int(zones.get(key, 0)) + 1
	if not zones.is_empty():
		print("[Map] Uncovered samples by area: ", zones)
		for i in mini(8, missing.size()):
			print("[Map] Uncovered feet ", missing[i])
	_check(missing.is_empty(), "sampled street, floor, roof, deck and recovery shelf positions have Fire Wave coverage")


func _water_return() -> void:
	await _place(Vector3(14.8, -1.21, 55), Vector3.RIGHT)
	_driver.moving = true
	for i in 160:
		if _player.global_position.x >= 17.5:
			break
		await get_tree().physics_frame
	_driver.moving = false
	for i in 20:
		await get_tree().physics_frame
	var feet := _player.global_position
	var safe := _player.is_on_floor() and absf(feet.y - -2.65) < 0.05
	_check(safe and await _walk(feet, Vector3(23, -2.65, 49.65)),
		"a missed jump lands on the recovery shelf and walks to the east steps")


func _fire_wave() -> void:
	_player.set_role(Enums.Role.MAGE)
	var ability := _player.abilities.get_child(0) as MageAbilities
	for boat: Node3D in get_tree().get_nodes_in_group("map_boat"):
		var samples: Array[Vector3] = []
		for x: float in [-0.52, 0.0, 0.52]:
			for z: float in [-1.52, 0.0, 1.55]:
				samples.append(boat.to_global(Vector3(x, 0, z)))
		await _wave_samples(ability, boat.global_position, samples, boat.name)
	for label: String in ["SaltLoft", "BellLoft"]:
		var route: Marker3D = _town.get_node(label + "Window")
		var entry: Vector3 = route.get_meta("landing")
		var samples: Array[Vector3] = [entry + Vector3.RIGHT * 1.05, entry + Vector3.RIGHT * 2.1, entry + Vector3.RIGHT * 2.95]
		await _wave_samples(ability, entry, samples, label)
	# Aim directly at a target through the solid shutter adjacent to the window.
	var route: Marker3D = _town.get_node("SaltLoftWindow")
	var inside: Vector3 = route.get_meta("landing")
	var outside := route.global_position
	outside.z += 1.35
	inside.z += 1.35
	await _place(outside, Vector3.RIGHT)
	var target := _spawn(inside + Vector3.UP * 0.05, Enums.Role.VILLAGER, true)
	await get_tree().physics_frame
	var hp := target.health.hp
	ability._attack(&"fire_wave", (target.global_position - _player.global_position + Vector3.DOWN * 0.25).normalized())
	_check(is_equal_approx(target.health.hp, hp), "closed wall blocks the actual Fire Wave")
	target.queue_free()


func _wave_samples(ability: MageAbilities, anchor: Vector3, points: Array[Vector3], label: String) -> void:
	var clean := true
	for point in points:
		if not _clear(point + Vector3.UP * 0.035, 0.3, 1.0):
			continue
		var sources: Array[Vector3] = [anchor]
		for x in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				sources.append(point + Vector3(x, 0, z) * 0.9)
		var source := Vector3.INF
		for candidate in sources:
			if candidate.distance_to(point) < 0.73:
				continue
			var floor := _ray(candidate + Vector3.UP * 0.08, candidate - Vector3.UP * 0.11)
			if floor.is_empty() or not _clear(candidate + Vector3.UP * 0.04, 0.35, 1.4):
				continue
			var origin := candidate + Vector3.UP * 0.65
			var hit := point + Vector3.UP * 0.4
			if origin.distance_to(hit) <= ability.tuning.wave_range and _ray(origin, hit).is_empty():
				source = candidate
				break
		if not source.is_finite():
			clean = false
			print("[Map] Missing firing position for ", label, " at ", point)
			continue
		await _place(source, _flat(point - source).normalized())
		var target := _spawn(point + Vector3.UP * 0.04, Enums.Role.VILLAGER, true)
		await get_tree().physics_frame
		var before := target.health.hp
		var aim := ((target.global_position + Vector3.UP * 0.4) -
			(_player.global_position + Vector3.UP * 0.65)).normalized()
		ability._attack(&"fire_wave", aim)
		if not target.health.hp < before:
			clean = false
			print("[Map] Fire Wave missed ", label, " from ", source, " to ", point)
		target.queue_free()
		await get_tree().physics_frame
	_check(clean, "%s Fire Wave hits deck or room corners and centre" % label)


func _reachable(point: Vector3) -> bool:
	var end := NavigationServer3D.map_get_closest_point(_nav, point)
	if end.distance_to(point) > 0.96:
		return false
	var path := NavigationServer3D.map_get_path(_nav, ANCHOR, end, true)
	return not path.is_empty() and path[-1].distance_to(end) < 0.1


func _clear(feet: Vector3, radius: float, height: float) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = feet + Vector3.UP * height / 2
	query.collision_mask = 1 | 16
	return _space.intersect_shape(query, 1).is_empty()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 16))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _check_furnishing() -> void:
	var furniture := get_tree().get_nodes_in_group("map_furniture")
	var breakable := get_tree().get_nodes_in_group(BreakableProp.GROUP)
	var foliage := get_tree().get_nodes_in_group("map_foliage")
	var trees := foliage.filter(func(node: Node) -> bool: return String(node.name).begins_with("Tree"))
	print("[Map] Furniture %d, breakable %d, lights %d, foliage %d, trees %d" % [furniture.size(), breakable.size(),
		get_tree().get_nodes_in_group("map_light").size(), foliage.size(), trees.size()])
	_check(furniture.size() >= 600, "rooms are furnished")
	_check(breakable.size() >= 300, "wooden furniture can break")
	_check(get_tree().get_nodes_in_group("map_light").size() >= 150, "rooms have torches or lanterns")
	_check(foliage.size() >= 300 and trees.size() >= 15, "town has trees, bushes and flowers")
	_check(not get_tree().get_nodes_in_group("map_vines").is_empty(), "buildings have vines")
	for house: Node3D in get_tree().get_nodes_in_group("map_house"):
		var count := house.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool:
			return node.is_in_group("map_furniture")).size()
		_check(count >= 3, "%s has furniture" % house.name)
	# Furniture must never crowd a doorway the route tests below rely on.
	var doors := get_tree().get_nodes_in_group("map_house_exit") + get_tree().get_nodes_in_group("map_room_opening")
	for door: Node3D in doors:
		for prop: Node3D in furniture:
			if absf(prop.global_position.y - door.global_position.y) < 1.5 and \
					Vector2(prop.global_position.x - door.global_position.x, prop.global_position.z - door.global_position.z).length() < 0.6:
				_check(false, "%s clears %s" % [prop.name, door.get_path()])


func _check(ok: bool, label: String) -> void:
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_fails += 1
