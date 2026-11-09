class_name MatchManager
extends Node
## Server-run round state machine and lobby. Owner: S04. Runs at Systems/Match on every peer.
## Public API: phase, time_left, mage_id, roles, tuning; start_round(), end_round(), get_role(),
## is_round_active(). RPCs emit GameEvents phase_changed/role_assigned/round_ended on every peer.
## Player.set_role() always precedes role_assigned, including delayed spawns and late-join snapshots.

## Current Enums.Phase (synced, with events delivered through reliable RPCs).
var phase: int = Enums.Phase.LOBBY
## Server's seconds remaining, replicated at 10 Hz for the HUD.
var time_left := 0.0
## Selected mage in the lobby (0 = random), actual mage during a round.
var mage_id := 0
## Peer id -> Enums.Role for this round, including late spectators.
var roles: Dictionary = {}
## Private tuning copy, including --tune=match.* overrides.
var tuning: MatchTuning

var _known: Dictionary = {}
var _pending_roles: Dictionary = {}
var _snapshots: Array[int] = []
var _living_villagers: Dictionary = {}
var _winner: int = Enums.Winner.NONE
var _reason := ""
var _autostart_used := false
var _session_closed := false
var _roster_key := "uninitialized"
var _mage_count: SpinBox

@onready var _lobby: PanelContainer = $UI/Lobby
@onready var _pick: OptionButton = $UI/Lobby/Content/MagePick
@onready var _start: Button = $UI/Lobby/Content/Start
@onready var _status: Label = $UI/Lobby/Content/Status
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
	_mage_count = SpinBox.new()
	_mage_count.min_value = 1
	_mage_count.max_value = 5
	_mage_count.step = 1
	_mage_count.value = clampi(int(NetworkManager.args.get("mages", 1)), 1, 5)
	_mage_count.value_changed.connect(func(value: float):
		if Net.is_server(self) and phase == Enums.Phase.LOBBY:
			NetworkManager.args["mages"] = int(value))
	var count_label := Label.new()
	count_label.text = "MAGES"
	$UI/Lobby/Content.add_child(count_label)
	$UI/Lobby/Content.add_child(_mage_count)
	$UI/Lobby/Content.move_child(count_label, 3)
	$UI/Lobby/Content.move_child(_mage_count, 4)
	_style_lobby()


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
	if roster.size() < maxi(maxi(2, tuning.min_players), int(NetworkManager.args.get("mages", 1)) + 1):
		return
	var chosen := selected_mage if selected_mage != 0 else mage_id
	if chosen == 0:
		chosen = int(roster.pick_random().peer_id)
	if Players.get_player(chosen) == null:
		return
	_winner = Enums.Winner.NONE
	_reason = ""
	_living_villagers.clear()
	var assigned := {}
	var mage_ids: Array = [chosen]
	var candidates := roster.duplicate()
	candidates.shuffle()
	var count := clampi(int(NetworkManager.args.get("mages", 1)), 1, roster.size() - 1)
	for candidate in candidates:
		if mage_ids.size() >= count:
			break
		if candidate.peer_id != chosen:
			mage_ids.append(candidate.peer_id)
	for p in roster:
		assigned[p.peer_id] = Enums.Role.MAGE if mage_ids.has(p.peer_id) else Enums.Role.VILLAGER
		_known[p.peer_id] = true
		if not mage_ids.has(p.peer_id):
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


## True during HEAD_START and HUNT (the public gameplay contract).
func is_round_active() -> bool:
	return phase == Enums.Phase.HEAD_START or phase == Enums.Phase.HUNT


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
	var index := 0
	for p in Players.all():
		if get_role(p.peer_id) == Enums.Role.MAGE:
			var points := _clear_spawns(p, mages)
			var pos: Vector3 = points.pick_random() if not points.is_empty() else Vector3(0, 1, 0)
			print("[Match] Spawn ", p.peer_id, " MAGE at ", pos)
			p.teleport(pos)
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
	_change_phase(Enums.Phase.LOBBY, 0.0)


