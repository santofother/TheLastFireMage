class_name MatchManager
extends Node
## Server-run round state machine and lobby. Owner: S04. Runs at Systems/Match on every peer.
## Public API: phase, time_left, mage_id, mage_count, roles, tuning; start_round(), end_round(), get_role(),
## mage_ids(), is_round_active(). RPCs emit GameEvents phase_changed/role_assigned/round_ended on every peer.
## Player.set_role() always precedes role_assigned, including delayed spawns and late-join snapshots.

## Current Enums.Phase (synced, with events delivered through reliable RPCs).
var phase: int = Enums.Phase.LOBBY
## Server's seconds remaining, replicated at 10 Hz for the HUD.
var time_left := 0.0
## TUNE: most mages the host can choose. A round always keeps at least one villager.
const MAX_MAGES := 9 # CONTRACT: any ratio, but one villager always remains (see _draw_mages)

## Selected mage in the lobby (0 = random). During a round: the first mage (see mage_ids() for all).
var mage_id := 0
## Host's lobby choice for mages per round; extra mages are drawn at random.
var mage_count := 1
## Peer id -> Enums.Role for this round, including late spectators.
var roles: Dictionary = {}
## Private tuning copy, including --tune=match.* overrides.
var tuning: MatchTuning

var _known: Dictionary = {}
var _pending_roles: Dictionary = {}
var _snapshots: Array[int] = []
var _living_villagers: Dictionary = {}
var _living_mages: Dictionary = {}
var _winner: int = Enums.Winner.NONE
var _reason := ""
var _autostart_used := false
var _session_closed := false
var _roster_key := "uninitialized"
var _exploring := false
var _bot_count: SpinBox
var _lobby_background: TextureRect
var _roster_label: Label
var _invite: Button
var _portraits: Array[AtlasTexture] = []
## Six lobby slot cards (one per player seat): {panel, portrait, empty, name, sub, prev, next}.
var _slots: Array[Dictionary] = []
var _player_count_label: Label
var _mage_caption: Label
var _card_styles: Dictionary = {} # "filled"/"empty"/"you" -> StyleBoxFlat
var _slot_layout_count := -1

@onready var _lobby: PanelContainer = $UI/Lobby
@onready var _pick: OptionButton = $UI/Lobby/Content/MagePick
@onready var _count: SpinBox = $UI/Lobby/Content/MageCountRow/MageCount
@onready var _start: Button = $UI/Lobby/Content/Start
@onready var _status: Label = $UI/Lobby/Content/Status
var _settings_panel: PanelContainer
var _settings_btn: Button
@onready var _blind: ColorRect = $UI/Blind
@onready var _blind_text: Label = $UI/Blind/Message


