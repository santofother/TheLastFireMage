extends CanvasLayer
## Main menu + in-game Esc menu (same panel). UI is built in code to keep the .tscn tiny.

const SETTINGS_PATH := "user://settings.cfg"

var _root: CenterContainer
var _name_edit: LineEdit
# FIX(S07, Codex): expose server bots for editor playtests without CLI arguments.
var _bot_count: SpinBox
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
		_show(not _root.visible)
		get_viewport().set_input_as_handled()


func _show(on: bool) -> void:
	_root.visible = on
	_refresh_buttons()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- actions

func _apply_name() -> void:
	NetworkManager.local_name = _name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "Player"
	_save_settings()


func _on_host_steam() -> void:
	_apply_name()
	NetworkManager.args["bots"] = int(_bot_count.value)
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
	_show(true)


func _on_lobby_list(lobbies: Array) -> void:
	_lobby_list.clear()
	for l in lobbies:
		var i := _lobby_list.add_item("%s  (%d/%d)" % [l["name"], l["members"], NetworkManager.MAX_PLAYERS])
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
	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var title := Label.new()
	title.text = "The Last Fire Mage — net/voice test"
	title.add_theme_font_size_override("font_size", 22)
	v.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Player name"
	_name_edit.max_length = 20
	v.add_child(_row("Name", _name_edit))

	# TODO: replace with the full character screen when the menus are redone.
	_skin_option = OptionButton.new()
	_skin_option.name = "VillagerSkin"
	for skin_name: String in VillagerSkins.NAMES:
		_skin_option.add_item(skin_name)
	_skin_option.item_selected.connect(func(i: int) -> void:
		VillagerSkins.local = i
		_save_settings())
	v.add_child(_row("Villager", _skin_option))

	# FIX(S07, Codex): shared by Steam and LAN hosting; CLI automation keeps its supplied count.
	_bot_count = SpinBox.new()
	_bot_count.name = "BotCount"
	_bot_count.min_value = 0
	_bot_count.max_value = NetworkManager.MAX_PLAYERS - 1
	_bot_count.step = 1
	_bot_count.value = clampi(int(NetworkManager.args.get("bots", 0)), 0, NetworkManager.MAX_PLAYERS - 1)
	_bot_count.tooltip_text = "Computer players to add when you host (0–5)."
	v.add_child(_row("Bots", _bot_count))

	v.add_child(HSeparator.new())
	_steam_label = Label.new()
	v.add_child(_steam_label)
	_host_steam_btn = _button("Host Steam lobby", _on_host_steam)
	_invite_btn = _button("Invite Steam friends", SteamManager.invite_friends)
	v.add_child(_hbox([_host_steam_btn, _invite_btn]))
	_refresh_btn = _button("Refresh lobby list", SteamManager.request_lobby_list)
	_join_lobby_btn = _button("Join selected lobby", _on_join_lobby)
	v.add_child(_hbox([_refresh_btn, _join_lobby_btn]))
	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 90)
	_lobby_list.item_activated.connect(func(_i): _on_join_lobby())
	v.add_child(_lobby_list)

	v.add_child(HSeparator.new())
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(80, 0)
	_host_lan_btn = _button("Host LAN", _on_host_lan)
	v.add_child(_hbox([_host_lan_btn, _label("Port"), _port_edit]))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_ip_btn = _button("Join IP", _on_join_ip)
	v.add_child(_hbox([_ip_edit, _join_ip_btn]))

	v.add_child(HSeparator.new())
	_mic_option = OptionButton.new()
	for d in VoiceManager.get_input_devices():
		_mic_option.add_item(d)
	_mic_option.item_selected.connect(func(i):
		VoiceManager.set_input_device(_mic_option.get_item_text(i))
		_save_settings())
	v.add_child(_row("Mic", _mic_option))
	var note := _label("Steam voice uses the mic chosen in Steam > Settings > Voice.")
	note.add_theme_font_size_override("font_size", 12)
	v.add_child(note)
	_ptt_check = CheckButton.new()
	_ptt_check.text = "Push-to-talk (hold V). Off = open mic"
	_ptt_check.toggled.connect(func(on):
		VoiceManager.push_to_talk = on
		_save_settings())
	v.add_child(_ptt_check)
	_mic_bar = ProgressBar.new()
	_mic_bar.show_percentage = false
	_mic_bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(_row("Mic level", _mic_bar))

	v.add_child(HSeparator.new())
	_leave_btn = _button("Leave game", _on_leave)
	v.add_child(_leave_btn)
	_status = _label("Ready. F3 = debug overlay, Esc = menu in game.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_status)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
