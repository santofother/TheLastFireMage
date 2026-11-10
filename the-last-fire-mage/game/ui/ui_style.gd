class_name UiStyle
extends RefCounted
## Shared look for the main menu and lobby, matched to concept-art/ui (plum panels, gold trim, serif caps,
## glowing orange primary button, parchment secondary buttons). Owner: menu/lobby UI.
## NET: local only. All static helpers; no state besides cached fonts.
## Public API: `title_font()`, `body_font()`, `italic_font()`, `panel()`, `card()`, `style_primary(b)`,
## `style_secondary(b)`, `style_dark(b)`, `style_arrow(b)`, `style_field(c)`, `heading(text, size)`,
## `ornament(text)`, `footer(text)`.

const GOLD := Color("f3cf86")
const GOLD_DARK := Color("b98745")
const PLUM := Color("3a1a2bf0")
const PLUM_DEEP := Color("2a1220")
const CREAM := Color("f2e3c4")
const INK := Color("341a12")

static var _title: Font
static var _body: Font
static var _italic: Font


## Engraved serif caps for titles and buttons (system font with fallbacks; no bundled font file).
static func title_font() -> Font:
	if _title == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino", "Palatino Linotype",
			"Book Antiqua", "Georgia", "Times New Roman", "serif"])
		f.font_weight = 700
		_title = f
	return _title


static func body_font() -> Font:
	if _body == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Palatino", "Palatino Linotype", "Book Antiqua", "Georgia", "serif"])
		f.font_weight = 600
		_body = f
	return _body


static func italic_font() -> Font:
	if _italic == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Palatino", "Palatino Linotype", "Book Antiqua", "Georgia", "serif"])
		f.font_italic = true
		_italic = f
	return _italic


## Big plum panel with a double gold frame and a soft drop shadow.
static func panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PLUM
	s.border_color = GOLD_DARK
	s.set_border_width_all(3)
	s.set_corner_radius_all(14)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	s.set_content_margin_all(26)
	s.anti_aliasing = true
	return s


