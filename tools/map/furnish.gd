extends RefCounted
## Dresses the generated town: room furniture, wall lights, gardens, street planting and vines.
## Owner: furnishing pass (S05 follow-up). Called by tools/map/generate.gd once the walls have physics.
## Public API: `run(generator)`. Every placement is checked against real collision, floor support and
## the door, stair and route markers, so moving a wall in layout.json can never block a doorway.
## NET: offline authoring tool; the saved scene is identical on every peer.

const PROPS := "res://game/props/%s.tscn"
const WORLD_MASK := 1
const FLOOR_TOLERANCE := 0.07
const WALL_GAP := 0.03
const ITEM_GAP := 0.14
const SITE_STEP := 0.42
## TUNE: Height of wall fixtures above the floor. Below the 1.76 m door head.
const FIXTURE_HEIGHT := 1.02

## TUNE: Per-room plans, tried in order. Anything that cannot fit is skipped.
## ["set", table, seat, seats] table with seats · ["wall", key...] first key that fits against a wall
## ["row", key...] items side by side · ["light", key] wall fixture.
const RECIPES := {
	"kitchen": [["set", "table", "stool", 3], ["wall", "shelf"], ["row", "crate", "crate"], ["wall", "cauldron"], ["pot"],
		["light", "torch"]],
	"living": [["set", "table", "chair", 2], ["wall", "shelf"], ["wall", "bench"], ["wall", "chest"], ["pot"], ["light", "lantern"]],
	# TODO(S05): the interior pack has no bed, so bedrooms have none until a matching model exists.
	"bedroom": [["wall", "chest"], ["top", "stool", "candles"], ["wall", "bench"], ["pot"], ["light", "lantern"]],
	"storage": [["row", "crate", "chest", "crate"], ["row", "crate", "crate"], ["wall", "shelf"], ["light", "torch"]],
	"workshop": [["set", "workbench", "stool", 1], ["row", "crate", "crate"], ["wall", "shelf"], ["wall", "vase"], ["light", "torch"]],
	"shop": [["set", "table", "stool", 0], ["row", "crate", "crate", "chest"], ["wall", "shelf"], ["pot"], ["light", "lantern"]],
	"chapel": [["wall", "bench"], ["wall", "bench"], ["wall", "bench"], ["top", "stool", "candles"], ["top", "stool", "candles"],
		["wall", "vase"], ["light", "lantern"]],
}
## TUNE: Wall dressing per room, tried in order. No collision, so it can never affect a route.
const WALL_DECOR := {
	"kitchen": ["plates", "herbs", "ledge", "herbs", "plates", "ledge", "pegs"],
	"living": ["painting", "tapestry", "ledge", "painting", "banner", "painting", "ledge"],
	"bedroom": ["painting", "pegs", "tapestry", "ledge", "painting", "painting"],
	"storage": ["pegs", "ledge", "tools", "herbs", "ledge", "pegs"],
	"workshop": ["tools", "ledge", "tools", "pegs", "ledge", "herbs"],
	"shop": ["ledge", "banner", "ledge", "plates", "ledge", "banner"],
	"chapel": ["tapestry", "tapestry", "banner", "tapestry", "banner", "tapestry"],
}
const RUG_ROOMS := ["living", "bedroom", "chapel", "shop"]
const DECOR_SIZE := {"painting": Vector2(0.62, 0.46), "tapestry": Vector2(0.7, 1.1), "plates": Vector2(0.95, 0.3),
	"herbs": Vector2(0.65, 0.5), "ledge": Vector2(0.95, 0.3), "pegs": Vector2(0.75, 0.75), "tools": Vector2(0.9, 0.55),
	"banner": Vector2(0.55, 0.9)}
const DECOR_CENTRE := 1.32 # TUNE: height of wall dressing above the floor
const CLOTHS := [Color(0.55, 0.16, 0.14), Color(0.17, 0.3, 0.5), Color(0.26, 0.4, 0.24), Color(0.62, 0.45, 0.16), Color(0.4, 0.22, 0.42)]
const WOOD := Color(0.31, 0.2, 0.12)
# CONTRACT: only props with no collision, so shelves can never block a search ray or a route.
const SHELF_ITEMS := ["bottle", "bowl", "books", "candles"]
const CRAFT_NAMES := ["Dye", "Rope", "Weaver", "Tanner", "Cooper", "Potter", "Sail", "Net", "Tiler", "Carver", "Mender",
	"Scribe", "Press", "Kiln", "Cloth", "Wool", "Oven"]
const POTS := ["pot_plant_fern", "pot_plant_flowers", "pot_plant_leafy", "pot_plant_tall"]
const TREES := {
	"OliveYard": ["tree_small_a", "tree_palm_c"], "CuttersYard": ["tree_common_b"], "DyersGarden": ["tree_common_a"],
	"CisternYard": ["tree_small_b"], "IndigoCourt": ["tree_small_a"], "JuniperCourt": ["tree_palm_b"],
	"CandleCourt": ["tree_common_c"], "LaurelYard": ["tree_common_b", "tree_small_b"], "SailYard": ["tree_palm_c"],
}
const STREET_TUFTS := ["grass_short", "grass_short", "grass_tall", "grass_wisp", "clover", "fern", "flowers_a", "flowers_b",
	"flower_a", "flower_b"]
const COURT_TUFTS := ["grass_tall", "grass_wisp", "grass_short", "fern", "flowers_a", "flowers_b", "flowers_a", "clover"]
const LEAF_COLOURS := [Color(0.27, 0.42, 0.17), Color(0.33, 0.49, 0.19), Color(0.22, 0.36, 0.16), Color(0.39, 0.53, 0.22)]