func _enter_tree() -> void:
	GameEvents.register_system(&"match", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/match/tuning_match.tres", "match") as MatchTuning
	GameEvents.player_died.connect(_on_player_died)
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.hosting_started.connect(_on_session_started)
	NetworkManager.connected.connect(_on_session_started)
	_start.pressed.connect(func() -> void: start_round(mage_id))
	$UI/Lobby/Content/Explore.pressed.connect(_on_explore_town)
	_pick.item_selected.connect(_on_mage_picked)
	_count.max_value = MAX_MAGES
	_count.value_changed.connect(_on_mage_count_changed)
	mage_count = _default_mage_count()
	var bots_label := Label.new()
	bots_label.name = "BotCountLabel"
	bots_label.text = "BOTS"
	_bot_count = SpinBox.new()
	_bot_count.min_value = 0
	_bot_count.max_value = NetworkManager.MAX_PLAYERS - 1
	_bot_count.step = 1
	_bot_count.value = clampi(int(NetworkManager.args.get("bots", 0)), 0, NetworkManager.MAX_PLAYERS - 1)
	_bot_count.value_changed.connect(func(value: float):
		if Net.is_server(self):
			var bot_manager := GameEvents.system(&"bots")
			if bot_manager:
				bot_manager.set_lobby_count(int(value)))
	$UI/Lobby/Content.add_child(bots_label)
	$UI/Lobby/Content.add_child(_bot_count)
	$UI/Lobby/Content.move_child(bots_label, 5)
	$UI/Lobby/Content.move_child(_bot_count, 6)
	_style_lobby()
	_lobby_background = TextureRect.new()
	_lobby_background.texture = load("res://game/ui/art/village-background.png")
	_lobby_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_lobby_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_background.visible = false
	$UI.add_child(_lobby_background)
	$UI.move_child(_lobby_background, 0)
	_roster_label = Label.new() # kept for the roster text tests/logs read; hidden in favour of the cards
	_roster_label.visible = false
	$UI/Lobby/Content.add_child(_roster_label)
	_invite = Button.new()
	_invite.text = "INVITE FRIENDS"
	_invite.pressed.connect(SteamManager.invite_friends)
	$UI/Lobby/Content.add_child(_invite)
	var sheet: Texture2D = load("res://game/ui/art/portraits.png")
	for index in 2:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		# Square-ish crop on the face so the small slot portraits read well.
		var w := sheet.get_width() * 0.5
		atlas.region = Rect2(w * index + w * 0.12, 0, w * 0.76, sheet.get_height() * 0.76)
		_portraits.append(atlas)
	_build_lobby_cards()
	_layout_lobby()
	_settings_panel = preload("res://game/match/game_settings_panel.gd").new()
	_settings_panel.changed.connect(_on_settings_changed)
	$UI.add_child(_settings_panel)
	_settings_btn = Button.new()
	_settings_btn.text = "GAME SETTINGS"
	_settings_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_settings_btn.offset_left = 20
	_settings_btn.offset_top = -70
	_settings_btn.offset_right = 240
	_settings_btn.offset_bottom = -20
	UiStyle.style_primary(_settings_btn, 18)
	_settings_btn.pressed.connect(func() -> void: _settings_panel.visible = not _settings_panel.visible)
	$UI.add_child(_settings_btn)


func _process(delta: float) -> void:
	if _session_closed:
		return
	_apply_pending_roles()
	if Net.is_server(self):
		_discover_players()
		_send_snapshots()
		if phase != Enums.Phase.LOBBY:
			time_left = maxf(0.0, time_left - delta)
			if time_left <= 0.0:
				_advance_phase()
		elif NetworkManager.args.has("autostart") and not _autostart_used:
			var needed := maxi(tuning.min_players, int(NetworkManager.args.get("autostart-players", tuning.min_players)))
			if Players.all().size() >= needed:
				_autostart_used = true
				start_round(int(NetworkManager.args.get("mage-id", mage_id)))
	_update_ui()


## NET: server only. Starts from LOBBY with at least min_players. 0 uses the lobby pick or random.
func start_round(selected_mage: int = 0) -> void:
	if _session_closed or not Net.is_server(self) or phase != Enums.Phase.LOBBY:
		return
	var roster := Players.all()
	if roster.size() < maxi(2, tuning.min_players):
		return
	var chosen := selected_mage if selected_mage != 0 else mage_id
	if chosen == 0:
		chosen = int(roster.pick_random().peer_id)
	if Players.get_player(chosen) == null:
		return
	_winner = Enums.Winner.NONE
	_reason = ""
	_living_villagers.clear()
	_living_mages.clear()
	var mages := _draw_mages(roster, chosen)
	var assigned := {}
	for p in roster:
		var is_mage: bool = p.peer_id in mages
		assigned[p.peer_id] = Enums.Role.MAGE if is_mage else Enums.Role.VILLAGER
		_known[p.peer_id] = true
		if is_mage:
			_living_mages[p.peer_id] = true
		else:
			_living_villagers[p.peer_id] = true
			if not p.health.downed.is_connected(_check_villagers):
				p.health.downed.connect(_check_villagers)
	Net.broadcast(self, &"_rpc_roles", [assigned, chosen])
	for p in roster:
		p.health.invulnerable = true
		p.health.revive()
	_change_phase(Enums.Phase.ROLE_REVEAL, tuning.role_reveal_time)


## NET: server only. Decides a round once; round_ended fires just before RESULTS on all peers.
func end_round(winner: int, reason: String) -> void:
	if not Net.is_server(self) or not _round_started() or _winner != Enums.Winner.NONE:
		return
	if winner != Enums.Winner.MAGE and winner != Enums.Winner.VILLAGERS:
		return
	Net.broadcast(self, &"_rpc_result", [winner, reason])
	_change_phase(Enums.Phase.RESULTS, tuning.results_time)


## Role of a peer this round, or NONE if absent.
func get_role(peer_id: int) -> int:
	return int(roles.get(peer_id, Enums.Role.NONE))


## Peer ids of every mage this round. Any peer.
func mage_ids() -> Array[int]:
	var found: Array[int] = []
	for id: int in roles:
		if roles[id] == Enums.Role.MAGE:
			found.append(id)
	return found


## True during HEAD_START and HUNT (the public gameplay contract).
func is_round_active() -> bool:
	return phase == Enums.Phase.HEAD_START or phase == Enums.Phase.HUNT


func _draw_mages(roster: Array, chosen: int) -> Array[int]:
	var mages: Array[int] = [chosen]
	var others := roster.filter(func(p: Node) -> bool: return p.peer_id != chosen)
	others.shuffle()
	# CONTRACT: at least one villager remains, so a small lobby can have fewer mages than chosen.
	for i in mini(clampi(mage_count, 1, MAX_MAGES) - 1, others.size() - 1):
		mages.append(int(others[i].peer_id))
	return mages


func _default_mage_count() -> int:
	return clampi(int(NetworkManager.args.get("mage-count", 1)), 1, MAX_MAGES)


func _round_started() -> bool:
	return phase == Enums.Phase.ROLE_REVEAL or is_round_active()


func _advance_phase() -> void:
	match phase:
		Enums.Phase.ROLE_REVEAL:
			# WHY: blind the mage on every peer before any villager teleport is sent.
			_change_phase(Enums.Phase.HEAD_START, tuning.head_start_time)
			_spawn_round()
		Enums.Phase.HEAD_START:
			_change_phase(Enums.Phase.HUNT, tuning.hunt_time)
		Enums.Phase.HUNT:
			end_round(Enums.Winner.VILLAGERS, "timeout")
		Enums.Phase.RESULTS:
			_return_to_lobby()


func _change_phase(next: int, duration: float) -> void:
	for p in Players.all():
		_configure_player(p, next)
	Net.broadcast(self, &"_rpc_phase", [next, maxf(0.0, duration)])


func _configure_player(p: Node, next: int) -> void:
	var spectator := get_role(p.peer_id) == Enums.Role.SPECTATOR
	p.health.invulnerable = spectator or next != Enums.Phase.HUNT and next != Enums.Phase.LOBBY
	p.set_input_lock(&"match", spectator or next == Enums.Phase.ROLE_REVEAL \
		or next == Enums.Phase.RESULTS or next == Enums.Phase.HEAD_START and get_role(p.peer_id) == Enums.Role.MAGE)


func _spawn_round() -> void:
	var villagers := get_tree().get_nodes_in_group(&"villager_spawn")
	var mages := get_tree().get_nodes_in_group(&"mage_spawn")
	villagers.shuffle()
	mages.shuffle()
	var index := 0
	var mage_index := 0
	for p in Players.all():
		if get_role(p.peer_id) == Enums.Role.MAGE:
			var points := _clear_spawns(p, mages)
			var pos := Vector3(0, 1, 0)
			if not points.is_empty():
				pos = points[mage_index % points.size()]
				# WHY: a map can have fewer clear markers than mages; never stack two on one spot.
				pos += Vector3.RIGHT * 0.9 * (mage_index / points.size())
			print("[Match] Spawn ", p.peer_id, " MAGE at ", pos)
			p.teleport(pos)
			mage_index += 1
		elif get_role(p.peer_id) == Enums.Role.VILLAGER:
			var points := _clear_spawns(p, villagers)
			var pos: Vector3 = points[index % points.size()] if not points.is_empty() else Vector3(3 + index * 2, 1, 0)
			print("[Match] Spawn ", p.peer_id, " VILLAGER at ", pos)
			p.teleport(pos)
			index += 1


func _clear_spawns(p: Node3D, markers: Array[Node]) -> Array[Vector3]:
	# WHY: markers can intersect walls (including one in test_arena); avoid physics depenetration.
	var shape := CapsuleShape3D.new()
	shape.radius = p.tuning.radius
	shape.height = p.tuning.height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 # world only; players are being repositioned together
	var points: Array[Vector3] = []
	for marker in markers:
		var pos: Vector3 = marker.global_position
		query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, shape.height / 2.0, 0))
		if p.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			points.append(pos)
	return points


