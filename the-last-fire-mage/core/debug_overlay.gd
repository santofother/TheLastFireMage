extends CanvasLayer
## F3 debug overlay + always-on mic meter while in a session.

var _panel: PanelContainer
var _label: Label
var _hud: VBoxContainer
var _mic_bar: ProgressBar


func _ready() -> void:
	layer = 100
	_panel = PanelContainer.new()
	_panel.position = Vector2(10, 10)
	_panel.visible = false
	add_child(_panel)
	_label = Label.new()
	_panel.add_child(_label)

	_hud = VBoxContainer.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hud.offset_left = 12
	_hud.offset_top = -26
	_hud.offset_right = 240
	_hud.offset_bottom = -12
	add_child(_hud)
	# FIX(S08, Codex): the round HUD owns keybind hints; reserve this strip for the mic.
	_mic_bar = ProgressBar.new()
	_mic_bar.custom_minimum_size = Vector2(220, 14)
	_mic_bar.show_percentage = false
	_hud.add_child(_mic_bar)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	_hud.visible = NetworkManager.is_in_session()
	_mic_bar.value = VoiceManager.mic_level * 100.0
	if not _panel.visible:
		return
	var mp := multiplayer
	var in_s := NetworkManager.is_in_session()
	var lines := PackedStringArray([
		"Mode: %s%s" % [NetworkManager.mode_name(), "  (host)" if in_s and mp.is_server() else ""],
		"Steam: %s" % SteamManager.init_message,
		"My peer id: %s" % (str(mp.get_unique_id()) if in_s else "-"),
		"Peers: %d   Players: %s" % [mp.get_peers().size() if in_s else 0, ", ".join(NetworkManager.player_names.values())],
		"Ping: %s" % ("host" if in_s and mp.is_server() else ("%d ms" % NetworkManager.ping_ms if NetworkManager.ping_ms >= 0 else "-")),
		"Voice: %s   PTT: %s   loopback(F4): %s" % [VoiceManager.voice_mode_name(), VoiceManager.push_to_talk, VoiceManager.loopback],
		"Voice packets sent: %d   received: %d" % [VoiceManager.packets_sent, VoiceManager.packets_received],
		VoiceManager.status_line(), # FIX(S12, Claude): kbit/s line requested by the S12 card
		"Mic level: %d%%   talking: %s   device: %s" % [int(VoiceManager.mic_level * 100), VoiceManager.local_speaking, AudioServer.input_device],
		"Falloff: full <= %.0f m, silent >= %.0f m" % [VoiceManager.full_volume_distance, VoiceManager.silent_distance],
		"FPS: %d" % Engine.get_frames_per_second(),
	])
	_label.text = "\n".join(lines)