var g # The running generate.gd SceneTree. Untyped because that script has no class_name.
var space: PhysicsDirectSpaceState3D
var rng := RandomNumberGenerator.new()
var _scenes: Dictionary = {}
var _keep: Array = []
var _placed: Array = []
var _counts: Dictionary = {}
var _vines: Dictionary = {}
var _vine_material: StandardMaterial3D
var _decor: Dictionary = {} # band -> SurfaceTool
var _decor_used: Array = []


## Places everything. `generator` is the running generate.gd; its walls must already be in the physics world.
func run(generator: Variant) -> void:
	g = generator
	space = g.root.get_world_3d().direct_space_state
	_collect_keep_outs()
	for room: Dictionary in g._rooms:
		_furnish_storey(room)
	_plant_courts()
	_plant_streets()
	_plant_landmarks()
	_plant_cliffs()
	_commit_decor()
	_grow_vines()
	print("[Map] Furnished: %s" % str(_counts))


# --- Interiors ---------------------------------------------------------------------------------

func _furnish_storey(room: Dictionary) -> void:
	var z0: float = room.z0 + g.WALL
	var z1: float = room.z1 - g.WALL
	var north_end: float = room.split - 0.09
	var south_start: float = room.split + 0.09
	if room.covered:
		north_end = room.entry_z - 1.03
		south_start = room.entry_z + 1.03
	rng.seed = hash("%s%d" % [room.house, room.level])
	var kinds := _room_kinds(room)
	for i in 2:
		var low: float = z0 if i == 0 else south_start
		var high: float = north_end if i == 0 else z1
		if high - low < 1.1:
			continue
		_placed = []
		var kind: String = kinds[i]
		for step: Array in RECIPES[kind]:
			_run_step(step, room, low, high)
		# WHY: dressing must not consume the furniture sequence, or adding a picture moves the room's furniture.
		var furniture_state := rng.state
		_decorate(room, low, high, kind)
		rng.state = furniture_state
		_counts[kind] = int(_counts.get(kind, 0)) + 1


func _room_kinds(room: Dictionary) -> Array:
	var house: String = room.house
	var top: bool = room.level == room.levels - 1
	var craft := CRAFT_NAMES.any(func(word: String) -> bool: return house.contains(word))
	var flip := hash(house) % 2 == 0
	var pair: Array
	if room.template == "chapel":
		pair = ["chapel", "chapel"]
	elif room.loft:
		pair = ["storage", "storage"]
	elif room.covered:
		pair = ["shop", "storage"]
	elif room.levels == 1:
		pair = ["kitchen", "workshop" if craft else "bedroom"]
	elif room.level == 0:
		pair = ["kitchen", "workshop" if craft else "living"] if room.template != "court" else ["living", "storage"]
	elif top:
		pair = ["bedroom", "bedroom" if room.levels == 2 else "storage"]
	else:
		pair = ["living", "workshop" if craft else "bedroom"]
	return [pair[1], pair[0]] if flip else pair


func _run_step(step: Array, room: Dictionary, low: float, high: float) -> void:
	match step[0]:
		"set":
			_table_set(room, low, high, step[1], step[2], step[3])
		"wall":
			for key: String in step.slice(1):
				if not _against_wall(room, low, high, key).is_empty():
					break
		"row":
			_row(room, low, high, step.slice(1))
		"top":
			var base := _against_wall(room, low, high, step[1])
			if not base.is_empty():
				_set_on_top(base, step[2])
		"pot":
			_against_wall(room, low, high, POTS[rng.randi() % POTS.size()])
		"light":
			_wall_light(room, low, high, step[1])


