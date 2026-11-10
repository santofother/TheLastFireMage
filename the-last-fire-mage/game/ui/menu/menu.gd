extends CanvasLayer
## Main menu + in-game Esc menu (same panel). UI is built in code to keep the .tscn tiny.

const SETTINGS_PATH := "user://settings.cfg"

var _root: CenterContainer
var _landing: Control
var _menu_backdrop: TextureRect
var _pages: Dictionary = {}
var _page_title: Label
var _name_edit: LineEdit
# FIX(S07, Codex): expose server bots for editor playtests without CLI arguments.
var _bot_count: SpinBox
var _mage_count: SpinBox
var _saved_skin := 0
var _steam_label: Label
var _host_steam_btn: Button
var _invite_btn: Button
var _refresh_btn: Button
var _lobby_list: ItemList
var _join_lobby_btn: Button
var _host_lan_btn: Button
var _join_ip_btn: Button
var _leave_btn: Button
var _port_edit: LineEdit
var _ip_edit: LineEdit
var _mic_option: OptionButton
var _ptt_check: CheckButton
var _mic_bar: ProgressBar
# FIX(S18, Claude): user asked for separate game / player-voice / mic volume settings.
var _volume_sliders: Dictionary = {} # &"game"|&"player"|&"mic" -> HSlider
var _status: Label
# lower-settings: graphics quality controls (Settings page); refreshed from GraphicsSettings.
var _gfx_preset: OptionButton
var _gfx_shadows: OptionButton
var _gfx_aa: OptionButton
var _gfx_fps: OptionButton
var _gfx_scale: HSlider
var _gfx_scale_lbl: Label
var _gfx_lights: CheckButton
var _gfx_effects: CheckButton


func _ready() -> void:
	_build_ui()
	_build_landing()
	_root.visible = false
	_load_settings()
	NetworkManager.status_changed.connect(_set_status)
	NetworkManager.connection_failed.connect(_set_status)
	NetworkManager.hosting_started.connect(_on_session_started)
	NetworkManager.connected.connect(_on_session_started)
	NetworkManager.session_ended.connect(_on_session_ended)
	SteamManager.status_changed.connect(_set_status)
	SteamManager.lobby_list_updated.connect(_on_lobby_list)
	_refresh_buttons()
	_auto_start_from_args.call_deferred() # after Main._ready has connected its signals


func _auto_start_from_args() -> void:
	var a := NetworkManager.args
	var port := int(a.get("port", NetworkManager.DEFAULT_PORT))
	if a.has("host"):
		NetworkManager.host_enet(port)
	elif a.has("join"):
		NetworkManager.join_enet(a["join"], port)


func _process(_delta: float) -> void:
	if _root.visible:
		_mic_bar.value = VoiceManager.mic_level * 100.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE and NetworkManager.is_in_session():
		if not _root.visible:
			_select_page("settings")
		_show(not _root.visible)
		get_viewport().set_input_as_handled()


func _show(on: bool) -> void:
	_root.visible = on
	_menu_backdrop.visible = on and not NetworkManager.is_in_session()
	if _landing:
		_landing.visible = false
	_refresh_buttons()
	if DisplayServer.get_name() != "headless":
		var match_system := GameEvents.system(&"match")
		var in_lobby: bool = match_system != null and match_system.phase == Enums.Phase.LOBBY and not match_system._exploring
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on or not NetworkManager.is_in_session() or in_lobby else Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- actions

func _apply_name() -> void:
	NetworkManager.local_name = _name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "Player"
	_save_settings()


func _on_host_steam() -> void:
	_apply_name()
	NetworkManager.args["bots"] = int(_bot_count.value)
	NetworkManager.args["mage-count"] = int(_mage_count.value)
	SteamManager.host_lobby()


func _on_join_lobby() -> void:
	var sel := _lobby_list.get_selected_items()
	if sel.is_empty():
		_set_status("Select a lobby first (or accept a Steam invite)")
		return
	_apply_name()
	SteamManager.join_lobby(_lobby_list.get_item_metadata(sel[0]))