func _on_player_died(id: int, _killer: int, _cause: StringName) -> void:
	if not Net.is_server(self) or not _round_started():
		return
	if get_role(id) == Enums.Role.MAGE:
		_check_mages(id, "mage_died")
	elif get_role(id) == Enums.Role.VILLAGER:
		_living_villagers.erase(id)
		_check_villagers()


func _check_mages(excluded: int, reason: String) -> void:
	for p in Players.all():
		if p.peer_id != excluded and get_role(p.peer_id) == Enums.Role.MAGE and p.health.is_alive:
			return
	end_round(Enums.Winner.VILLAGERS, reason)


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
	if _round_started():
		if get_role(id) == Enums.Role.MAGE:
			_check_mages(id, "mage_left")
		elif get_role(id) == Enums.Role.VILLAGER:
			_living_villagers.erase(id)
			_check_villagers()
	_known.erase(id)
	_snapshots.erase(id)
	var remaining := roles.duplicate()
	remaining.erase(id)
	Net.broadcast(self, &"_rpc_roles", [remaining, 0 if phase == Enums.Phase.LOBBY and id == mage_id else mage_id])


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
		_rpc_snapshot.rpc_id(id, roles, mage_id, phase, time_left, _winner, _reason)
		_snapshots.erase(id)


func _on_session_started() -> void:
	_session_closed = false
	if _mage_count:
		_mage_count.value = clampi(int(NetworkManager.args.get("mages", 1)), 1, 5)


func _on_session_ended(_message: String) -> void:
	# WHY: queued player bodies can survive one frame after the transport is removed.
	_session_closed = true
	_lobby.visible = false
	_known.clear()
	_pending_roles.clear()
	_snapshots.clear()
	_living_villagers.clear()
	roles.clear()
	mage_id = 0
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


func _on_explore_town() -> void:
	# FIX(S05, Codex): solo map playtests need captured input before a multiplayer round starts.
	if NetworkManager.is_in_session() and phase == Enums.Phase.LOBBY:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_ui() -> void:
	_update_blind()
	var was_visible := _lobby.visible
	_lobby.visible = NetworkManager.is_in_session() and phase == Enums.Phase.LOBBY
	if DisplayServer.get_name() != "headless":
		# FIX(S05, Codex): release the cursor on entry, not every frame while exploring.
		if _lobby.visible and not was_visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif was_visible and not _lobby.visible and NetworkManager.is_in_session():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var roster := Players.all()
	var key := ""
	for p in roster:
		key += "%d:%s;" % [p.peer_id, p.display_name]
	if key != _roster_key:
		_roster_key = key
		_pick.clear()
		_pick.add_item("Random Mage", 0)
		for p in roster:
			_pick.add_item(p.display_name, p.peer_id)
	_pick.select(maxi(0, _pick.get_item_index(mage_id)))
	_pick.disabled = not Net.is_server(self)
	_mage_count.editable = Net.is_server(self)
	var required := maxi(maxi(2, tuning.min_players), int(NetworkManager.args.get("mages", 1)) + 1)
	_start.disabled = not Net.is_server(self) or roster.size() < required
	var message := "Choose the Mage and start" if Net.is_server(self) else "Waiting for host"
	if Net.is_server(self) and roster.size() < required:
		message = "Need %d players (including at least one villager)" % required
	_status.text = "%d players — %s" % [roster.size(), message]


func _style_lobby() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("391b2bec")
	panel.border_color = Color("d1994f")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(5)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	_lobby.add_theme_stylebox_override("panel", panel)
	for button in [_start, $UI/Lobby/Content/Explore]:
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("67362f")
		normal.border_color = Color("c6904e")
		normal.set_border_width_all(2)
		normal.set_content_margin_all(8)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color("a84c1f")
		hover.border_color = Color("ffcc67")
		hover.shadow_color = Color("ff8a2388")
		hover.shadow_size = 8
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_color_override("font_color", Color("ffe5b1"))
