## In-round presentation. Owner: S08. Public API: GameEvents.system(&"hud").
## Reads events and replicated state; never changes gameplay. NET: local on every peer.
class_name Hud
extends CanvasLayer

const INK := Color("ecede8")
const EMBER := Color("ffb766")
var _root: Control
var _labels: Dictionary = {}
var _blind: ColorRect
var _health_meter: ProgressBar
var _stamina: VBoxContainer
var _stamina_meter: ProgressBar
var _meter: ProgressBar
var _marks: Control
var _threshold: ColorRect
var _phase := Enums.Phase.LOBBY
var _role := Enums.Role.NONE
var _remaining := 0.0
var _roles: Dictionary = {}
var _scores: Dictionary = {}
var _dead: Dictionary = {}
var _kills: Dictionary = {}
var _feed: Array[Dictionary] = []
var _carry: StringName = &""
var _power := 0.0
var _tier := 0
var _multiplier := 1.0
var _required := 0.0
var _warning_left := 0.0
var _warning_stage := 0
var _result := ""
var _local: Node
var _poll := 0.0

func _enter_tree() -> void:
	GameEvents.register_system(&"hud", self)

func _ready() -> void:
	_build()
	GameEvents.phase_changed.connect(_on_phase)
	GameEvents.role_assigned.connect(_on_role)
	GameEvents.local_player_ready.connect(_on_local)
	GameEvents.carry_changed.connect(_on_carry)
	GameEvents.interact_prompt_changed.connect(_on_prompt)
	GameEvents.power_changed.connect(_on_power)
	GameEvents.firestorm_warning.connect(_on_warning)
	GameEvents.firestorm_stage.connect(_on_storm)
	GameEvents.player_died.connect(_on_death)
	GameEvents.player_revived.connect(_on_revive)
	GameEvents.score_changed.connect(_on_score)
	GameEvents.round_ended.connect(_on_result)
	GameEvents.party_ended.connect(_on_party)
	NetworkManager.session_ended.connect(_on_session_end)
	_local = Players.local_player()
	var match_system := GameEvents.system(&"match")
	if match_system:
		for id in match_system.roles:
			_on_role(id, match_system.roles[id])
		_on_phase(match_system.phase, match_system.time_left)
	_refresh()

