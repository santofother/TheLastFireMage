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
var _skin_option: OptionButton
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
var _status: Label


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
	_skin_option.disabled = in_s
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
	_skin_option.select(skin)
	VoiceManager.push_to_talk = cfg.get_value("voice", "push_to_talk", true)
	_ptt_check.button_pressed = VoiceManager.push_to_talk
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
	add_child(_root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(550, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("351c2af2"), Color("d19a50"), 2))
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	_page_title = _label("HOST GAME")
	_page_title.add_theme_color_override("font_color", Color("ffd080"))
	_page_title.add_theme_font_size_override("font_size", 27)
	v.add_child(_page_title)
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
	_mage_count.max_value = 5
	_mage_count.step = 1
	_mage_count.value = 1
	host.add_child(_row("Mages", _mage_count))

	# TODO: replace with the full character screen when the menus are redone.
	_skin_option = OptionButton.new()
	_skin_option.name = "VillagerSkin"
	for skin_name: String in VillagerSkins.NAMES:
		_skin_option.add_item(skin_name)
	_skin_option.item_selected.connect(func(i: int) -> void:
		VillagerSkins.local = i
		_save_settings())
	host.add_child(_row("Villager", _skin_option))

	_bot_count = SpinBox.new()
	_bot_count.name = "BotCount"
	_bot_count.min_value = 0
	_bot_count.max_value = NetworkManager.MAX_PLAYERS - 1
	_bot_count.step = 1
	_bot_count.value = clampi(int(NetworkManager.args.get("bots", 0)), 0, NetworkManager.MAX_PLAYERS - 1)
	host.add_child(_row("Bots", _bot_count))
	_steam_label = _label("")
	host.add_child(_steam_label)
	_host_steam_btn = _button("Host Steam lobby", _on_host_steam)
	_host_lan_btn = _button("Host LAN", _on_host_lan)
	host.add_child(_hbox([_host_steam_btn, _host_lan_btn]))
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	var port_row := _row("LAN port", _port_edit)
	v.add_child(port_row)
	v.move_child(port_row, 2)
	_invite_btn = _button("Invite Steam friends", SteamManager.invite_friends)
	host.add_child(_invite_btn)
	var join: VBoxContainer = _pages["join"]
	_refresh_btn = _button("Refresh Steam lobbies", SteamManager.request_lobby_list)
	_join_lobby_btn = _button("Join selected lobby", _on_join_lobby)
	join.add_child(_hbox([_refresh_btn, _join_lobby_btn]))
	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 120)
	_lobby_list.item_activated.connect(func(_i): _on_join_lobby())
	join.add_child(_lobby_list)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_ip_btn = _button("Join IP", _on_join_ip)
	join.add_child(_hbox([_ip_edit, _join_ip_btn]))
	var join_port := _label("Enter a host address and the LAN port above.")
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
	var back := _button("Back", func():
		_show(false)
		if not NetworkManager.is_in_session():
			_landing.visible = true)
	back.name = "BackButton"
	v.add_child(back)
	_leave_btn = _button("Leave game", _on_leave)
	v.add_child(_leave_btn)
	_status = _label("Ready")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_status)
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
	b.add_theme_stylebox_override("normal", _panel_style(Color("68372f"), Color("c69250"), 2))
	b.add_theme_stylebox_override("hover", _panel_style(Color("b7541c"), Color("ffca64"), 3))
	b.add_theme_stylebox_override("pressed", _panel_style(Color("8a3d19"), Color("ffe4a0"), 2))
	b.add_theme_color_override("font_color", Color("ffe5b1"))
	b.add_theme_color_override("font_hover_color", Color("fff4d5"))
	b.pressed.connect(cb)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _hbox(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	for c in children:
		h.add_child(c)
	return h


func _row(caption: String, control: Control) -> HBoxContainer:
	var l := _label(caption)
	l.custom_minimum_size = Vector2(80, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _hbox([l, control])


func _panel_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	if width == 3:
		style.shadow_color = Color("ff821b99")
		style.shadow_size = 3
	return style


func _build_landing() -> void:
	_landing = Control.new()
	_landing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_landing)
	var picture := TextureRect.new()
	picture.texture = load("res://game/ui/art/village-background.png")
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_landing.add_child(picture)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.035
	panel.anchor_right = 0.35
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	panel.add_theme_stylebox_override("panel", _panel_style(Color("301725ed"), Color("d79b50"), 2))
	_landing.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	var title := Label.new()
	title.text = "THE LAST\nFIRE MAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("ffd080"))
	content.add_child(title)
	var ornament := _label("✦    ━━━━━    ✦")
	ornament.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ornament.add_theme_color_override("font_color", Color("d99a4e"))
	content.add_child(ornament)
	for spec in [["HOST GAME", func(): _open_page("host")], ["JOIN GAME", func(): _open_page("join")], ["SETTINGS", func(): _open_page("settings")], ["QUIT", func(): get_tree().quit()]]:
		var button := _button(spec[0], spec[1])
		button.custom_minimum_size = Vector2(0, 54)
		button.add_theme_font_size_override("font_size", 24)
		content.add_child(button)