func _on_host_lan() -> void:
	_apply_name()
	NetworkManager.args["bots"] = int(_bot_count.value)
	NetworkManager.args["mage-count"] = int(_mage_count.value)
	NetworkManager.host_enet(int(_port_edit.text))


func _on_join_ip() -> void:
	_apply_name()
	NetworkManager.join_enet(_ip_edit.text.strip_edges(), int(_port_edit.text))


func _on_leave() -> void:
	NetworkManager.leave("Left game")


func _on_session_started() -> void:
	_show(false)


func _on_session_ended(reason: String) -> void:
	_set_status(reason)
	_show(false)
	_landing.visible = true


func _on_lobby_list(lobbies: Array) -> void:
	_lobby_list.clear()
	for l in lobbies:
		var i := _lobby_list.add_item("%s  (%d players)" % [l["name"], l["members"]])
		_lobby_list.set_item_metadata(i, l["id"])


func _set_status(t: String) -> void:
	_status.text = t
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _host_steam_btn == null:
		return
	var in_s := NetworkManager.mode != NetworkManager.Mode.OFFLINE
	var steam := SteamManager.available
	_steam_label.text = "Steam: " + SteamManager.init_message
	for b in [_host_steam_btn, _refresh_btn, _join_lobby_btn]:
		b.disabled = in_s or not steam
	_host_lan_btn.disabled = in_s
	_join_ip_btn.disabled = in_s
	_name_edit.editable = not in_s
	_bot_count.editable = not in_s
	_mage_count.editable = not in_s
	_invite_btn.disabled = not (steam and SteamManager.lobby_id != 0)
	_leave_btn.visible = in_s


# ---------------------------------------------------------------- settings

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var default_name: String = SteamManager.persona_name if SteamManager.available else "Player"
	if NetworkManager.args.has("name"):
		default_name = NetworkManager.args["name"]
	_name_edit.text = cfg.get_value("player", "name", default_name) if not NetworkManager.args.has("name") else default_name
	NetworkManager.local_name = _name_edit.text
	_saved_skin = VillagerSkins.clamp_id(cfg.get_value("player", "villager", 0))
	# WHY: --villager is for tests and must not overwrite the choice saved in the player's settings.
	var skin: int = VillagerSkins.id_from_name(NetworkManager.args["villager"]) if NetworkManager.args.has("villager") else _saved_skin
	VillagerSkins.local = skin
	VoiceManager.push_to_talk = cfg.get_value("voice", "push_to_talk", true)
	_ptt_check.button_pressed = VoiceManager.push_to_talk
	for kind: StringName in _volume_sliders:
		var v := float(cfg.get_value("audio", String(kind) + "_volume", 1.0))
		AudioDirector.set_volume(kind, v)
		_volume_sliders[kind].set_value_no_signal(v * 100.0)
		_volume_sliders[kind].get_meta(&"pct").text = "%d%%" % roundi(v * 100.0)
	var dev: String = cfg.get_value("voice", "input_device", "Default")
	for i in _mic_option.item_count:
		if _mic_option.get_item_text(i) == dev:
			_mic_option.select(i)
			if dev != AudioServer.input_device:
				VoiceManager.set_input_device(dev)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", _name_edit.text)
	if not NetworkManager.args.has("villager"):
		_saved_skin = VillagerSkins.local
	cfg.set_value("player", "villager", _saved_skin)
	cfg.set_value("voice", "push_to_talk", VoiceManager.push_to_talk)
	cfg.set_value("voice", "input_device", AudioServer.input_device)
	for kind: StringName in _volume_sliders:
		cfg.set_value("audio", String(kind) + "_volume", _volume_sliders[kind].value / 100.0)
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------- UI construction