func _return_to_lobby() -> void:
	var assigned := {}
	for p in Players.all():
		assigned[p.peer_id] = Enums.Role.NONE
	Net.broadcast(self, &"_rpc_roles", [assigned, 0])
	for p in Players.all():
		p.health.revive()
	_living_villagers.clear()
	_living_mages.clear()
	_change_phase(Enums.Phase.LOBBY, 0.0)


func _on_player_died(id: int, _killer: int, _cause: StringName) -> void:
	if not Net.is_server(self) or not _round_started():
		return
	if get_role(id) == Enums.Role.MAGE:
		_living_mages.erase(id)
		if _living_mages.is_empty():
			end_round(Enums.Winner.VILLAGERS, "mage_died")
	elif get_role(id) == Enums.Role.VILLAGER:
		_living_villagers.erase(id)
		_check_villagers()


## Mage wins when no villager is left standing: dead, or downed with nobody free to revive them.
func _check_villagers() -> void:
	if not Net.is_server(self) or not _round_started():
		return
	var standing := false
	for id in _living_villagers:
		var p := Players.get_player(id)
		if p == null or not p.health.is_downed:
			standing = true
	if not standing:
		end_round(Enums.Winner.MAGE, "all_dead")


func _on_peer_left(id: int) -> void:
	if not Net.is_server(self):
		return
	var primary := 0 if phase == Enums.Phase.LOBBY and id == mage_id else mage_id
	if _round_started():
		if get_role(id) == Enums.Role.MAGE:
			_living_mages.erase(id)
			if _living_mages.is_empty():
				end_round(Enums.Winner.VILLAGERS, "mage_left")
			elif id == mage_id:
				primary = int(_living_mages.keys()[0])
		elif get_role(id) == Enums.Role.VILLAGER:
			_living_villagers.erase(id)
			_check_villagers()
	_known.erase(id)
	_snapshots.erase(id)
	var remaining := roles.duplicate()
	remaining.erase(id)
	Net.broadcast(self, &"_rpc_roles", [remaining, primary])