func _build() -> void:
	_root = Control.new()
	_root.name = "RoundHUD"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_blind = ColorRect.new()
	_blind.color = Color("080b11")
	_blind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_blind)
	_label("Phase", Rect2(.34, .035, .32, .08), 28, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Role", Rect2(.035, .05, .27, .09), 26)
	_label("Reveal", Rect2(.2, .32, .6, .16), 38, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Blind", Rect2(.2, .5, .6, .16), 24, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Warning", Rect2(.25, .15, .5, .1), 24, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Feed", Rect2(.71, .05, .26, .23), 18, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Speaking", Rect2(.035, .25, .25, .24), 18)
	_label("Health", Rect2(.035, .63, .25, .05), 20)
	_health_meter = ProgressBar.new()
	_health_meter.name = "HealthMeter"
	_health_meter.show_percentage = false
	_health_meter.anchor_left = .035
	_health_meter.anchor_right = .285
	_health_meter.anchor_top = .69
	_health_meter.anchor_bottom = .715
	_health_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_health_meter)
	_label("Power", Rect2(.035, .76, .42, .055), 20)
	_meter = ProgressBar.new()
	_meter.name = "PowerMeter"
	_meter.show_percentage = false
	_meter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_meter.anchor_left = .035
	_meter.anchor_right = .455
	_meter.anchor_top = .825
	_meter.anchor_bottom = .85
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_meter)
	_marks = Control.new()
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.add_child(_marks)
	_threshold = ColorRect.new()
	_threshold.color = Color("ff5a54")
	_threshold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.add_child(_threshold)
	_label("Carry", Rect2(.035, .82, .4, .08), 24)
	_label("Cooldowns", Rect2(.035, .87, .85, .045), 18)
	_label("Prompt", Rect2(.3, .68, .4, .07), 24, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Hint", Rect2(.7, .91, .27, .05), 16, HORIZONTAL_ALIGNMENT_RIGHT)
	_labels.Hint.text = "Hold Tab · scoreboard     V · speak"
	_label("Scoreboard", Rect2(.22, .24, .56, .49), 21, HORIZONTAL_ALIGNMENT_CENTER, true)
	_label("Results", Rect2(.18, .23, .64, .55), 23, HORIZONTAL_ALIGNMENT_CENTER, true)
	_root.resized.connect(_layout_meter)
	_build_stamina()

func _build_stamina() -> void:
	# Separate from the round panel so the same meter is visible in Explore Town.
	_stamina = VBoxContainer.new()
	_stamina.name = "Stamina"
	_stamina.anchor_left = 1.0
	_stamina.anchor_right = 1.0
	_stamina.anchor_top = 1.0
	_stamina.anchor_bottom = 1.0
	_stamina.offset_left = -242
	_stamina.offset_right = -26
	_stamina.offset_top = -106
	_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = "STAMINA"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina.add_child(label)
	_stamina_meter = ProgressBar.new()
	_stamina_meter.name = "Meter"
	_stamina_meter.show_percentage = false
	_stamina_meter.step = 0.0
	_stamina_meter.custom_minimum_size.y = 10
	_stamina_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("17251feb")
	track.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("9ee391")
	fill.set_corner_radius_all(3)
	_stamina_meter.add_theme_stylebox_override("background", track)
	_stamina_meter.add_theme_stylebox_override("fill", fill)
	_stamina.add_child(_stamina_meter)
	add_child(_stamina)

func _refresh_stamina() -> void:
	var player := _local as Player if is_instance_valid(_local) else null
	var exploring := _phase == Enums.Phase.LOBBY and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var in_round := _phase in [Enums.Phase.HEAD_START, Enums.Phase.HUNT] and not _blind.visible
	_stamina.visible = player != null and player.is_alive and not player.health.is_downed and (exploring or in_round)
	if _stamina.visible:
		_stamina_meter.max_value = player.tuning.max_stamina
		_stamina_meter.value = player.stamina

func _label(key: String, rect: Rect2, size: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, panel: bool = false) -> void:
	var label := Label.new()
	label.name = key
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.anchor_left = rect.position.x
	label.anchor_top = rect.position.y
	label.anchor_right = rect.end.x
	label.anchor_bottom = rect.end.y
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", EMBER if key in ["Role", "Warning", "Power"] else INK)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	if panel:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("101923f5")
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.border_color = EMBER
		style.set_border_width_all(2)
		label.add_theme_stylebox_override("normal", style)
	_root.add_child(label)
	_labels[key] = label

func _process(delta: float) -> void:
	_remaining = maxf(0, _remaining - delta)
	_warning_left = maxf(0, _warning_left - delta)
	for entry in _feed:
		entry.left -= delta
	while not _feed.is_empty() and _feed[0].left <= 0:
		_feed.pop_front()
	var match_system := GameEvents.system(&"match")
	if match_system:
		_remaining = match_system.time_left
	_poll -= delta
	if _poll <= 0:
		_poll = .1
		_refresh()
	_labels.Scoreboard.visible = _root.visible and Input.is_action_pressed("scoreboard")
	_labels.Results.visible = not _result.is_empty() and not _labels.Scoreboard.visible
	_refresh_stamina()

func _local_id() -> int:
	if is_instance_valid(_local):
		return int(_local.get("peer_id"))
	# WHY: a session-end power reset can arrive after the local player and peer are removed.
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0

func _name_for(id: int) -> String:
	return str(NetworkManager.player_names.get(id, "Player %d" % id)) if id != 0 else "Firestorm / environment"

func _on_local(player: Node) -> void:
	_local = player
	_role = int(player.get("role"))
	_refresh()

func _on_role(id: int, role: int) -> void:
	_roles[id] = role
	if id == _local_id():
		_role = role
	_refresh()

func _on_phase(phase: int, duration: float) -> void:
	_phase = phase
	_remaining = duration
	if phase == Enums.Phase.LOBBY or phase == Enums.Phase.ROLE_REVEAL:
		_dead.clear()
		_kills.clear()
		_feed.clear()
		_carry = &""
		_power = 0
		_tier = 0
		_multiplier = 1
		_required = 0
		_warning_left = 0
		_warning_stage = 0
		_result = ""
		_labels.Prompt.text = ""
		if phase == Enums.Phase.LOBBY:
			_roles.clear()
			_role = Enums.Role.NONE
	_refresh()

func _on_carry(id: int, kind: StringName) -> void:
	if id == _local_id():
		_carry = kind
		_refresh()

func _on_prompt(text: String) -> void:
	_labels.Prompt.text = text

func _on_power(id: int, power: float, tier: int, multiplier: float) -> void:
	if id == _local_id():
		_power = power
		_tier = tier
		_multiplier = multiplier
		_refresh()

func _on_warning(stage: int, seconds: float) -> void:
	_warning_stage = stage
	_warning_left = seconds
	_refresh()

func _on_storm(stage: int, _center: Vector3, _radius: float, required: float, _seconds: float) -> void:
	_required = required
	_warning_stage = stage
	_warning_left = 0
	_refresh()

func _on_death(id: int, killer: int, cause: StringName) -> void:
	_dead[id] = true
	if killer != 0 and killer != id:
		_kills[killer] = int(_kills.get(killer, 0)) + 1
	_feed.append({"text": "%s → %s · %s" % [_name_for(killer), _name_for(id), String(cause).replace("_", " ")], "left": 8.0})
	if _feed.size() > 4:
		_feed.pop_front()
	_refresh()

func _on_revive(id: int) -> void:
	_dead.erase(id)
	_refresh()

func _on_score(id: int, total: int) -> void:
	_scores[id] = total
	_refresh()

func _on_result(winner: int, reason: String) -> void:
	_result = "%s WIN\n%s" % ["MAGE" if winner == Enums.Winner.MAGE else "VILLAGERS", reason.replace("_", " ")]
	_refresh()

func _on_party(standings: Array) -> void:
	_result = "PARTY RESULTS"
	for entry in standings:
		_result += "\n%s · %d points" % [entry.name, entry.total]
	_refresh()

func _on_session_end(_reason: String) -> void:
	_scores.clear()
	_on_phase(Enums.Phase.LOBBY, 0)

func _summary() -> String:
	var lines := PackedStringArray()
	var ids := _roles.keys()
	for id in _scores:
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	for id in ids:
		lines.append("%s · %s · %s · %d kills · %d pts" % [_name_for(id), Enums.role_name(int(_roles.get(id, 0))), "dead" if _dead.has(id) else "alive", int(_kills.get(id, 0)), int(_scores.get(id, 0))])
	return "\n".join(lines)

func _refresh() -> void:
	if not is_instance_valid(_root):
		return
	_root.visible = _phase != Enums.Phase.LOBBY
	var seconds := ceili(_remaining)
	_labels.Phase.text = "%s  ·  %02d:%02d" % [Enums.phase_name(_phase).replace("HeadStart", "HEAD START").replace("RoleReveal", "ROLE REVEAL").to_upper(), seconds / 60, seconds % 60]
	_labels.Role.text = "YOU ARE THE %s" % Enums.role_name(_role).to_upper()
	_labels.Reveal.text = _labels.Role.text if _phase == Enums.Phase.ROLE_REVEAL else ""
	_blind.visible = _role == Enums.Role.MAGE and _phase in [Enums.Phase.ROLE_REVEAL, Enums.Phase.HEAD_START]
	_labels.Blind.text = "YOU ARE BLINDED\nVillagers are hiding. Hunt begins in %d s" % seconds if _blind.visible else ""
	var health := _local.get_node_or_null("Health") as Health if is_instance_valid(_local) else null
	_health_meter.visible = health != null
	_labels.Health.visible = health != null
	if health:
		_health_meter.max_value = maxf(1.0, health.max_hp)
		_health_meter.value = health.hp
		_labels.Health.text = "HEALTH %.0f / %.0f" % [health.hp, health.max_hp]
	var mage := _role == Enums.Role.MAGE
	_labels.Power.visible = mage
	_meter.visible = mage
	_labels.Cooldowns.visible = mage
	_labels.Carry.visible = _role == Enums.Role.VILLAGER
	_labels.Carry.text = "CARRYING · %s" % String(_carry).capitalize() if _carry != &"" else "HANDS EMPTY"
	_labels.Power.text = "POWER %.1f · TIER %d · ×%.2f   /   STORM NEEDS %.1f" % [_power, _tier + 1, _multiplier, _required]
	_layout_meter()
	var cooldowns := PackedStringArray()
	var abilities: Node = _local.call("get_ability", &"MageAbilities") if is_instance_valid(_local) and _local.has_method("get_ability") else null
	# S13: each ability shows its keybind (read from the InputMap so rebinding stays correct).
	var binds := {&"knife": &"primary", &"ignite": &"ability_1", &"fire_wave": &"ability_2"}
	for ability in [&"knife", &"ignite", &"fire_wave"]:
		var left := float(abilities.call("cooldown_left", ability)) if abilities else 0.0
		cooldowns.append("[%s] %s · %s" % [_key_names(binds[ability]), String(ability).replace("_", " ").capitalize(), "READY" if left <= 0 else "%.1fs" % left])
	# The locator is a passive pulse with no key, so it is labelled AUTO rather than a keybind.
	if abilities and abilities.has_method("locator_left"):
		var pulse := float(abilities.call("locator_left"))
		cooldowns.append("[AUTO] Locate · %s" % ("READY" if pulse <= 0 else "%.1fs" % pulse))
	_labels.Cooldowns.text = "   ".join(cooldowns)
	_labels.Warning.text = "FIRESTORM %d IN %d s" % [_warning_stage, ceili(_warning_left)] if _warning_left > 0 else ("FIRESTORM · STAGE %d" % _warning_stage if _required > 0 else "")
	var feed := PackedStringArray()
	for entry in _feed:
		feed.append(entry.text)
	_labels.Feed.text = "\n".join(feed)
	var speakers := PackedStringArray()
	if VoiceManager.local_speaking:
		speakers.append("● %s (you)" % _name_for(_local_id()))
	# WHY: reuse the packet timestamps that already drive VoiceManager's world indicators.
	var voice_state: Dictionary = VoiceManager.get("_speakers")
	for id in voice_state:
		if Time.get_ticks_msec() / 1000.0 - float(voice_state[id].last) < VoiceManager.SPEAKING_TIMEOUT:
			speakers.append("● %s" % _name_for(id))
	_labels.Speaking.text = "\n".join(speakers)
	_labels.Scoreboard.text = "SCOREBOARD\n\n" + _summary()
	_labels.Results.visible = not _result.is_empty()
	_labels.Results.text = _result + "\n\n" + _summary()

## Short display names of the inputs bound to an action, e.g. "RMB/Q".
func _key_names(action: StringName) -> String:
	var names := PackedStringArray()
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			names.append({1: "LMB", 2: "RMB", 3: "MMB"}.get(event.button_index, "Mouse%d" % event.button_index))
		elif event is InputEventKey:
			var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			names.append(OS.get_keycode_string(code))
	return "/".join(names)

func _layout_meter() -> void:
	if not is_instance_valid(_meter):
		return
	var thresholds := PackedFloat32Array([0, 3, 6, 10])
	var power_system := GameEvents.system(&"power")
	if power_system and power_system.get("tuning"):
		thresholds = power_system.tuning.tier_thresholds
	_meter.max_value = maxf(12, maxf(_required, _power) * 1.15)
	if not thresholds.is_empty():
		_meter.max_value = maxf(_meter.max_value, thresholds[-1] * 1.2)
	_meter.value = _power
	for child in _marks.get_children():
		if child != _threshold:
			child.free()
	for value in thresholds:
		var mark := Label.new()
		mark.text = "│\n%.0f" % value
		mark.add_theme_font_size_override("font_size", 14)
		mark.position = Vector2(value / _meter.max_value * _meter.size.x - 3, -5)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_marks.add_child(mark)
	_threshold.visible = _required > 0
	_threshold.position = Vector2(_required / _meter.max_value * _meter.size.x, -4)
	_threshold.size = Vector2(3, _meter.size.y + 8)