# All wall-hugging positions of one room; each is a line point plus inward direction, shuffled.
func _sites(room: Dictionary, low: float, high: float) -> Array:
	var sites: Array = []
	var band: int = room.band
	for at: float in [low, high]:
		var inward := Vector2(0.0, 1.0 if at == low else -1.0)
		var edge: Vector2 = g._edges(band, at)
		var x: float = edge.x + 0.7
		while x < edge.y - 0.7:
			sites.append({"p": Vector2(x, at), "in": inward})
			x += SITE_STEP
	var z := low + 0.45
	while z < high - 0.4:
		var edge: Vector2 = g._edges(band, z)
		var wall: float = g.WALL + 0.02
		sites.append({"p": Vector2(edge.x + wall, z), "in": Vector2(1.0, 0.0)})
		sites.append({"p": Vector2(edge.y - wall, z), "in": Vector2(-1.0, 0.0)})
		z += SITE_STEP
	# Fisher-Yates with the seeded generator keeps regeneration deterministic.
	for i in range(sites.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Dictionary = sites[i]
		sites[i] = sites[j]
		sites[j] = swap
	return sites


func _against_wall(room: Dictionary, low: float, high: float, key: String) -> Dictionary:
	var size := _size(key)
	for site: Dictionary in _sites(room, low, high):
		var inward: Vector2 = site.in
		var at: Vector2 = site.p + inward * (size.y / 2.0 + WALL_GAP)
		var placed := _try(room, low, high, key, at, atan2(inward.x, inward.y))
		if not placed.is_empty():
			return placed
	return {}


func _row(room: Dictionary, low: float, high: float, keys: Array) -> void:
	var first := _against_wall(room, low, high, keys[0])
	if first.is_empty():
		return
	var tangent := Vector2(cos(first.yaw), -sin(first.yaw))
	var last: Dictionary = first
	for i in range(1, keys.size()):
		var key: String = keys[i]
		var size := _size(key)
		var inward := Vector2(sin(first.yaw), cos(first.yaw))
		var step: float = last.size.x / 2.0 + size.x / 2.0 + 0.04
		var wall_line: Vector2 = first.at - inward * (first.size.y / 2.0)
		var along: Vector2 = wall_line + tangent * (last.along + step) + inward * (size.y / 2.0)
		var placed := _try(room, low, high, key, along, first.yaw, 0.02)
		if placed.is_empty():
			continue
		placed.along = last.along + step
		last = placed


func _table_set(room: Dictionary, low: float, high: float, table: String, seat: String, seats: int) -> void:
	var placed := _against_wall(room, low, high, table)
	if placed.is_empty() or seats == 0:
		return
	var inward := Vector2(sin(placed.yaw), cos(placed.yaw))
	var tangent := Vector2(cos(placed.yaw), -sin(placed.yaw))
	var seat_size := _size(seat)
	var front: Vector2 = placed.at + inward * (placed.size.y / 2.0 + seat_size.y / 2.0 + 0.05)
	var options: Array = [
		[front + tangent * placed.size.x * 0.24, placed.yaw + PI],
		[front - tangent * placed.size.x * 0.24, placed.yaw + PI],
		[placed.at + tangent * (placed.size.x / 2.0 + seat_size.x / 2.0 + 0.06), placed.yaw - PI / 2.0],
		[placed.at - tangent * (placed.size.x / 2.0 + seat_size.x / 2.0 + 0.06), placed.yaw + PI / 2.0],
	]
	var added := 0
	for option: Array in options:
		if added == seats:
			break
		if not _try(room, low, high, seat, option[0], option[1], 0.02, true).is_empty():
			added += 1
	if table == "table":
		_set_on_top(placed, ["candles", "books", "bottle", "bowl"][rng.randi() % 4])


# A prop on a breakable parent is its child, so it disappears when the parent shatters.
func _set_on_top(base: Dictionary, key: String) -> void:
	var item := _instance(base.node, key, base.node.get_meta("height", 0.4) * Vector3.UP, 0.0)
	item.position.y = float(base.node.get_meta("height", 0.4))


func _try(room: Dictionary, low: float, high: float, key: String, at: Vector2, yaw: float,
		gap := ITEM_GAP, skip_gap := false) -> Dictionary:
	var size := _size(key)
	var height := _height(key)
	var y: float = room.y
	var turned := absf(sin(yaw)) > 0.7
	var extent := Vector2(size.y if turned else size.x, size.x if turned else size.y) / 2.0
	var pos := Vector3(at.x, y, at.y)
	if at.y - extent.y < low - 0.01 or at.y + extent.y > high + 0.01:
		return {}
	if not _clear_of_routes(pos, extent.length() + 0.05):
		return {}
	var separation := 0.0 if skip_gap else gap
	for other: Dictionary in _placed:
		var other_extent: Vector2 = other.extent
		if absf(other.at.x - at.x) < extent.x + other_extent.x + separation and \
				absf(other.at.y - at.y) < extent.y + other_extent.y + separation:
			return {}
	if not _box_clear(pos, yaw, size, height) or not _supported(pos, extent, y):
		return {}
	var node := _instance(room.floor, key, pos, yaw)
	node.add_to_group("map_furniture", true)
	var placed := {"key": key, "at": at, "yaw": yaw, "size": size, "extent": extent, "node": node, "along": 0.0}
	_placed.append(placed)
	return placed


func _wall_light(room: Dictionary, low: float, high: float, key: String) -> void:
	var size := _size(key)
	for site: Dictionary in _sites(room, low, high):
		var inward: Vector2 = site.in
		var height: float = room.y + FIXTURE_HEIGHT + _height(key) * 0.5
		var from := Vector3(site.p.x + inward.x * 0.7, height, site.p.y + inward.y * 0.7)
		var to := Vector3(site.p.x - inward.x * 0.5, height, site.p.y - inward.y * 0.5)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK))
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.2:
			continue
		var point: Vector3 = hit.position
		if point.z < low - 0.3 or point.z > high + 0.3 or not _clear_of_routes(Vector3(point.x, room.y, point.z), 0.5):
			continue
		if _behind_tall_furniture(Vector2(point.x, point.z)):
			continue
		var normal: Vector3 = hit.normal
		var node := _instance(room.floor, key, point + normal * (size.y / 2.0) + Vector3.DOWN * _height(key) * 0.5,
			atan2(normal.x, normal.z))
		node.add_to_group("map_light", true)
		_counts.light = int(_counts.get("light", 0)) + 1
		return


func _behind_tall_furniture(point: Vector2) -> bool:
	for other: Dictionary in _placed:
		if _height(other.key) > FIXTURE_HEIGHT - 0.1 and (other.at as Vector2).distance_to(point) < 0.9:
			return true
	return false


# --- Wall dressing ------------------------------------------------------------------------------

func _decorate(room: Dictionary, low: float, high: float, kind: String) -> void:
	_decor_used = []
	for key: String in WALL_DECOR[kind]:
		var anchor := _decor_anchor(room, low, high, DECOR_SIZE[key])
		if anchor.is_empty():
			continue
		call("_decor_" + key, room, anchor)
		_counts.wall_decor = int(_counts.get("wall_decor", 0)) + 1
	if kind in RUG_ROOMS:
		_rug(room, low, high)


