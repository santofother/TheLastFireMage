extends Node
## Graphics quality options for low-end machines. Owner: lower-settings branch.
## Public API: `values` (Dictionary of current options), `set_value(key, v)`, `apply_preset(i)`,
## `apply_all()`, `PRESET_NAMES`, signal `changed`. Saved to user://graphics.cfg (separate from the menu's
## settings.cfg so the two files never overwrite each other). Runs on every peer; purely local, never networked.
## CLI: `--gfx=default|medium|low|potato` forces a preset for that run without saving.
# CONTRACT: the DEFAULT preset must equal the game's original look (shadows high, no AA, 100% scale, lights+effects on).

signal changed

const SAVE_PATH := "user://graphics.cfg"
const PRESET_NAMES: Array[String] = ["Default", "Medium", "Low", "Potato"]
const SHADOW_NAMES: Array[String] = ["Off", "Low", "High"]
const AA_NAMES: Array[String] = ["Off", "FXAA"]
const FPS_NAMES: Array[String] = ["Unlimited", "60", "30"]
const FPS_VALUES: Array[int] = [0, 60, 30]
## Sun shadow atlas size per shadows level (index 0 unused). 4096 is Godot's default.
const SHADOW_ATLAS: Array[int] = [0, 1024, 4096]

## Preset table: shadows (0..2), aa (0..1), scale (%, 50..100), lights (bool), effects (bool), fps (index).
const PRESETS: Array[Dictionary] = [
	{"shadows": 2, "aa": 0, "scale": 100, "lights": true, "effects": true, "fps": 0},
	{"shadows": 1, "aa": 0, "scale": 85, "lights": true, "effects": true, "fps": 0},
	{"shadows": 0, "aa": 0, "scale": 70, "lights": false, "effects": true, "fps": 0},
	{"shadows": 0, "aa": 0, "scale": 50, "lights": false, "effects": false, "fps": 2},
]

var values: Dictionary = PRESETS[0].duplicate()
## Index into PRESET_NAMES, or -1 when the options no longer match any preset.
var preset: int = 0
var _save_enabled := true


func _ready() -> void:
	_load()
	if NetworkManager.args.has("gfx"):
		var i := PRESET_NAMES.map(func(n: String) -> String: return n.to_lower()).find(String(NetworkManager.args["gfx"]).to_lower())
		if i >= 0:
			values = PRESETS[i].duplicate()
			_save_enabled = false # WHY: CLI override is for this run only; don't clobber the player's saved choice.
	_update_preset_index()
	get_tree().node_added.connect(_on_node_added)
	apply_all()


## Set one option (key from PRESETS[0]) and apply + save.
func set_value(key: String, v: Variant) -> void:
	values[key] = v
	_update_preset_index()
	apply_all()
	_save()
	changed.emit()


## Apply one of PRESETS wholesale.
func apply_preset(i: int) -> void:
	if i < 0 or i >= PRESETS.size():
		return
	values = PRESETS[i].duplicate()
	_update_preset_index()
	apply_all()
	_save()
	changed.emit()


## Push every option to the renderer and to existing lights/particles.
func apply_all() -> void:
	var root := get_tree().root
	var shadows: int = values["shadows"]
	if shadows > 0:
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[shadows], true)
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(values["aa"]) == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	var s := float(values["scale"]) / 100.0
	root.scaling_3d_scale = s
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	Engine.max_fps = FPS_VALUES[int(values["fps"])]
	for n: Node in root.find_children("*", "Light3D", true, false):
		_apply_node(n)
	for n: Node in root.find_children("*", "GPUParticles3D", true, false):
		_apply_node(n)


func _on_node_added(n: Node) -> void:
	if n is Light3D or n is GPUParticles3D:
		_apply_node(n)


func _apply_node(n: Node) -> void:
	if n is DirectionalLight3D:
		n.shadow_enabled = int(values["shadows"]) > 0
	elif n is OmniLight3D or n is SpotLight3D:
		# WHY: small prop lights (torches/lanterns) are the main per-pixel light cost; hide, don't free, so High restores them.
		n.visible = bool(values["lights"])
	elif n is GPUParticles3D:
		n.amount_ratio = 1.0 if bool(values["effects"]) else 0.0


func _update_preset_index() -> void:
	preset = -1
	for i in PRESETS.size():
		if PRESETS[i].recursive_equal(values, 1):
			preset = i
			return


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key: String in PRESETS[0]:
		var d: Variant = PRESETS[0][key]
		var v: Variant = cfg.get_value("graphics", key, d)
		if typeof(v) == typeof(d):
			values[key] = v
	values["shadows"] = clampi(values["shadows"], 0, 2)
	values["aa"] = clampi(values["aa"], 0, 1)
	values["scale"] = clampi(values["scale"], 50, 100)
	values["fps"] = clampi(values["fps"], 0, FPS_VALUES.size() - 1)


func _save() -> void:
	if not _save_enabled:
		return
	var cfg := ConfigFile.new()
	for key: String in values:
		cfg.set_value("graphics", key, values[key])
	cfg.save(SAVE_PATH)
