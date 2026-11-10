class_name Tuning
extends Resource
## Base class for every system's tuning resource. Owner: S02.
##
## Pattern (CONTRACT):
## - Each system has `game/<sys>/<sys>_tuning.gd` (`class_name XxxTuning extends Tuning`, `@export` vars with
##   the GDD defaults and `# TUNE:` comments) and `game/<sys>/tuning_<sys>.tres` (an instance of it).
## - Load with `XxxTuning.load_tuning("res://game/<sys>/tuning_<sys>.tres", "<section>")`: it returns a
##   private copy with command-line overrides applied, so tests can shorten timers without editing files.
## - Override syntax (after `--`): `--tune=match.hunt_time=10,match.head_start_time=2,power.per_chicken=5`


## Loads a tuning resource, duplicates it, and applies `--tune=` overrides for `section`.
static func load_tuning(path: String, section: String) -> Tuning:
	var res := load(path) as Tuning
	if res == null:
		push_error("[Tuning] could not load %s" % path)
		return null
	var copy := res.duplicate(true) as Tuning
	copy.apply_overrides(section, _cli_tune_arg())
	GameSettings.register(copy) # host lobby balance multipliers
	return copy


## Applies "section.key=value,section.key=value" overrides. Values are converted to the property's type.
func apply_overrides(section: String, spec: String) -> void:
	if spec.is_empty():
		return
	for pair in spec.split(",", false):
		var kv := pair.split("=", true, 1)
		if kv.size() != 2:
			continue
		var key := kv[0].strip_edges()
		if not key.begins_with(section + "."):
			continue
		var prop := key.substr(section.length() + 1)
		var current: Variant = get(prop)
		if current == null:
			push_warning("[Tuning] %s has no property '%s'" % [section, prop])
			continue
		set(prop, type_convert(str_to_var(kv[1].strip_edges()), typeof(current)))
		print("[Tuning] %s.%s = %s" % [section, prop, str(get(prop))])


static func _cli_tune_arg() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var nm: Node = tree.root.get_node_or_null(^"NetworkManager") if tree else null
	return String(nm.get(&"args").get("tune", "")) if nm else ""