# A wall spot whose whole face is solid plaster, so nothing hangs across a window, door or corner.
func _decor_anchor(room: Dictionary, low: float, high: float, size: Vector2) -> Dictionary:
	var centre_y: float = room.y + DECOR_CENTRE
	for site: Dictionary in _sites(room, low, high):
		var inward: Vector2 = site.in
		var from := Vector3(site.p.x + inward.x * 0.7, centre_y, site.p.y + inward.y * 0.7)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from,
			Vector3(site.p.x - inward.x * 0.5, centre_y, site.p.y - inward.y * 0.5), WORLD_MASK))
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.1:
			continue
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		if point.z < low - 0.3 or point.z > high + 0.3 or not _clear_of_routes(Vector3(point.x, room.y, point.z), 0.35):
			continue
		if _behind_tall_furniture(Vector2(point.x, point.z)) or _decor_crowded(point, size.x):
			continue
		if not _wall_solid(point, normal, size):
			continue
		_decor_used.append([point, size.x])
		return {"at": point, "n": normal, "t": normal.cross(Vector3.UP).normalized()}
	return {}


func _decor_crowded(point: Vector3, width: float) -> bool:
	for used: Array in _decor_used:
		if (used[0] as Vector3).distance_to(point) < (float(used[1]) + width) / 2.0 + 0.25:
			return true
	return false


func _wall_solid(point: Vector3, normal: Vector3, size: Vector2) -> bool:
	var tangent := normal.cross(Vector3.UP).normalized()
	for corner: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var target: Vector3 = point + tangent * corner.x * size.x + Vector3.UP * corner.y * size.y
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(target + normal * 0.25, target - normal * 0.12, WORLD_MASK))
		if hit.is_empty() or absf((hit.position as Vector3).distance_to(target)) > 0.05:
			return false
	return true


func _decor_painting(room: Dictionary, a: Dictionary) -> void:
	_panel(room, a, 0.0, 0.0, 0.62, 0.46, 0.03, WOOD)
	var sky := Color(0.55, 0.68, 0.76).lerp(Color(0.86, 0.62, 0.42), rng.randf())
	_panel(room, a, 0.0, 0.0, 0.54, 0.38, 0.038, sky)
	_panel(room, a, 0.0, -0.1, 0.54, 0.18, 0.042, Color(0.2, 0.33, 0.42).lerp(Color(0.34, 0.42, 0.22), rng.randf()))
	_panel(room, a, rng.randf_range(-0.16, 0.16), 0.08, 0.08, 0.08, 0.046, Color(0.96, 0.84, 0.5))


func _decor_tapestry(room: Dictionary, a: Dictionary) -> void:
	var cloth: Color = CLOTHS[rng.randi() % CLOTHS.size()]
	_panel(room, a, 0.0, 0.57, 0.8, 0.04, 0.05, WOOD)
	_panel(room, a, 0.0, 0.0, 0.7, 1.1, 0.02, cloth)
	_panel(room, a, 0.0, 0.42, 0.62, 0.05, 0.026, cloth.lightened(0.45))
	_panel(room, a, 0.0, -0.42, 0.62, 0.05, 0.026, cloth.lightened(0.45))
	_panel(room, a, 0.0, 0.0, 0.2, 0.2, 0.026, cloth.lightened(0.3))


func _decor_banner(room: Dictionary, a: Dictionary) -> void:
	var cloth: Color = CLOTHS[rng.randi() % CLOTHS.size()]
	_panel(room, a, 0.0, 0.47, 0.65, 0.04, 0.05, WOOD)
	_panel(room, a, 0.0, 0.0, 0.55, 0.9, 0.02, cloth)
	_panel(room, a, 0.0, 0.05, 0.14, 0.42, 0.026, cloth.lightened(0.5))
	_panel(room, a, 0.0, 0.1, 0.34, 0.12, 0.026, cloth.lightened(0.5))


func _decor_plates(room: Dictionary, a: Dictionary) -> void:
	_panel(room, a, 0.0, -0.12, 0.95, 0.05, 0.16, WOOD)
	_panel(room, a, 0.0, 0.14, 0.95, 0.03, 0.04, WOOD)
	for i in 4:
		var x := -0.33 + 0.22 * i
		var plate := Color(0.86, 0.82, 0.72).lerp(Color(0.42, 0.56, 0.68), rng.randf() * 0.6)
		_panel(room, a, x, 0.0, 0.17, 0.11, 0.04, plate)
		_panel(room, a, x, 0.0, 0.11, 0.17, 0.04, plate)


func _decor_herbs(room: Dictionary, a: Dictionary) -> void:
	_panel(room, a, 0.0, 0.2, 0.65, 0.05, 0.05, WOOD)
	for i in 3:
		var x := -0.21 + 0.21 * i
		var herb := Color(0.33, 0.42, 0.18).lerp(Color(0.62, 0.52, 0.2), rng.randf())
		var drop := rng.randf_range(0.22, 0.34)
		_panel(room, a, x, 0.2 - drop * 0.5, 0.11, drop, 0.07, herb)
		_panel(room, a, x, 0.17, 0.05, 0.06, 0.09, Color(0.7, 0.62, 0.42))


