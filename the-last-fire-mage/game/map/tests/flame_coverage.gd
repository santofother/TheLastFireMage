extends RefCounted
## Samples saved collision for flame coverage, including short crouch pockets. Owner: S05.
## Public API: audit() returns uncovered positions for the map regression.
## NET: offline. Actual damage is exercised separately by map_test.gd.

# The spacing is smaller than the clearance left by the narrowest intended doorway.
const STEP := 0.55
const COLUMNS := 122
const ROWS := 236
const CORNER := Vector3(-33.25, 0, -62.35)
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
	_reachable.resize(_positions.size())
	_flood(anchor, links, mage_shape)
	var missing := PackedVector3Array()
	var half_cone := deg_to_rad(tuning.wave_angle_deg / 2.0)
	for i in _positions.size():
		if not _can_hit(_positions[i], _indices[i], tuning.wave_range, mage.pitch_min - half_cone, mage.pitch_max + half_cone):
			missing.append(_positions[i])
	print("[Map] Flame coverage at %.2f m spacing: %d villager samples, %d within Fire Wave coverage" %
		[STEP, _positions.size(), _positions.size() - missing.size()])
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


func _nearby(anchor: Vector3) -> PackedInt32Array:
	var nearby := PackedInt32Array()
	var column := roundi((anchor.x - CORNER.x) / STEP)
	var row := roundi((anchor.z - CORNER.z) / STEP)
	for z in range(maxi(row - 1, 0), mini(row + 2, ROWS)):
		for x in range(maxi(column - 1, 0), mini(column + 2, COLUMNS)):
			for id in _cells[z * COLUMNS + x]:
				if _walkable[id] and _positions[id].distance_to(anchor) < 0.75:
					nearby.append(id)
	return nearby


func _flood(anchor: Vector3, links: Array[PackedVector3Array], mage: CapsuleShape3D) -> void:
	var explicit: Dictionary[int, PackedInt32Array] = {}
	for link in links:
		var ends := [_nearby(link[0]), _nearby(link[1])]
		for side in 2:
			for id: int in ends[side]:
				if not explicit.has(id):
					explicit[id] = PackedInt32Array()
				explicit[id].append_array(ends[1 - side])
	var queue := _nearby(anchor)
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
		for side: int in [-COLUMNS, COLUMNS, -1, 1]:
			var neighbour := cell + side
			if neighbour < 0 or neighbour >= _cells.size():
				continue
			for dest in _cells[neighbour]:
				var a := _positions[source]
				var b := _positions[dest]
				if not _walkable[dest] or _reachable[dest] or a.distance_to(b) > STEP + 0.16:
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