func _on_registered(id: int, _name: String) -> void:
	if id != 1 and not _snapshots.has(id):
		_snapshots.append(id)


func _discover_players() -> void:
	# WHY: registration precedes Main's spawn callback; polling also discovers server-owned bots.
	for p in Players.all():
		if _known.has(p.peer_id):
			continue
		_known[p.peer_id] = true
		var assigned := roles.duplicate()
		assigned[p.peer_id] = Enums.Role.NONE if phase == Enums.Phase.LOBBY else Enums.Role.SPECTATOR
		Net.broadcast(self, &"_rpc_roles", [assigned, mage_id])
		_configure_player(p, phase)


func _send_snapshots() -> void:
	for id in _snapshots.duplicate():
		if Players.get_player(id) == null or not multiplayer.get_peers().has(id):
			continue
		_rpc_mage_count.rpc_id(id, mage_count)
		_rpc_settings.rpc_id(id, GameSettings.mults)
		_rpc_snapshot.rpc_id(id, roles, mage_id, phase, time_left, _winner, _reason)
		_snapshots.erase(id)


func _on_session_started() -> void:
	_session_closed = false
	if _bot_count:
		_bot_count.value = clampi(int(NetworkManager.args.get("bots", 0)), 0, 5)


func _on_session_ended(_message: String) -> void:
	# WHY: queued player bodies can survive one frame after the transport is removed.
	_session_closed = true
	_exploring = false
	_lobby.visible = false
	_lobby_background.visible = false
	_known.clear()
	_pending_roles.clear()
	_snapshots.clear()
	_living_villagers.clear()
	_living_mages.clear()
	roles.clear()
	mage_id = 0
	mage_count = _default_mage_count()
	_winner = Enums.Winner.NONE
	_reason = ""
	_autostart_used = false
	_rpc_phase(Enums.Phase.LOBBY, 0.0)