func _decor_ledge(room: Dictionary, a: Dictionary) -> void:
	_panel(room, a, 0.0, -0.02, 0.95, 0.04, 0.24, WOOD)
	for side: float in [-0.36, 0.36]:
		_panel(room, a, side, -0.12, 0.04, 0.18, 0.12, WOOD.darkened(0.2))
	var count := rng.randi_range(2, 4)
	for i in count:
		var x := lerpf(-0.34, 0.34, (float(i) + 0.5) / float(count))
		var key: String = SHELF_ITEMS[rng.randi() % SHELF_ITEMS.size()]
		var pos: Vector3 = a.at + a.t * x + a.n * 0.13 + Vector3.UP * (room.y + DECOR_CENTRE - a.at.y)
		_instance(room.floor, key, pos, rng.randf() * TAU)


func _decor_pegs(room: Dictionary, a: Dictionary) -> void:
	_panel(room, a, 0.0, 0.3, 0.75, 0.05, 0.04, WOOD)
	for i in 3:
		var x := -0.25 + 0.25 * i
		_panel(room, a, x, 0.3, 0.03, 0.03, 0.1, WOOD.darkened(0.3))
		if rng.randf() < 0.75:
			var cloth: Color = CLOTHS[rng.randi() % CLOTHS.size()].darkened(0.15)
			var drop := rng.randf_range(0.42, 0.68)
			_panel(room, a, x, 0.28 - drop * 0.5, 0.22, drop, 0.06, cloth)


func _decor_tools(room: Dictionary, a: Dictionary) -> void:
	_panel(room, a, 0.0, 0.0, 0.9, 0.55, 0.02, WOOD.lightened(0.12))
	var iron := Color(0.4, 0.4, 0.43)
	_panel(room, a, -0.3, 0.0, 0.04, 0.42, 0.04, WOOD)
	_panel(room, a, -0.3, 0.19, 0.18, 0.08, 0.05, iron)
	_panel(room, a, 0.0, 0.05, 0.3, 0.09, 0.03, iron)
	_panel(room, a, 0.0, -0.08, 0.05, 0.2, 0.04, WOOD)
	_panel(room, a, 0.3, -0.03, 0.04, 0.36, 0.04, WOOD)
	_panel(room, a, 0.3, 0.17, 0.14, 0.12, 0.05, iron)


func _rug(room: Dictionary, low: float, high: float) -> void:
	var z := (low + high) / 2.0
	var edge: Vector2 = g._edges(room.band, z)
	var centre := Vector3((edge.x + edge.y) / 2.0, room.y, z)
	var extent := Vector2(minf((edge.y - edge.x) * 0.26, 1.1), minf((high - low) * 0.28, 0.9))
	if extent.x < 0.4 or extent.y < 0.35 or not _supported(centre, extent, room.y) or not _clear_of_routes(centre, 0.1):
		return
	var cloth: Color = CLOTHS[rng.randi() % CLOTHS.size()]
	var surface := _decor_surface(room.band)
	_box(surface, centre + Vector3.UP * 0.008, Vector3(extent.x, 0, 0), Vector3(0, 0.008, 0), Vector3(0, 0, extent.y), cloth)
	_box(surface, centre + Vector3.UP * 0.018, Vector3(extent.x * 0.82, 0, 0), Vector3(0, 0.003, 0), Vector3(0, 0, extent.y * 0.8), cloth.lightened(0.35))
	_box(surface, centre + Vector3.UP * 0.024, Vector3(extent.x * 0.66, 0, 0), Vector3(0, 0.003, 0), Vector3(0, 0, extent.y * 0.62), cloth)
	_counts.rugs = int(_counts.get("rugs", 0)) + 1


# Coloured box flat on the wall: `x`,`y` offset the centre, `depth` is how far it stands off the plaster.
func _panel(room: Dictionary, a: Dictionary, x: float, y: float, width: float, height: float, depth: float, colour: Color) -> void:
	var centre: Vector3 = a.at + a.t * x + Vector3.UP * y + a.n * depth / 2.0
	_box(_decor_surface(room.band), centre, a.t * width / 2.0, Vector3.UP * height / 2.0, a.n * depth / 2.0, colour)


func _decor_surface(band: int) -> SurfaceTool:
	if not _decor.has(band):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_decor[band] = surface
	return _decor[band]


func _box(surface: SurfaceTool, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, colour: Color) -> void:
	surface.set_color(colour)
	var flip := ax.cross(ay).dot(az) < 0.0
	for face: Array in [[ax, ay, az], [-ax, az, ay], [ay, az, ax], [-ay, ax, az], [az, ax, ay], [-az, ay, ax]]:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var quad: Array = [c + n - u - v, c + n + u - v, c + n + u + v, c + n - u + v]
		# Godot front faces wind clockwise seen from outside.
		for index: int in ([0, 1, 2, 0, 2, 3] if flip else [0, 2, 1, 0, 3, 2]):
			surface.add_vertex(quad[index])


func _commit_decor() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	for band: int in _decor:
		var surface: SurfaceTool = _decor[band]
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "WallDecor%d" % band
		mesh.mesh = surface.commit()
		mesh.material_override = material
		g._add(g._town, mesh)
		mesh.add_to_group("map_decor", true)


# --- Exterior ----------------------------------------------------------------------------------

