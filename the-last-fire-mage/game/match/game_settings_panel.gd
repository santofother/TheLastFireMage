extends PanelContainer
## Host-only "GAME SETTINGS" overlay opened from the lobby. Owner: menu-testing.
## One percentage slider per GameSettings.DEFS entry (100 % = current balance). Emits `changed(mults)` on edit.
## NET: UI only; MatchManager (server) turns `changed` into a broadcast.

signal changed(mults: Dictionary)

const MIN_PCT := 25.0
const MAX_PCT := 300.0

var _sliders := {}
var _labels := {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -380
	offset_right = 380
	offset_top = -340
	offset_bottom = 340
	add_theme_stylebox_override("panel", UiStyle.panel())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(UiStyle.heading("GAME SETTINGS", 36))
	v.add_child(UiStyle.caption("100% = normal balance. Applies to the next round, for everyone."))
	for def in GameSettings.DEFS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := Label.new()
		name_label.text = def["label"]
		name_label.custom_minimum_size.x = 250
		var s := HSlider.new()
		s.min_value = MIN_PCT
		s.max_value = MAX_PCT
		s.step = 5
		s.value = 100
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size = Vector2(240, 28)
		var pct := Label.new()
		pct.custom_minimum_size.x = 64
		pct.text = "100%"
		var id: String = def["id"]
		s.value_changed.connect(func(val: float) -> void:
			pct.text = "%d%%" % int(val)
			changed.emit(_collect()))
		_sliders[id] = s
		_labels[id] = pct
		row.add_child(name_label)
		row.add_child(s)
		row.add_child(pct)
		v.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var reset := Button.new()
	reset.text = "RESET ALL TO 100%"
	reset.pressed.connect(func() -> void:
		for id in _sliders:
			(_sliders[id] as HSlider).value = 100)
	var close := Button.new()
	close.text = "DONE"
	close.pressed.connect(func() -> void: visible = false)
	UiStyle.style_primary(close, 20)
	buttons.add_child(reset)
	buttons.add_child(close)
	v.add_child(buttons)
	visible = false


## Mirrors externally set factors into the sliders without emitting `changed`.
func show_mults(m: Dictionary) -> void:
	for id in _sliders:
		var pct := int(round(float(m.get(id, 1.0)) * 100.0))
		(_sliders[id] as HSlider).set_value_no_signal(pct)
		(_labels[id] as Label).text = "%d%%" % pct


func _collect() -> Dictionary:
	var d := {}
	for id in _sliders:
		var f := (_sliders[id] as HSlider).value / 100.0
		if not is_equal_approx(f, 1.0):
			d[id] = f
	return d