## Inset player slot card; `filled` slots get a brighter gold edge.
static func card(filled: bool, highlight := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("4a2134") if filled else Color("31162399")
	s.border_color = GOLD if highlight else (GOLD_DARK if filled else Color("8a5d3b"))
	s.set_border_width_all(3 if highlight else 2)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(10)
	if highlight:
		s.shadow_color = Color("ffb04a55")
		s.shadow_size = 8
	return s


static func _box(bg: Color, border: Color, width: int, radius: int, glow: Color = Color.TRANSPARENT,
		glow_size := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = glow
	s.shadow_size = glow_size
	s.anti_aliasing = true
	return s


static func _set_states(b: Button, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox,
		font: Color, font_hover: Color, font_size: int) -> void:
	b.add_theme_stylebox_override(&"normal", normal)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", pressed)
	b.add_theme_stylebox_override(&"disabled", disabled)
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	b.add_theme_color_override(&"font_color", font)
	b.add_theme_color_override(&"font_hover_color", font_hover)
	b.add_theme_color_override(&"font_pressed_color", font_hover)
	b.add_theme_color_override(&"font_focus_color", font)
	b.add_theme_color_override(&"font_disabled_color", Color(font, 0.45))
	b.add_theme_font_override(&"font", title_font())
	b.add_theme_font_size_override(&"font_size", font_size)


## Glowing orange call-to-action (HOST GAME, START ROUND).
static func style_primary(b: Button, font_size := 26) -> void:
	_set_states(b,
		_box(Color("b5481a"), Color("ffcf72"), 3, 12, Color("ff7a1f88"), 12),
		_box(Color("d65e1f"), Color("fff0b0"), 3, 12, Color("ff9a30cc"), 18),
		_box(Color("8f3814"), Color("ffcf72"), 3, 12, Color("ff7a1f66"), 6),
		_box(Color("6b3a2a"), Color("9b7a52"), 2, 12),
		Color("fff1c8"), Color.WHITE, font_size)


## Parchment button with dark ink text (JOIN GAME, SETTINGS, QUIT).
static func style_secondary(b: Button, font_size := 24) -> void:
	_set_states(b,
		_box(CREAM, GOLD_DARK, 3, 12, Color(0, 0, 0, 0.35), 4),
		_box(Color("fff3d9"), Color("ffb84a"), 3, 12, Color("ffae3c88"), 10),
		_box(Color("dcc9a4"), GOLD_DARK, 3, 12),
		_box(Color("a99a80"), Color("7d6a50"), 2, 12),
		INK, Color("5a200c"), font_size)


## Dark plum button with gold trim (INVITE FRIENDS, EXPLORE TOWN, Back).
static func style_dark(b: Button, font_size := 18) -> void:
	_set_states(b,
		_box(Color("3d1c2c"), GOLD_DARK, 2, 9, Color(0, 0, 0, 0.35), 4),
		_box(Color("5a2638"), GOLD, 2, 9, Color("ffae3c66"), 8),
		_box(Color("2c1220"), GOLD_DARK, 2, 9),
		_box(Color("2e1a24"), Color("6e5338"), 2, 9),
		Color("f6deb0"), Color.WHITE, font_size)


## Small gold square ‹ › arrows on selectors and slot cards.
static func style_arrow(b: Button) -> void:
	var normal := _box(Color("c8923f"), Color("ffe1a0"), 2, 6)
	normal.set_content_margin_all(4)
	var hover := _box(Color("e8ab4c"), Color.WHITE, 2, 6, Color("ffb04a88"), 6)
	hover.set_content_margin_all(4)
	var pressed := _box(Color("9c6c2c"), Color("ffe1a0"), 2, 6)
	pressed.set_content_margin_all(4)
	var disabled := _box(Color("5a4030"), Color("7d6a50"), 1, 6)
	disabled.set_content_margin_all(4)
	_set_states(b, normal, hover, pressed, disabled, Color("3a1a0c"), Color("1a0a04"), 18)
	b.custom_minimum_size = Vector2(28, 40)


## Line edits, option buttons and spin boxes in the gold-pill selector look.
static func style_field(c: Control) -> void:
	var box := _box(Color("2a1220"), GOLD_DARK, 2, 18)
	box.content_margin_left = 14
	var hover := _box(Color("3a1a2b"), GOLD, 2, 18)
	hover.content_margin_left = 14
	var target: Control = c
	if c is SpinBox:
		target = (c as SpinBox).get_line_edit()
		(c as SpinBox).alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in [&"normal", &"read_only", &"focus"]:
		target.add_theme_stylebox_override(state, hover if state == &"focus" else box)
	if target is Button:
		target.add_theme_stylebox_override(&"hover", hover)
		target.add_theme_stylebox_override(&"pressed", hover)
		target.add_theme_stylebox_override(&"disabled", box)
		target.add_theme_color_override(&"font_color", GOLD)
		target.add_theme_color_override(&"font_hover_color", Color.WHITE)
	target.add_theme_color_override(&"font_color", Color("ffe9bd"))
	target.add_theme_font_override(&"font", title_font())
	target.add_theme_font_size_override(&"font_size", 18)


## Gold engraved heading label.
static func heading(text: String, size := 40) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", title_font())
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", GOLD)
	l.add_theme_color_override(&"font_shadow_color", Color("1a0610cc"))
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", 3)
	l.add_theme_color_override(&"font_outline_color", Color("5a2a10"))
	l.add_theme_constant_override(&"outline_size", 4)
	return l


## Small caps label for selector captions (GAME MODE, BOTS).
static func caption(text: String, size := 17) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", title_font())
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color("f2dcae"))
	return l


## Thin gold divider like "◆ ━━━━ ◆" (or wraps text: "◆  2 / 6 PLAYERS  ◆").
static func ornament(text := "", size := 20) -> Label:
	var l := heading("◆  ────  %s  ────  ◆" % text if text != "" else "──────  ◆  ──────", size)
	l.add_theme_constant_override(&"outline_size", 0)
	l.add_theme_color_override(&"font_color", Color("e6b86a"))
	return l


## Italic flavour line at the bottom of a panel.
static func footer(text: String, size := 17) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override(&"font", italic_font())
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color("f0dcb8"))
	return l