func _plant_courts() -> void:
	for house_name: String in TREES:
		var house: Dictionary = g._houses[house_name]
		var spec: Array = house.spec
		var band: int = house.band
		var z0 := float(spec[1]) + 0.64
		var z1 := float(spec[2]) - 0.64
		var u0 := 0.18 if house.east else 0.39
		var u1 := 0.61 if house.east else 0.82
		var y: float = house.base
		var greenery: Node3D = g._container(house.node, "Greenery", Vector3.ZERO)
		rng.seed = hash(house_name)
		var trees: Array = TREES[house_name]
		for i in trees.size():
			var z := lerpf(z0, z1, (float(i) + 0.5) / float(trees.size()))
			for attempt in 8:
				var at: Vector3 = g._plot_point(band, rng.randf_range(0.34, 0.66) * (u1 - u0) + u0, y, z + rng.randf_range(-0.5, 0.5))
				if _clear_of_routes(at, 0.75) and _box_clear(at, 0.0, Vector2(0.5, 0.5), 2.2):
					_foliage(greenery, trees[i], at, true)
					_keep.append([at, at, 0.45])
					break
		var z := z0
		while z < z1:
			var u := u0
			while u < u1:
				var edge: Vector2 = g._edges(band, z)
				var jitter := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
				var at: Vector3 = g._plot_point(band, u, y, z) + jitter
				var border := u <= u0 + 0.03 or u >= u1 - 0.09 or z <= z0 + 0.3 or z >= z1 - 0.5
				if _clear_of_routes(at, 0.55) and rng.randf() < 0.72:
					var key: String = "bush_flowers" if rng.randf() < 0.3 else "bush"
					if not border:
						key = COURT_TUFTS[rng.randi() % COURT_TUFTS.size()]
					_foliage(greenery, key, at, false)
				u += 0.55 / maxf(1.0, edge.y - edge.x)
			z += 0.55


func _plant_streets() -> void:
	var greenery: Node3D = g._container(g._region, "StreetPlanting", Vector3.ZERO)
	rng.seed = 7
	for lane in 3:
		var rows: Array = g._layout.streets[lane]
		var z := float(rows[0][0]) + 0.6
		var end := float(rows[rows.size() - 1][0]) - 0.6
		while z < end:
			var road: Vector3 = g._street_at(lane, z)
			var half := float(_lane_width(lane, z)) / 2.0 - 0.07
			for side: float in [-1.0, 1.0]:
				if rng.randf() > 0.42:
					continue
				var from := Vector3(road.x + side * half, road.y + 0.9, z)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.2, WORLD_MASK))
				if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
					continue
				var at: Vector3 = hit.position
				if _clear_of_routes(at, 0.8):
					_foliage(greenery, STREET_TUFTS[rng.randi() % STREET_TUFTS.size()], at, false)
			z += 0.9
	# A potted plant beside some front doors.
	for door: Node3D in g.get_nodes_in_group("map_house_exit"):
		if rng.randf() > 0.4:
			continue
		var outward: Vector3 = Basis(Vector3.UP, door.rotation.y) * Vector3.BACK
		var along := outward.cross(Vector3.UP).normalized() * (0.86 if rng.randf() < 0.5 else -0.86)
		var at: Vector3 = door.position + along + outward * 0.2
		var key: String = POTS[rng.randi() % POTS.size()]
		if not _beside_lane(at):
			continue
		if _box_clear(at, 0.0, _size(key), 0.5) and _supported(at, _size(key) / 2.0, at.y):
			_instance(greenery, key, at, rng.randf() * TAU).add_to_group("map_furniture", true)


# True when `at` hugs a lane edge rather than the running line down its middle.
func _beside_lane(at: Vector3) -> bool:
	for lane in 3:
		var road: Vector3 = g._street_at(lane, at.z)
		var half := _lane_width(lane, at.z) / 2.0
		if absf(road.y - at.y) < 1.4 and absf(at.x - road.x) < half - 0.3:
			return false
	return true


func _lane_width(lane: int, z: float) -> float:
	var rows: Array = g._layout.streets[lane]
	for i in range(1, rows.size()):
		if z <= float(rows[i][0]):
			var t := inverse_lerp(float(rows[i - 1][0]), float(rows[i][0]), z)
			return lerpf(float(rows[i - 1][3]), float(rows[i][3]), t)
	return float(rows[rows.size() - 1][3])


func _plant_landmarks() -> void:
	var greenery: Node3D = g._container(g._region, "SquarePlanting", Vector3.ZERO)
	rng.seed = 11
	var spots := [
		["tree_palm_a", Vector3(-20, 8.2, -55.6)], ["tree_small_a", Vector3(-13, 8.2, -58.7)], ["tree_palm_b", Vector3(13, 8.2, -58.9)],
		["tree_palm_c", Vector3(20, 8.2, -55.4)], ["tree_small_b", Vector3(-26.5, 0.0, 33.4)], ["tree_common_b", Vector3(-17.5, 0.0, 33.5)],
		["tree_small_a", Vector3(17.5, 0.0, 33.4)], ["tree_common_a", Vector3(26.5, 0.0, 33.5)],
		["tree_palm_c", Vector3(-9.5, 0.0, 33.4)], ["tree_small_b", Vector3(9.5, 0.0, 33.4)],
	]
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		if _clear_of_routes(at, 0.8) and _box_clear(at, 0.0, Vector2(0.5, 0.5), 2.2):
			_foliage(greenery, spot[0], at, true)
			for i in 5:
				var offset := Vector3(rng.randf_range(-1.1, 1.1), 0.0, rng.randf_range(-1.1, 1.1))
				if offset.length() > 0.4 and _clear_of_routes(at + offset, 0.5):
					_foliage(greenery, ["bush", "fern", "flowers_a", "flowers_b", "grass_tall"][i], at + offset, false)


