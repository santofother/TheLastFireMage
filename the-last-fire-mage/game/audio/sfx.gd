class_name Sfx
extends RefCounted
## Static helpers to play sound cues by NAME (see docs/audio/CUE_SHEET.md). Owner: S18. NET: local audio only,
## every peer plays its own sounds; nothing here is networked.
##
## Public API:
## - `Sfx.play_3d(cue, pos, bus := &"SFX", range_m := 0.0, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D`
##   one-shot at a world position (frees itself). `range_m` > 0 sets `max_distance` (audible range).
## - `Sfx.play_2d(cue, bus := &"UI", volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer` non-positional one-shot.
## - `Sfx.play_ui(cue)` = play_2d on the UI bus (menus call this).
## - `Sfx.attach_loop(node, cue, bus := &"SFX", range_m := 0.0) -> AudioStreamPlayer3D` looping child of `node`.
## - `Sfx.make_3d(cue, bus)` an unplayed configured player (callers parent it themselves).
## - `Sfx.set_base_db(player, db)` volume that keeps the director's occlusion offset applied on top.
## - `Sfx.headless` true under `--headless`: nodes are created and configured, `play()` is skipped.
## Unknown cue = one `push_warning` per cue, returns null (callers must null-check). Never crashes.

const BANK_PATH := "res://game/audio/sound_bank.tres"

## True when running without a display (tests/servers): logic runs, real playback is skipped.
static var headless := DisplayServer.get_name() == "headless"
## Parent for one-shots (the AudioDirector sets itself). Falls back to the scene root.
static var root: Node
## Spatial players the director may occlude (one-shots and loops). Freed ones are pruned by the director.
static var tracked: Array[AudioStreamPlayer3D] = []

static var _bank: SoundBank
static var _warned := {}


## The loaded bank (loaded once).
static func bank() -> SoundBank:
	if _bank == null:
		_bank = load(BANK_PATH) as SoundBank
		if _bank == null:
			push_error("[Audio] could not load %s" % BANK_PATH)
			_bank = SoundBank.new()
	return _bank


## Stream for a cue, or null with a one-time warning.
static func stream(cue: StringName) -> AudioStream:
	var s := bank().get_stream(cue)
	if s == null and not _warned.has(cue):
		_warned[cue] = true
		push_warning("[Audio] unknown cue '%s'" % cue)
	return s


## A configured, unparented, unplayed 3D player (null for an unknown cue).
static func make_3d(cue: StringName, bus: StringName = &"SFX", range_m: float = 0.0) -> AudioStreamPlayer3D:
	var s := stream(cue)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.name = "Sfx_%s" % cue
	p.stream = s
	p.bus = bus
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if range_m > 0.0:
		p.max_distance = range_m
		p.unit_size = maxf(1.0, range_m * 0.25) # TUNE: loudness falls off over the first quarter of the range
	p.attenuation_filter_cutoff_hz = 20500.0 # director lowers it when occluded
	p.set_meta(&"base_db", 0.0)
	tracked.append(p)
	return p


## One-shot at `pos`. Frees itself when done.
static func play_3d(cue: StringName, pos: Vector3, bus: StringName = &"SFX", range_m: float = 0.0,
		volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var p := make_3d(cue, bus, range_m)
	var parent := _parent()
	if p == null or parent == null:
		return p
	parent.add_child(p)
	p.global_position = pos
	p.pitch_scale = pitch
	set_base_db(p, volume_db)
	_start_one_shot(p)
	return p


## Non-positional one-shot (stingers, UI, local-only cues).
static func play_2d(cue: StringName, bus: StringName = &"UI", volume_db: float = 0.0,
		pitch: float = 1.0) -> AudioStreamPlayer:
	var s := stream(cue)
	var parent := _parent()
	if s == null or parent == null:
		return null
	var p := AudioStreamPlayer.new()
	p.name = "Sfx2D_%s" % cue
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	_start_one_shot(p)
	return p


## UI click/confirm etc. on the UI bus.
static func play_ui(cue: StringName) -> AudioStreamPlayer:
	return play_2d(cue, &"UI")


## Looping 3D child of `node` (starts playing; free it or call stop() to end it).
static func attach_loop(node: Node, cue: StringName, bus: StringName = &"SFX",
		range_m: float = 0.0) -> AudioStreamPlayer3D:
	var p := make_3d(cue, bus, range_m)
	if p == null or node == null:
		return p
	p.name = "Loop_%s" % cue
	node.add_child(p)
	if not headless:
		p.play()
	return p


## Set a player's own volume; the director adds its occlusion offset (meta `occl_db`) on top.
static func set_base_db(p: AudioStreamPlayer3D, db: float) -> void:
	p.set_meta(&"base_db", db)
	p.volume_db = db + float(p.get_meta(&"occl_db", 0.0))


## Play (or in headless just schedule the free of) a one-shot.
static func _start_one_shot(p: Node) -> void:
	if headless:
		p.queue_free.call_deferred()
		return
	p.finished.connect(p.queue_free)
	p.call(&"play")


static func _parent() -> Node:
	if is_instance_valid(root):
		return root
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree else null
