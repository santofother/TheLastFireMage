extends SceneTree
## Writes the seamless cobblestone textures used by the "paving" material. Owner: playtest batch.
## Run once after changing the look: Godot --headless --path the-last-fire-mage --script ../tools/map/build_cobble.gd -- --no-steam
## NET: offline authoring tool.

const SIZE := 512
const CELLS := 11 # TUNE: stones across one tile
const OUT := "res://game/map/textures/cobble_%s.png"
const STONES := [Color(0.60, 0.57, 0.52), Color(0.52, 0.50, 0.47), Color(0.68, 0.63, 0.55), Color(0.46, 0.44, 0.43),
	Color(0.63, 0.55, 0.47), Color(0.56, 0.56, 0.54)]
const MORTAR := Color(0.20, 0.18, 0.15)


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var points: Array[Vector2] = []
	var tints: Array[Color] = []
	for i in CELLS * CELLS:
		points.append(Vector2(rng.randf_range(0.18, 0.82), rng.randf_range(0.18, 0.82)))
		var tint: Color = STONES[rng.randi() % STONES.size()]
		tints.append(tint.lightened(rng.randf_range(-0.08, 0.1)))
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var heights := PackedFloat32Array()
	heights.resize(SIZE * SIZE)
	var cell_size := float(SIZE) / CELLS
	for y in SIZE:
		for x in SIZE:
			var at := Vector2(x, y) / cell_size
			var base := Vector2i(floori(at.x), floori(at.y))
			var f1 := INF
			var f2 := INF
			var nearest := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var cell := base + Vector2i(dx, dy)
					var index := posmod(cell.x, CELLS) + posmod(cell.y, CELLS) * CELLS
					var d := at.distance_to(Vector2(cell) + points[index])
					if d < f1:
						f2 = f1
						f1 = d
						nearest = index
					elif d < f2:
						f2 = d
			var edge := smoothstep(0.03, 0.17, f2 - f1)
			var speck := rng.randf_range(-0.035, 0.035)
			albedo.set_pixel(x, y, MORTAR.lerp(tints[nearest].darkened(0.28 * (1.0 - smoothstep(0.1, 0.4, f2 - f1))), edge)
				+ Color(speck, speck, speck, 0.0))
			heights[y * SIZE + x] = edge * (0.75 + 0.25 * (1.0 - clampf(f1, 0.0, 1.0)))
	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var dx: float = heights[y * SIZE + posmod(x + 1, SIZE)] - heights[y * SIZE + posmod(x - 1, SIZE)]
			var dy: float = heights[posmod(y + 1, SIZE) * SIZE + x] - heights[posmod(y - 1, SIZE) * SIZE + x]
			var n := Vector3(-dx * 3.2, -dy * 3.2, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://game/map/textures"))
	albedo.save_png(OUT % "albedo")
	normal.save_png(OUT % "normal")
	print("[Map] Wrote cobble textures")
	quit()