# Green the rock faces below the outer lots so the village edge is not bare stone.
func _plant_cliffs() -> void:
	var greenery: Node3D = g._container(g._region, "CliffPlanting", Vector3.ZERO)
	rng.seed = 13
	# A broken line of trees along the ridge behind the chapel, against the sky.
	var ridge_x := -26.0
	while ridge_x < 27.0:
		var from := Vector3(ridge_x + rng.randf_range(-1.0, 1.0), 30.0, rng.randf_range(-65.0, -61.5))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, WORLD_MASK))
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.2 and (hit.position as Vector3).y > 5.0:
			_foliage(greenery, ["tree_palm_a", "tree_palm_b", "tree_small_a", "tree_common_b"][rng.randi() % 4], hit.position, false)
		ridge_x += rng.randf_range(3.0, 6.0)
	for band: int in [0, 3]:
		var side := -1.0 if band == 0 else 1.0
		var edge_rows: Array = g._layout.edges[0 if band == 0 else 1]
		var z := float(edge_rows[0][0]) + 1.5
		var end := float(edge_rows[edge_rows.size() - 1][0]) - 1.5
		while z < end:
			var edge: Vector2 = g._edges(band, z)
			var x: float = (edge.x if band == 0 else edge.y) + side * rng.randf_range(1.0, 3.6)
			var from := Vector3(x, 14.0, z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 18.0, WORLD_MASK))
			# WHY: the bluffs are steep (normal y near 0.3); plants cling to them like coastal scrub.
			if not hit.is_empty() and (hit.normal as Vector3).y > 0.22 and (hit.position as Vector3).y > -1.4:
				var at: Vector3 = hit.position
				var roll := rng.randf()
				if roll < 0.45:
					_foliage(greenery, ["tree_small_a", "tree_small_b", "tree_palm_c", "tree_palm_b", "tree_common_b"][rng.randi() % 5], at, false)
				elif roll < 0.8:
					_foliage(greenery, "bush", at, false)
				else:
					_foliage(greenery, "grass_wisp", at, false)
			z += rng.randf_range(1.6, 3.2)


func _foliage(parent: Node3D, key: String, at: Vector3, collides: bool) -> void:
	var node := _instance(parent, key, at, rng.randf_range(0.0, TAU))
	if not collides and node is StaticBody3D:
		# Cliff trees can never be reached; dropping the body keeps the physics world small.
		(node as StaticBody3D).collision_layer = 0
	var variation := rng.randf_range(0.82, 1.18)
	node.scale = Vector3(variation, variation * rng.randf_range(0.92, 1.1), variation)
	node.add_to_group("map_foliage", true)
	_counts.foliage = int(_counts.get("foliage", 0)) + 1


# --- Vines -------------------------------------------------------------------------------------

func _grow_vines() -> void:
	_vine_material = StandardMaterial3D.new()
	_vine_material.vertex_color_use_as_albedo = true
	_vine_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vine_material.roughness = 1.0
	for house_name: String in g._houses:
		var house: Dictionary = g._houses[house_name]
		var spec: Array = house.spec
		var levels := int(spec[3])
		rng.seed = hash(house_name + "vine")
		if levels == 0:
			_vine_court(house)
			continue
		var sides: Array = [1.0 if house.east else 0.0]
		if house.band == 0:
			sides.append(0.0)
		elif house.band == 3:
			sides.append(1.0)
		var wall_height: float = float(house.spacing) * levels
		for side: float in sides:
			var count := 1 if (spec[2] - spec[1]) < 7.0 else 2
			for i in count:
				var z := _vine_site(house, side)
				if z != INF:
					_vine_facade(house, side, z, wall_height * rng.randf_range(0.5, 0.92))
	var added := 0
	for band: int in _vines:
		var surface: SurfaceTool = _vines[band]
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "Vines%d" % band
		mesh.mesh = surface.commit()
		mesh.material_override = _vine_material
		g._add(g._town, mesh)
		mesh.add_to_group("map_vines", true)
		added += mesh.mesh.get_faces().size() / 3
	_counts.vine_leaves = added / 2


func _vine_site(house: Dictionary, side: float) -> float:
	var z0 := float(house.spec[1]) + 0.5
	var z1 := float(house.spec[2]) - 0.5
	for attempt in 14:
		var z := rng.randf_range(z0, z1)
		var at: Vector3 = g._facade_point(house.band, side, z, 0.0, float(house.base))
		var near_shutter := false
		for shutter: float in [lerpf(z0 - 0.5, z1 + 0.5, 0.23), lerpf(z0 - 0.5, z1 + 0.5, 0.77)]:
			near_shutter = near_shutter or absf(z - shutter) < 0.62
		if not near_shutter and _clear_of_vine_routes(at):
			return z
	return INF


func _clear_of_vine_routes(at: Vector3) -> bool:
	for keep: Array in _keep:
		var a: Vector3 = keep[0]
		var b: Vector3 = keep[1]
		if keep.size() > 3 and Vector2(a.x, a.z).distance_to(Vector2(at.x, at.z)) < 1.25:
			return false
		if a.is_equal_approx(b) and Vector2(a.x, a.z).distance_to(Vector2(at.x, at.z)) < 0.95:
			return false
	return true


func _vine_facade(house: Dictionary, side: float, z: float, height: float) -> void:
	var outward := Vector3.RIGHT * (2.0 * side - 1.0)
	_vine(house.band, outward, height, func(offset: float, depth: float, h: float) -> Vector3:
		return g._facade_point(house.band, side, z + offset, depth, float(house.base) + h))


