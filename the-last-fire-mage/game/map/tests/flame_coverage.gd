extends RefCounted
## Samples saved collision for flame coverage, including short crouch pockets. Owner: S05.
## Public API: audit() returns uncovered positions for the map regression.
## NET: offline. Actual damage is exercised separately by map_test.gd.

# The spacing is smaller than the clearance left by the narrowest intended doorway.
const STEP := 0.55
const COLUMNS := 134
const ROWS := 260
const CORNER := Vector3(-36.55, 0, -66.20)
const BLOCKERS := 1 | 16

var _space: PhysicsDirectSpaceState3D
var _cells: Array[PackedInt32Array] = []
var _positions := PackedVector3Array()
var _walkable := PackedByteArray()
var _reachable := PackedByteArray()
var _indices := PackedInt32Array()
var _crates: Array[AABB]
var _probe := PhysicsShapeQueryParameters3D.new()


## Flood mage-sized walkable collision from public starts and tested parkour landings.
## Check each sampled villager surface for a distinct in-range and unoccluded attack origin.
func audit(space: PhysicsDirectSpaceState3D, anchor: Vector3, links: Array[PackedVector3Array], crates: Array[AABB], tuning: MageCombatTuning) -> PackedVector3Array:
	_space = space
	_crates = crates
	_probe.collision_mask = BLOCKERS
	_cells.resize(COLUMNS * ROWS)
	var mage := preload("res://game/player/tuning_mage.tres") as PlayerTuning
	var villager := preload("res://game/player/tuning_villager.tres") as PlayerTuning
	var mage_shape := _capsule(mage.radius, mage.crouch_height)
	var villager_shape := _capsule(villager.radius, villager.crouch_height)
	for row in ROWS:
		for column in COLUMNS:
			_sample(row, column, mage_shape, villager_shape)
	var sample_count := _positions.size()
	_sample_link_ends(links, mage_shape)
	_reachable.resize(_positions.size())
	_flood(anchor, links, mage_shape)
	var missing := PackedVector3Array()
	var half_cone := deg_to_rad(tuning.wave_angle_deg / 2.0)
	for i in sample_count:
		if not _can_hit(_positions[i], _indices[i], tuning.wave_range, mage.pitch_min - half_cone, mage.pitch_max + half_cone):
			missing.append(_positions[i])
	print("[Map] Flame coverage at %.2f m spacing: %d villager samples, %d within Fire Wave coverage" %
		[STEP, sample_count, sample_count - missing.size()])
	return missing


func _sample(row: int, column: int, mage: CapsuleShape3D, villager: CapsuleShape3D) -> void:
	var cell := row * COLUMNS + column
	var point := CORNER + Vector3(column * STEP, 0, row * STEP)
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20, point - Vector3.UP * 2.8, BLOCKERS)
	var excluded: Array[RID] = []
	while true:
		var hit := _space.intersect_ray(ray)
		if hit.is_empty():
			return
		excluded.append(hit.rid)
		ray.exclude = excluded
		var feet: Vector3 = hit.position
		ray.from.y = feet.y - 0.025
		if (hit.normal as Vector3).y < 0.707 or _inside_crate(feet) or not _clear(feet, villager):
			continue
		_cells[cell].append(_positions.size())
		_positions.append(feet)
		_indices.append(cell)
		_walkable.append(int(_clear(feet, mage)))


func _inside_crate(feet: Vector3) -> bool:
	# A hollow CSG triangle collider can report a capsule entirely inside its solid-looking mesh as clear.
	for crate in _crates:
		if crate.has_point(feet + Vector3.UP * 0.1):
			return true
	return false


func _sample_link_ends(links: Array[PackedVector3Array], mage: CapsuleShape3D) -> void:
	# A ledge can fit the mage yet fall between grid points. Include the positions
	# from successful physics traversals as extra vertices in the reachability graph.
	var added: Dictionary[Vector3, bool] = {}
	for link in links:
		for end in link:
			var column := roundi((end.x - CORNER.x) / STEP)
			var row := roundi((end.z - CORNER.z) / STEP)
			if column < 0 or column >= COLUMNS or row < 0 or row >= ROWS:
				continue
			var floor := _space.intersect_ray(PhysicsRayQueryParameters3D.create(
				end + Vector3.UP * 0.12, end - Vector3.UP * 0.24, BLOCKERS))
			if floor.is_empty() or (floor.normal as Vector3).y < 0.707:
				continue
			var feet: Vector3 = floor.position
			# WHY: the physics run already stood here. On an angled facade the static capsule probe clips the wall.
			if added.has(feet) or _inside_crate(feet):
				continue
			added[feet] = true
			var cell := row * COLUMNS + column
			_cells[cell].append(_positions.size())
			_positions.append(feet)
			_indices.append(cell)
			_walkable.append(1)