@rpc("authority", "call_local", "reliable")
func _rpc_roles(assigned: Dictionary, chosen: int) -> void:
	mage_id = chosen
	for id in assigned:
		if not roles.has(id) or roles[id] != assigned[id]:
			_pending_roles[id] = assigned[id]
	roles = assigned.duplicate()
	for id in _pending_roles.keys():
		if not roles.has(id):
			_pending_roles.erase(id)
	_apply_pending_roles()


func _apply_pending_roles() -> void:
	for id in _pending_roles.keys():
		var p := Players.get_player(id)
		if p == null or not p.is_node_ready():
			continue
		var role: int = _pending_roles[id]
		p.set_role(role)
		_pending_roles.erase(id)
		GameEvents.role_assigned.emit(id, role)
		print("[Match] Role ", id, " ", Enums.Role.keys()[role])


@rpc("authority", "call_local", "reliable")
func _rpc_phase(next: int, duration: float) -> void:
	phase = next
	time_left = duration
	_update_blind()
	print("[Match] Phase ", Enums.Phase.keys()[phase], " duration=", duration)
	GameEvents.phase_changed.emit(phase, duration)


@rpc("authority", "call_local", "reliable")
func _rpc_result(winner: int, reason: String) -> void:
	_winner = winner
	_reason = reason
	print("[Match] Winner ", Enums.Winner.keys()[winner], " reason=", reason)
	GameEvents.round_ended.emit(winner, reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(assigned: Dictionary, chosen: int, current: int, seconds: float, winner: int, reason: String) -> void:
	# WHY: merge the full roster without repeating role events already received live.
	_rpc_roles(assigned, chosen)
	if winner != Enums.Winner.NONE and current == Enums.Phase.RESULTS:
		_rpc_result(winner, reason)
	_rpc_phase(current, seconds)
	print("[Match] Snapshot phase=", Enums.Phase.keys()[current])


@rpc("authority", "call_local", "reliable")
func _rpc_pick(chosen: int) -> void:
	mage_id = chosen


@rpc("authority", "call_local", "reliable")
func _rpc_mage_count(count: int) -> void:
	mage_count = clampi(count, 1, MAX_MAGES)


@rpc("authority", "call_local", "reliable")
func _rpc_settings(mults: Dictionary) -> void:
	GameSettings.set_mults(mults)
	if _settings_panel:
		_settings_panel.show_mults(mults)


func _on_settings_changed(mults: Dictionary) -> void:
	if Net.is_server(self) and phase == Enums.Phase.LOBBY:
		Net.broadcast(self, &"_rpc_settings", [mults])


func _on_mage_count_changed(value: float) -> void:
	if Net.is_server(self) and phase == Enums.Phase.LOBBY:
		Net.broadcast(self, &"_rpc_mage_count", [int(value)])


func _on_mage_picked(index: int) -> void:
	if Net.is_server(self) and phase == Enums.Phase.LOBBY:
		Net.broadcast(self, &"_rpc_pick", [_pick.get_item_id(index)])


func _update_blind() -> void:
	if not is_node_ready():
		return
	if phase != Enums.Phase.ROLE_REVEAL and phase != Enums.Phase.HEAD_START:
		_blind.visible = false
		return
	var p := Players.local_player()
	_blind.visible = p != null and get_role(p.peer_id) == Enums.Role.MAGE \
		and (phase == Enums.Phase.ROLE_REVEAL or phase == Enums.Phase.HEAD_START)
	_blind_text.text = "You are the Mage\nVillagers are hiding… %d" % ceili(time_left)


func _input(event: InputEvent) -> void:
	if _exploring and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_exploring = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func _on_explore_town() -> void:
	# FIX(S05, Codex): solo map playtests need captured input before a multiplayer round starts.
	if NetworkManager.is_in_session() and phase == Enums.Phase.LOBBY:
		_exploring = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_ui() -> void:
	_update_blind()
	var was_visible := _lobby.visible
	_lobby.visible = NetworkManager.is_in_session() and phase == Enums.Phase.LOBBY and not _exploring
	_lobby_background.visible = _lobby.visible
	if DisplayServer.get_name() != "headless":
		# FIX(S05, Codex): release the cursor on entry, not every frame while exploring.
		if _lobby.visible and not was_visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif was_visible and not _lobby.visible and NetworkManager.is_in_session():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var host := Net.is_server(self)
	$UI/Lobby/Content/Title.text = "HOST LOBBY" if host else "JOINED LOBBY"
	$UI/Lobby/Content/MageCountRow.visible = host
	$UI/Lobby/Content/BotCountLabel.visible = host
	_bot_count.visible = host
	_pick.visible = host
	_start.visible = host
	_invite.visible = host
	_settings_btn.visible = host and _lobby.visible
	if not _lobby.visible:
		_settings_panel.visible = false
	var roster := Players.all()
	_update_lobby_cards(roster)
	var key := ""
	var roster_names: Array[String] = []
	for p in roster:
		roster_names.append(p.display_name)
		key += "%d:%s;" % [p.peer_id, p.display_name]
	_roster_label.text = "PLAYERS   " + "   •   ".join(roster_names)
	if key != _roster_key:
		_roster_key = key
		_pick.clear()
		_pick.add_item("Random Mage", 0)
		for p in roster:
			_pick.add_item(p.display_name, p.peer_id)
	_pick.select(maxi(0, _pick.get_item_index(mage_id)))
	_pick.disabled = not Net.is_server(self)
	_count.editable = Net.is_server(self)
	_count.set_value_no_signal(mage_count)
	_bot_count.editable = Net.is_server(self)
	_invite.disabled = not SteamManager.available or SteamManager.lobby_id == 0
	var required := maxi(maxi(2, tuning.min_players), mage_count + 1)
	_start.disabled = not Net.is_server(self) or roster.size() < required
	var message := "Choose the Mage and start" if Net.is_server(self) else "Waiting for host"
	if Net.is_server(self) and roster.size() < required:
		message = "Need %d players (including at least one villager)" % required
	_status.text = message
	_player_count_label.text = "◆  ────  %d / %d PLAYERS  ────  ◆" % [roster.size(), NetworkManager.MAX_PLAYERS]
	_mage_caption.visible = host


func _style_lobby() -> void:
	_lobby.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lobby.offset_left = -600
	_lobby.offset_right = 600
	_lobby.offset_top = -330
	_lobby.offset_bottom = 330
	var theme := Theme.new()
	theme.default_font = UiStyle.body_font()
	theme.default_font_size = 18
	theme.set_color(&"font_color", &"Label", Color("f2dcae"))
	_lobby.theme = theme
	var panel := UiStyle.panel()
	panel.set_content_margin_all(24)
	_lobby.add_theme_stylebox_override("panel", panel)
	var content := $UI/Lobby/Content as Control
	content.custom_minimum_size = Vector2(1152, 612)
	var title := content.get_node("Title") as Label
	title.text = "HOST LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiStyle.title_font())
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	title.add_theme_color_override("font_outline_color", Color("5a2a10"))
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_color_override("font_shadow_color", Color("1a0610cc"))
	title.add_theme_constant_override("shadow_offset_y", 3)
	_player_count_label = UiStyle.ornament("2 / 6 PLAYERS", 22)
	content.add_child(_player_count_label)
	_mage_caption = UiStyle.caption("MAGE")
	content.add_child(_mage_caption)
	var mage_row := content.get_node("MageCountRow") as HBoxContainer
	var mage_label := mage_row.get_node("Label") as Label
	mage_label.text = "MAGES"
	mage_label.add_theme_font_override("font", UiStyle.title_font())
	mage_label.add_theme_font_size_override("font_size", 17)
	var bots_label := content.get_node("BotCountLabel") as Label
	bots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bots_label.add_theme_font_override("font", UiStyle.title_font())
	bots_label.add_theme_font_size_override("font_size", 17)
	for field: Control in [_pick, _count, _bot_count]:
		UiStyle.style_field(field)
	_start.text = "START ROUND"
	UiStyle.style_primary(_start, 30)
	var explore := content.get_node("Explore") as Button
	explore.text = "EXPLORE TOWN"
	UiStyle.style_dark(explore, 18)
	var help := content.get_node("ExploreHelp") as Label
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color("cfae84"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_override("font", UiStyle.italic_font())
	_status.add_theme_font_size_override("font_size", 18)
	_card_styles = {"filled": UiStyle.card(true), "empty": UiStyle.card(false), "you": UiStyle.card(true, true)}


func _layout_lobby() -> void:
	UiStyle.style_dark(_invite, 18)
	var content := $UI/Lobby/Content
	var right := 790.0
	var width := 350.0
	_place(content.get_node("Title"), Vector2(0, -6), Vector2(1152, 62))
	_place(_player_count_label, Vector2(0, 58), Vector2(1152, 32))
	_place(_status, Vector2(0, 574), Vector2(1152, 34))
	_place(_mage_caption, Vector2(right, 104), Vector2(width, 24))
	_place(_pick, Vector2(right, 130), Vector2(width, 42))
	_place(content.get_node("MageCountRow"), Vector2(right, 184), Vector2(width, 42))
	_place(content.get_node("BotCountLabel"), Vector2(right, 236), Vector2(width, 24))
	_place(_bot_count, Vector2(right, 262), Vector2(width, 42))
	_place(_invite, Vector2(right, 320), Vector2(width, 46))
	_place(_start, Vector2(right - 10, 380), Vector2(width + 20, 74))
	_place(content.get_node("Explore"), Vector2(right, 468), Vector2(width, 46))
	_place(content.get_node("ExploreHelp"), Vector2(right, 518), Vector2(width, 46))
	_slot_layout_count = -1 # cards are placed by _layout_slots() once the roster is known


## Builds the six player slot cards: portrait with ‹ › (own card only), name and villager line.
func _build_lobby_cards() -> void:
	var content := $UI/Lobby/Content
	var slot_frames: Array[PanelContainer] = []
	for i in NetworkManager.MAX_PLAYERS:
		var panel := PanelContainer.new()
		panel.name = "Slot%d" % i
		content.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(row)
		var prev := Button.new()
		prev.text = "‹"
		UiStyle.style_arrow(prev)
		prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		prev.pressed.connect(_change_character.bind(-1))
		row.add_child(prev)
		var frame := PanelContainer.new()
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color("1c0b14")
		frame_style.border_color = UiStyle.GOLD
		frame_style.set_border_width_all(3)
		frame_style.set_corner_radius_all(8)
		frame_style.set_content_margin_all(3)
		frame.add_theme_stylebox_override("panel", frame_style)
		slot_frames.append(frame)
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(frame)
		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(portrait)
		var empty := UiStyle.heading("❦", 54)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("8a5d3b"))
		frame.add_child(empty)
		var next := Button.new()
		next.text = "›"
		UiStyle.style_arrow(next)
		next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		next.pressed.connect(_change_character.bind(1))
		row.add_child(next)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(text)
		var name_label := UiStyle.heading("OPEN SLOT", 22)
		name_label.add_theme_constant_override("outline_size", 0)
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(name_label)
		var sub := UiStyle.footer("", 15)
		sub.add_theme_color_override("font_color", Color("e0c08f"))
		text.add_child(sub)
		_slots.append({"panel": panel, "portrait": portrait, "empty": empty, "name": name_label,
			"sub": sub, "prev": prev, "next": next, "frame": slot_frames[i]})


## Shows 6 cards (the design's party size), or more when more players joined, in two columns that
## shrink to fit the left half of the panel.
func _layout_slots(count: int) -> void:
	if count == _slot_layout_count:
		return
	_slot_layout_count = count
	var rows := ceili(count / 2.0)
	var gap := 14.0
	var height := (456.0 - gap * (rows - 1)) / rows
	var portrait := clampf(height - 26.0, 48.0, 112.0)
	for i in _slots.size():
		var slot := _slots[i]
		slot["panel"].visible = i < count
		if i >= count:
			continue
		_place(slot["panel"], Vector2(10, 104) + Vector2((i % 2) * 380, (i / 2) * (height + gap)), Vector2(364, height))
		slot["frame"].custom_minimum_size = Vector2(portrait, portrait)
		slot["empty"].add_theme_font_size_override("font_size", int(portrait * 0.5))


## Fills the slot cards from the roster: host first, then other humans, then bots. Every peer sees the
## same cards because `villager_skin` and names are replicated on each Player.
func _update_lobby_cards(roster: Array[Node]) -> void:
	if _slots.is_empty():
		return
	_layout_slots(clampi(roster.size() + roster.size() % 2, 6, _slots.size()))
	var ordered := roster.duplicate()
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.peer_id < b.peer_id)
	for i in _slots.size():
		var slot := _slots[i]
		var p: Player = ordered[i] as Player if i < ordered.size() else null
		var mine := p != null and p.is_local()
		slot["panel"].add_theme_stylebox_override("panel", _card_styles["you" if mine else ("filled" if p else "empty")])
		# WHY: hide arrows by alpha, not visibility, so every card's portrait sits in the same place.
		for arrow: Button in [slot["prev"], slot["next"]]:
			arrow.modulate.a = 1.0 if mine else 0.0
			arrow.disabled = not mine
			arrow.mouse_filter = Control.MOUSE_FILTER_STOP if mine else Control.MOUSE_FILTER_IGNORE
		slot["portrait"].visible = p != null
		slot["empty"].visible = p == null
		if p == null:
			slot["name"].text = "OPEN SLOT"
			slot["name"].add_theme_color_override("font_color", Color("c99a6a"))
			slot["sub"].text = ""
			continue
		var skin := VillagerSkins.clamp_id(p.villager_skin)
		slot["portrait"].texture = _portraits[clampi(skin, 0, _portraits.size() - 1)]
		slot["name"].text = p.display_name.to_upper()
		slot["name"].add_theme_color_override("font_color", UiStyle.GOLD)
		var tags: Array[String] = []
		if p.peer_id == 1:
			tags.append("Host")
		if mine:
			tags.append("You")
		if p.is_bot:
			tags.append("Bot")
		var who := "  ◆  ".join(tags)
		slot["sub"].text = "%s Villager%s" % [VillagerSkins.NAMES[skin], ("\n" + who) if who != "" else ""]


func _place(control: Control, pos: Vector2, dimensions: Vector2) -> void:
	control.position = pos
	control.size = dimensions


## Cycles the local player's villager body; the synchronizer shows it on everyone's lobby cards.
func _change_character(direction := 1) -> void:
	var local := Players.local_player()
	if local != null and phase == Enums.Phase.LOBBY:
		var count := mini(VillagerSkins.NAMES.size(), _portraits.size())
		var next: int = posmod(local.villager_skin + direction, count)
		VillagerSkins.local = next
		local.villager_skin = next