func _vine_court(house: Dictionary) -> void:
	var y: float = house.base
	for wall_z: float in [float(house.spec[1]) + 0.02, float(house.spec[2]) - 0.02]:
		var inward := 1.0 if wall_z < float(house.spec[1]) + 1.0 else -1.0
		var edge: Vector2 = g._edges(house.band, wall_z)
		var x := lerpf(edge.x, edge.y, rng.randf_range(0.3, 0.7))
		_vine(house.band, Vector3.BACK * inward, rng.randf_range(1.4, 2.3), func(offset: float, depth: float, h: float) -> Vector3:
			return Vector3(x + offset, y + h, wall_z + inward * depth))


func _vine(band: int, outward: Vector3, height: float, point: Callable) -> void:
	if not _vines.has(band):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_vines[band] = surface
	var surface: SurfaceTool = _vines[band]
	var drift := 0.0
	var h := 0.05
	var width := 0.22
	while h < height:
		drift += rng.randf_range(-0.09, 0.09)
		# Thins out toward the tip so the climber ends in a point instead of a flat top.
		var taper := clampf((height - h) / 0.8, 0.25, 1.0)
		var leaves := rng.randi_range(4, 7)
		for i in leaves:
			var offset := drift + rng.randf_range(-width, width) * taper
			var centre: Vector3 = point.call(offset, rng.randf_range(0.03, 0.09), h + rng.randf_range(-0.08, 0.08))
			var colour: Color = LEAF_COLOURS[rng.randi() % LEAF_COLOURS.size()]
			if rng.randf() < 0.05:
				colour = Color(0.78, 0.33, 0.42)
			_leaf(surface, centre, outward, rng.randf_range(0.04, 0.07), colour)
		h += rng.randf_range(0.1, 0.17)


func _leaf(surface: SurfaceTool, centre: Vector3, outward: Vector3, size: float, colour: Color) -> void:
	var spin := rng.randf() * TAU
	var up := Vector3(0.0, cos(spin), 0.0) + outward.cross(Vector3.UP) * sin(spin)
	var across := outward.cross(up).normalized()
	var tilt := outward * rng.randf_range(-0.03, 0.05)
	var corners := [centre + up * size * 1.25, centre + across * size * 0.7 + tilt, centre - up * size * 1.25,
		centre - across * size * 0.7 + tilt]
	surface.set_color(colour)
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.add_vertex(corners[index])


# --- Shared checks -----------------------------------------------------------------------------

func _collect_keep_outs() -> void:
	for group: String in ["map_house_exit", "map_room_opening"]:
		for marker: Node3D in g.get_nodes_in_group(group):
			_keep.append([marker.position, marker.position, 0.98])
	for marker: Node3D in g.get_nodes_in_group("map_stair_end"):
		_keep.append([marker.position, marker.position, 0.92])
	for marker: Node3D in g.get_nodes_in_group("map_walk_link"):
		_keep.append([marker.position, marker.get_meta("landing"), 0.66])
	for marker: Node3D in g.get_nodes_in_group("map_traversal"):
		# The fourth element marks a parkour route, which vines also stay away from.
		_keep.append([marker.get_meta("takeoff"), marker.get_meta("landing"), 0.7, true])
		_keep.append([marker.position, marker.position, 0.7, true])
	for group: String in ["hide_spot", "villager_spawn", "mage_spawn", "chicken_spawn"]:
		for marker: Node3D in g.get_nodes_in_group(group):
			_keep.append([marker.position, marker.position, 0.85])


func _clear_of_routes(at: Vector3, radius: float) -> bool:
	for keep: Array in _keep:
		var a: Vector3 = keep[0]
		var b: Vector3 = keep[1]
		if at.y < minf(a.y, b.y) - 1.3 or at.y > maxf(a.y, b.y) + 1.3:
			continue
		var closest := Geometry3D.get_closest_point_to_segment(at, a, b)
		var flat := Vector2(closest.x - at.x, closest.z - at.z)
		if flat.length() < radius + float(keep[2]):
			return false
	return true


func _box_clear(pos: Vector3, yaw: float, size: Vector2, height: float) -> bool:
	var shape := BoxShape3D.new()
	var tall := maxf(height - 0.14, 0.1)
	shape.size = Vector3(size.x, tall, size.y)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WORLD_MASK
	query.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * (0.1 + tall / 2.0))
	return space.intersect_shape(query, 1).is_empty()


func _supported(pos: Vector3, extent: Vector2, y: float) -> bool:
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
		var x := pos.x + corner.x * extent.x
		var z := pos.z + corner.y * extent.y
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x, y + 0.35, z), Vector3(x, y - 0.3, z), WORLD_MASK)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.85 or absf((hit.position as Vector3).y - y) > FLOOR_TOLERANCE:
			return false
	return true


func _scene(key: String) -> Node3D:
	if not _scenes.has(key):
		_scenes[key] = load(PROPS % key)
	return (_scenes[key] as PackedScene).instantiate() as Node3D


func _size(key: String) -> Vector2:
	var probe := _scene(key)
	var footprint: Vector2 = probe.get_meta("footprint")
	probe.free()
	return footprint


func _height(key: String) -> float:
	var probe := _scene(key)
	var value := float(probe.get_meta("height"))
	probe.free()
	return value


func _instance(parent: Node3D, key: String, pos: Vector3, yaw: float) -> Node3D:
	var node := _scene(key)
	node.position = pos
	node.rotation.y = yaw
	# Readable sibling names keep node paths, and so BreakableManager indices, stable and diffable.
	parent.add_child(node, true)
	node.owner = g._town
	return node