func _build_ui() -> void:
	_menu_backdrop = TextureRect.new()
	_menu_backdrop.texture = load("res://game/ui/art/village-background.png")
	_menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_menu_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_menu_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_backdrop.visible = false
	add_child(_menu_backdrop)
	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = _menu_theme()
	add_child(_root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	_page_title = UiStyle.heading("HOST GAME", 40)
	v.add_child(_page_title)
	v.add_child(UiStyle.ornament("", 16))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Player name"
	_name_edit.max_length = 20
	v.add_child(_row("Name", _name_edit))
	for key in ["host", "join", "settings"]:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 8)
		_pages[key] = section
		v.add_child(section)
	var host: VBoxContainer = _pages["host"]
	var hint := _label("Choose how friends will connect")
	hint.add_theme_color_override("font_color", Color("f6bd69"))
	host.add_child(hint)
	_mage_count = SpinBox.new()
	_mage_count.name = "MageCount"
	_mage_count.min_value = 1
	_mage_count.max_value = MatchManager.MAX_MAGES
	_mage_count.step = 1
	_mage_count.value = 1
	host.add_child(_row("Mages", _mage_count))

	_bot_count = SpinBox.new()
	_bot_count.name = "BotCount"
	_bot_count.min_value = 0
	_bot_count.max_value = NetworkManager.MAX_PLAYERS - 1
	_bot_count.step = 1
	_bot_count.value = clampi(int(NetworkManager.args.get("bots", 0)), 0, NetworkManager.MAX_PLAYERS - 1)
	host.add_child(_row("Bots", _bot_count))
	_steam_label = _label("")
	_steam_label.add_theme_color_override("font_color", Color("d9b98a"))
	_steam_label.add_theme_font_size_override("font_size", 15)
	host.add_child(_steam_label)
	_host_steam_btn = _button("Host Steam lobby", _on_host_steam)
	_host_lan_btn = _button("Host LAN", _on_host_lan)  # CONTRACT: bot_menu_test finds this by text
	UiStyle.style_primary(_host_steam_btn, 20)
	UiStyle.style_primary(_host_lan_btn, 20)
	_host_steam_btn.custom_minimum_size.y = 50
	_host_lan_btn.custom_minimum_size.y = 50
	host.add_child(_hbox([_host_steam_btn, _host_lan_btn]))
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	var port_row := _row("LAN port", _port_edit)
	v.add_child(port_row)
	v.move_child(port_row, 2)
	_invite_btn = _button("INVITE STEAM FRIENDS", SteamManager.invite_friends)
	host.add_child(_invite_btn)
	var join: VBoxContainer = _pages["join"]
	_refresh_btn = _button("REFRESH LOBBIES", SteamManager.request_lobby_list)
	_join_lobby_btn = _button("JOIN SELECTED", _on_join_lobby)
	join.add_child(_hbox([_refresh_btn, _join_lobby_btn]))
	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 140)
	var list_box := UiStyle.card(false)
	_lobby_list.add_theme_stylebox_override("panel", list_box)
	_lobby_list.add_theme_font_override("font", UiStyle.body_font())
	_lobby_list.add_theme_color_override("font_color", Color("f2dcae"))
	_lobby_list.item_activated.connect(func(_i): _on_join_lobby())
	join.add_child(_lobby_list)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_ip_btn = _button("JOIN IP", _on_join_ip)
	UiStyle.style_primary(_join_ip_btn, 18)
	join.add_child(_hbox([_ip_edit, _join_ip_btn]))
	var join_port := UiStyle.footer("Enter a host address and the LAN port above.", 15)
	join.add_child(join_port)
	var settings: VBoxContainer = _pages["settings"]
	_mic_option = OptionButton.new()
	for d in VoiceManager.get_input_devices():
		_mic_option.add_item(d)
	_mic_option.item_selected.connect(func(i):
		VoiceManager.set_input_device(_mic_option.get_item_text(i))
		_save_settings())
	settings.add_child(_row("Mic", _mic_option))
	_ptt_check = CheckButton.new()
	_ptt_check.text = "Push-to-talk (hold V)"
	_ptt_check.toggled.connect(func(on):
		VoiceManager.push_to_talk = on
		_save_settings())
	settings.add_child(_ptt_check)
	_mic_bar = ProgressBar.new()
	_mic_bar.show_percentage = false
	_mic_bar.custom_minimum_size = Vector2(0, 14)
	settings.add_child(_row("Mic level", _mic_bar))
	settings.add_child(_volume_row("Game", &"game", "Music, effects and ambience"))
	settings.add_child(_volume_row("Players", &"player", "Other players' voices"))
	settings.add_child(_volume_row("My mic", &"mic", "How loud others hear you"))
	_build_graphics(settings)
	var back := _button("BACK", func():
		_show(false)
		if not NetworkManager.is_in_session():
			_landing.visible = true)
	back.name = "BackButton"
	v.add_child(back)
	_leave_btn = _button("LEAVE GAME", _on_leave)
	v.add_child(_leave_btn)
	_status = UiStyle.footer("Ready", 15)
	v.add_child(_status)
	for field: Control in [_name_edit, _port_edit, _ip_edit, _mage_count, _bot_count, _mic_option]:
		UiStyle.style_field(field)
	_select_page("host")