func _nearby(anchor: Vector3, mage: CapsuleShape3D) -> PackedInt32Array:
	var nearby := PackedInt32Array()
	var column := roundi((anchor.x - CORNER.x) / STEP)
	var row := roundi((anchor.z - CORNER.z) / STEP)
	for z in range(maxi(row - 2, 0), mini(row + 3, ROWS)):
		for x in range(maxi(column - 2, 0), mini(column + 3, COLUMNS)):
			for id in _cells[z * COLUMNS + x]:
				if _walkable[id] and _positions[id].distance_to(anchor) < 1.20 and _joins(anchor, _positions[id], mage):
					nearby.append(id)
	return nearby


func _joins(a: Vector3, b: Vector3, mage: CapsuleShape3D) -> bool:
	if _flat_length(a - b) < 0.02:
		return true
	if absf(a.y - b.y) > _flat_length(a - b) * 1.02 + 0.08:
		return false
	var steps := maxi(2, ceili(a.distance_to(b) / 0.19))
	for j in range(1, steps):
		var p := a.lerp(b, float(j) / steps)
		var floor := _space.intersect_ray(PhysicsRayQueryParameters3D.create(
			p + Vector3.UP * 0.16, p - Vector3.UP * 0.16, BLOCKERS))
		if floor.is_empty() or (floor.normal as Vector3).y < 0.69 or not _clear(floor.position, mage):
			return false
	return true


func _flood(anchor: Vector3, links: Array[PackedVector3Array], mage: CapsuleShape3D) -> void:
	var explicit: Dictionary[int, PackedInt32Array] = {}
	for link in links:
		var ends := [_nearby(link[0], mage), _nearby(link[1], mage)]
		for side in 2:
			for id: int in ends[side]:
				if not explicit.has(id):
					explicit[id] = PackedInt32Array()
				explicit[id].append_array(ends[1 - side])
	var queue := _nearby(anchor, mage)
	for id in queue:
		_reachable[id] = 1
	var cursor := 0
	while cursor < queue.size():
		var source := queue[cursor]
		var cell := _indices[source]
		cursor += 1
		if explicit.has(source):
			for dest in explicit[source]:
				if not _reachable[dest]:
					_reachable[dest] = 1
					queue.append(dest)
		for step: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
				Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
			var column := cell % COLUMNS + step.x
			var row := cell / COLUMNS + step.y
			if column < 0 or column >= COLUMNS or row < 0 or row >= ROWS:
				continue
			var neighbour := row * COLUMNS + column
			for dest in _cells[neighbour]:
				var a := _positions[source]
				var b := _positions[dest]
				if not _walkable[dest] or _reachable[dest] or absf(a.y - b.y) > _flat_length(a - b) * 0.94:
					continue
				var midpoint := a.lerp(b, 0.5)
				var floor := _space.intersect_ray(PhysicsRayQueryParameters3D.create(
					midpoint + Vector3.UP * 0.12, midpoint - Vector3.UP * 0.12, BLOCKERS))
				if floor.is_empty() or not _clear(floor.position, mage):
					continue
				_reachable[dest] = 1
				queue.append(dest)



func _can_hit(feet: Vector3, cell: int, reach: float, min_pitch: float, max_pitch: float) -> bool:
	var radius := ceili(reach / STEP)
	var row := cell / COLUMNS
	var column := cell % COLUMNS
	var target := feet + Vector3.UP * 0.4
	# Fast path: most positions can be hit from a nearby position on the same floor.
	for distance in range(1, radius + 1):
		for dz in range(-distance, distance + 1):
			var other_row := row + dz
			if other_row < 0 or other_row >= ROWS:
				continue
			for dx in range(-distance, distance + 1):
				var other_column := column + dx
				if other_column < 0 or other_column >= COLUMNS or maxi(absi(dx), absi(dz)) != distance:
					continue
				for source in _cells[other_row * COLUMNS + other_column]:
					if not _reachable[source]:
						continue
					var origin := _positions[source] + Vector3.UP * 0.65
					var offset := target - origin
					if offset.length() > reach or _flat_length(offset) < 0.67:
						continue
					# Match the player's upward and downward camera pitch limits.
					var pitch := asin(offset.normalized().y)
					if pitch < min_pitch or pitch > max_pitch:
						continue
					if _space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target, BLOCKERS)).is_empty():
						return true
	return false


func _clear(feet: Vector3, capsule: CapsuleShape3D) -> bool:
	_probe.shape = capsule
	_probe.transform.origin = feet + Vector3.UP * (capsule.height / 2 + 0.056)
	return _space.intersect_shape(_probe, 1).is_empty()


func _capsule(radius: float, height: float) -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	return shape


func _flat_length(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
