extends Node
## Headless multiplayer integration assertions. Owner: S04. Runs on host and clients.
## Public API: none; boots the real Main and observes GameEvents / Player hooks.

var _match: MatchManager
var _failures := 0
var _phases: Array[int] = []
var _results := 0
var _started := false
var _finished := false
var _timer_sample := -1.0
var _scenario := ""
var _late := false


func _ready() -> void:
	_scenario = String(NetworkManager.args.get("match-case", "timeout"))
	_late = NetworkManager.args.has("late-client")
	GameEvents.role_assigned.connect(_on_role)
	GameEvents.phase_changed.connect(_on_phase)
	GameEvents.round_ended.connect(_on_result)
	add_child(load("res://game/main.tscn").instantiate())
	_match = GameEvents.system(&"match") as MatchManager
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		_check(false, "watchdog timeout"); _finish())


func _process(_delta: float) -> void:
	if _match == null or _finished:
		return
	if Net.is_server(self) and _scenario == "mage_left" and not _started and Players.all().size() == 3:
		for p in Players.all():
			if p.display_name != "C1":
				continue
			var picker := _match.get_node("UI/Lobby/Content/MagePick") as OptionButton
			var index := picker.get_item_index(p.peer_id)
			if index < 0:
				return
			_started = true
			_match.start_round(-1)
			_check(_match.phase == Enums.Phase.LOBBY, "invalid mage cannot start round")
			picker.select(index)
			picker.item_selected.emit(index)
			_check(_match.mage_id == p.peer_id, "host lobby picker sets mage")
			_match.start_round()
	if _match.phase == Enums.Phase.HUNT:
		if _timer_sample < 0.0:
			_timer_sample = _match.time_left
		elif _timer_sample - _match.time_left > 0.15:
			set_meta(&"timer_ticked", true)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", message])


func _on_role(id: int, role: int) -> void:
	var p := Players.get_player(id)
	_check(p != null and p.role == role, "role event follows Player.set_role")
	if role == Enums.Role.MAGE:
		_check(p.get_ability(&"MageAbilities") != null, "mage abilities exist at role event")
	if _late and p.is_local():
		_check(role == Enums.Role.SPECTATOR or role == Enums.Role.NONE, "late join is spectator until lobby")


func _on_phase(next: int, duration: float) -> void:
	_phases.append(next)
	if next == Enums.Phase.HUNT:
		_timer_sample = duration
	# RPC order guarantees role/lock updates precede the phase signal for existing peers.
	if next == Enums.Phase.ROLE_REVEAL:
		_check(_match.roles.size() == (2 if _scenario == "late_join" else 3), "round roster")
		_check(_match.roles.values().count(Enums.Role.MAGE) == 1, "exactly one mage assigned")
		if Net.is_server(self):
			var chosen := _match.mage_id
			_match.start_round(1)
			_check(_match.mage_id == chosen, "cannot restart active round")
	if next == Enums.Phase.HEAD_START or next == Enums.Phase.HUNT:
		_check_phase.call_deferred(next)
	if next == Enums.Phase.HUNT and Net.is_server(self):
		get_tree().create_timer(0.4).timeout.connect(_exercise_outcome)
	if next == Enums.Phase.HUNT and _scenario == "mage_left" and NetworkManager.local_name == "C1":
		get_tree().create_timer(0.45).timeout.connect(func() -> void:
			NetworkManager.leave("test mage leaves")
			print("[TEST] MATCH CLIENT LEFT")
			get_tree().quit(_failures))
	if next == Enums.Phase.LOBBY and _results > 0:
		_check_lobby.call_deferred()


func _check_phase(next: int) -> void:
	for p in Players.all():
		var role := _match.get_role(p.peer_id)
		if next == Enums.Phase.HEAD_START:
			_check(p.can_control() == (role == Enums.Role.VILLAGER), "head start locks only mage/spectators")
		elif role != Enums.Role.SPECTATOR:
			_check(p.can_control(), "hunt releases participants")
		else:
			_check(not p.can_control(), "late spectator input locked")
		if Net.is_server(self):
			_check(p.health.invulnerable == (next == Enums.Phase.HEAD_START or role == Enums.Role.SPECTATOR), "phase damage protection")
	if not Net.is_server(self):
		var before := _match.phase
		_match.start_round(1)
		_match.end_round(Enums.Winner.MAGE, "unauthorized")
		_check(_match.phase == before, "client cannot decide outcomes")
	if next == Enums.Phase.HEAD_START:
		for p in Players.all():
			var group := &"mage_spawn" if p.role == Enums.Role.MAGE else &"villager_spawn"
			var found := false
			for marker in get_tree().get_nodes_in_group(group):
				if Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(marker.global_position.x, marker.global_position.z)) < 0.2:
					found = true
			_check(found, "participant teleported to role spawn")
	var local := Players.local_player()
	if local != null:
		_check(_match.get_node("UI/Blind").visible == (local.role == Enums.Role.MAGE and next == Enums.Phase.HEAD_START), "mage blinded only before hunt")


func _exercise_outcome() -> void:
	match _scenario:
		"all_dead":
			for p in Players.alive_with_role(Enums.Role.VILLAGER):
				p.health.kill(_match.mage_id, &"test")
		"mage_died":
			Players.get_player(_match.mage_id).health.kill(0, &"firestorm")
		"late_join":
			# A spectator must be ignored by the all-villagers-dead condition.
			get_tree().create_timer(1.4).timeout.connect(func() -> void:
				for p in Players.alive_with_role(Enums.Role.VILLAGER):
					p.health.kill(_match.mage_id, &"test"))


func _on_result(winner: int, reason: String) -> void:
	_results += 1
	_check(_results == 1, "round result emitted once")
	_check(_match.phase == Enums.Phase.HUNT, "round result precedes RESULTS")
	var expected := {"timeout": "timeout", "all_dead": "all_dead", "mage_died": "mage_died", "mage_left": "mage_left", "late_join": "all_dead"}
	_check(reason == expected[_scenario], "expected winner reason " + reason)
	_check(winner == (Enums.Winner.MAGE if reason == "all_dead" else Enums.Winner.VILLAGERS), "expected winner")
	if Net.is_server(self):
		_match.end_round(Enums.Winner.MAGE, "duplicate")


func _check_lobby() -> void:
	if _finished:
		return
	_check(_phases.has(Enums.Phase.RESULTS), "RESULTS observed")
	if not _late:
		for next in [Enums.Phase.ROLE_REVEAL, Enums.Phase.HEAD_START, Enums.Phase.HUNT]:
			_check(_phases.has(next), "phase observed " + Enums.Phase.keys()[next])
	_check(bool(get_meta(&"timer_ticked", false)), "HUD timer decreased")
	for p in Players.all():
		_check(p.role == Enums.Role.NONE and p.is_alive and p.can_control(), "lobby resets roles, health and locks")
	if _late:
		_check(_match.roles.size() == 3, "late join received full roster")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("[TEST] MATCH %s (%s, %s)" % ["PASSED" if _failures == 0 else "FAILED", _scenario, NetworkManager.local_name])
	# Keep peers connected until everyone has observed the final lobby RPC.
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit(0 if _failures == 0 else 1))