func _select_page(page: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page
	_page_title.text = {"host": "HOST GAME", "join": "JOIN GAME", "settings": "SETTINGS"}.get(page, "MENU")


func _open_page(page: String) -> void:
	_select_page(page)
	_show(true)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 40
	UiStyle.style_dark(b, 17)
	b.pressed.connect(cb)
	return b


## Default font/colours for every label and control in the menu (serif, warm cream).
func _menu_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UiStyle.body_font()
	t.default_font_size = 18
	t.set_color(&"font_color", &"Label", Color("f2dcae"))
	t.set_color(&"font_color", &"CheckButton", Color("f2dcae"))
	t.set_color(&"font_hover_color", &"CheckButton", Color.WHITE)
	return t


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _hbox(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	for c in children:
		h.add_child(c)
	return h


## Volume slider 0..max % (100 % = default) for AudioDirector.set_volume(kind); saved to settings.cfg on change.
func _volume_row(caption: String, kind: StringName, tip: String) -> HBoxContainer:
	var slider := HSlider.new()
	slider.name = "Volume_%s" % kind
	slider.min_value = 0.0
	slider.max_value = float(AudioDirector.VOLUME_MAX[kind]) * 100.0
	slider.step = 5.0
	slider.value = 100.0
	slider.tooltip_text = tip
	slider.custom_minimum_size = Vector2(160, 0)
	var pct := _label("100%")
	pct.custom_minimum_size = Vector2(48, 0)
	slider.set_meta(&"pct", pct)
	slider.value_changed.connect(func(v: float):
		AudioDirector.set_volume(kind, v / 100.0)
		pct.text = "%d%%" % roundi(v)
		_save_settings())
	_volume_sliders[kind] = slider
	var row := _row(caption, slider)
	row.add_child(pct)
	return row


## Graphics section of the Settings page. Everything goes through GraphicsSettings (saved to graphics.cfg).
func _build_graphics(page: VBoxContainer) -> void:
	page.add_child(UiStyle.heading("GRAPHICS", 20))
	# WHY: scroll box keeps the panel inside a 720p window with all the extra rows.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var settings := VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override("separation", 8)
	scroll.add_child(settings)
	_gfx_preset = _gfx_option(GraphicsSettings.PRESET_NAMES + ["Custom"])
	_gfx_preset.item_selected.connect(func(i: int):
		if i < GraphicsSettings.PRESETS.size():
			GraphicsSettings.apply_preset(i))
	settings.add_child(_row("Quality", _gfx_preset))
	_gfx_shadows = _gfx_option(GraphicsSettings.SHADOW_NAMES)
	_gfx_shadows.item_selected.connect(func(i: int): GraphicsSettings.set_value("shadows", i))
	settings.add_child(_row("Shadows", _gfx_shadows))
	_gfx_aa = _gfx_option(GraphicsSettings.AA_NAMES)
	_gfx_aa.item_selected.connect(func(i: int): GraphicsSettings.set_value("aa", i))
	settings.add_child(_row("Anti-alias", _gfx_aa))
	_gfx_scale = HSlider.new()
	_gfx_scale.min_value = 50
	_gfx_scale.max_value = 100
	_gfx_scale.step = 5
	_gfx_scale.tooltip_text = "Lower = blurrier but much faster"
	_gfx_scale.custom_minimum_size = Vector2(160, 0)
	_gfx_scale_lbl = _label("100%")
	_gfx_scale_lbl.custom_minimum_size = Vector2(48, 0)
	_gfx_scale.value_changed.connect(func(v: float):
		_gfx_scale_lbl.text = "%d%%" % roundi(v)
		if roundi(v) != int(GraphicsSettings.values["scale"]):
			GraphicsSettings.set_value("scale", roundi(v)))
	var scale_row := _row("3D scale", _gfx_scale)
	scale_row.add_child(_gfx_scale_lbl)
	settings.add_child(scale_row)
	_gfx_lights = CheckButton.new()
	_gfx_lights.text = "Torch / lantern lights"
	_gfx_lights.toggled.connect(func(on: bool): GraphicsSettings.set_value("lights", on))
	settings.add_child(_gfx_lights)
	_gfx_effects = CheckButton.new()
	_gfx_effects.text = "Particle effects (embers)"
	_gfx_effects.toggled.connect(func(on: bool): GraphicsSettings.set_value("effects", on))
	settings.add_child(_gfx_effects)
	_gfx_fps = _gfx_option(GraphicsSettings.FPS_NAMES)
	_gfx_fps.item_selected.connect(func(i: int): GraphicsSettings.set_value("fps", i))
	settings.add_child(_row("FPS cap", _gfx_fps))
	GraphicsSettings.changed.connect(_refresh_graphics)
	_refresh_graphics()


func _gfx_option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it: String in items:
		o.add_item(it)
	UiStyle.style_field(o)
	return o


func _refresh_graphics() -> void:
	var v: Dictionary = GraphicsSettings.values
	_gfx_preset.select(GraphicsSettings.preset if GraphicsSettings.preset >= 0 else GraphicsSettings.PRESETS.size())
	_gfx_shadows.select(v["shadows"])
	_gfx_aa.select(v["aa"])
	_gfx_fps.select(v["fps"])
	_gfx_scale.set_value_no_signal(v["scale"])
	_gfx_scale_lbl.text = "%d%%" % int(v["scale"])
	_gfx_lights.set_pressed_no_signal(v["lights"])
	_gfx_effects.set_pressed_no_signal(v["effects"])


func _row(caption: String, control: Control) -> HBoxContainer:
	var l := _label(caption)
	l.custom_minimum_size = Vector2(110, 0)
	l.text = caption.to_upper()
	l.add_theme_font_override("font", UiStyle.title_font())
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("f2dcae"))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _hbox([l, control])


func _build_landing() -> void:
	_landing = Control.new()
	_landing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landing.theme = _menu_theme()
	add_child(_landing)
	var picture := TextureRect.new()
	picture.texture = load("res://game/ui/art/village-background.png")
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_landing.add_child(picture)
	# Tall plum banner on the left, like concept-art/ui/starting-menu-concept-v3.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.04
	panel.anchor_right = 0.33
	panel.anchor_top = 0.04
	panel.anchor_bottom = 0.94
	var style := UiStyle.panel()
	style.bg_color = Color("2b1222ee")
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	_landing.add_child(panel)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	var sun := UiStyle.heading("❦   ✹   ❦", 34)
	sun.add_theme_color_override("font_color", Color("f6b24a"))
	content.add_child(sun)
	var title_small := UiStyle.heading("THE LAST", 44)
	var title_big := UiStyle.heading("FIRE MAGE", 62)
	title_small.add_theme_constant_override("line_spacing", -8)
	content.add_child(title_small)
	content.add_child(title_big)
	content.add_child(UiStyle.ornament("☾", 18))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	content.add_child(spacer)
	var specs := [["HOST GAME", func(): _open_page("host")], ["JOIN GAME", func(): _open_page("join")],
		["SETTINGS", func(): _open_page("settings")], ["QUIT", func(): get_tree().quit()]]
	for i in specs.size():
		var button := _button(specs[i][0], specs[i][1])
		button.custom_minimum_size = Vector2(0, 58)
		if i == 0:
			UiStyle.style_primary(button, 30)
		else:
			UiStyle.style_secondary(button, 28)
		content.add_child(button)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 6)
	content.add_child(spacer2)
	content.add_child(UiStyle.ornament("", 14))
	content.add_child(UiStyle.footer("Private games with friends  ◆  Proximity voice", 16))
