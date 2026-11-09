class_name ScoringManager
extends Node
## Points per round + party mode (everyone is mage once). Owner: S16. Registered as
## GameEvents.system(&"scoring").
## NET: server counts from GameEvents (player_died, round_ended, phase_changed); fires score_changed /
## party_ended on all peers. In party mode it starts each round with MatchManager.start_round(mage_id).
## Public API: `party_active`, `totals`, `get_total(peer_id)`, `start_party(order)`, `standings()`,
## `mage_order`, `round_index`; GameEvents.score_changed(peer_id, total), party_ended(standings).
## CLI: `--party` (+ `--party-players=N`, default match min_players) starts a party once enough players joined.
## `standings` = Array of {peer_id:int, name:String, total:int} sorted best first (winner = index 0).

## True while a party (multi-round session) runs.
var party_active := false
## peer_id -> total points (replicated through score_changed; late joiners get a snapshot).
var totals: Dictionary = {}
## Mage order of the running/last party (peer ids). Players that left are skipped when their turn comes.
var mage_order: Array[int] = []
## Number of rounds started in the current party.
var round_index := 0
var tuning: ScoringTuning

var _names: Dictionary = {}
var _hunt_start_msec := -1
var _round_open := false
var _dead_at: Dictionary = {} # villager id -> survival seconds (server)
var _party_autostarted := false


func _enter_tree() -> void:
	GameEvents.register_system(&"scoring", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/scoring/tuning_scoring.tres", "scoring") as ScoringTuning
	GameEvents.phase_changed.connect(_on_phase)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.round_ended.connect(_on_round_ended)
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.session_ended.connect(_on_session_ended)


func _process(_delta: float) -> void:
	if _party_autostarted or not NetworkManager.args.has("party") or not Net.is_server(self):
		return
	var match_system := _match()
	if match_system == null or match_system.phase != Enums.Phase.LOBBY:
		return
	var needed := maxi(2, int(NetworkManager.args.get("party-players", match_system.tuning.min_players)))
	if Players.all().size() >= needed:
		_party_autostarted = true
		start_party()


## Party total for a peer. Any peer.
func get_total(peer_id: int) -> int:
	return totals.get(peer_id, 0)


## Current standings, best first. Any peer.
func standings() -> Array:
	var list: Array = []
	for id in totals:
		list.append({"peer_id": id, "name": _names.get(id, "Player %d" % id), "total": totals[id]})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total"] > b["total"])
	return list


## NET: server only. Starts a party from the LOBBY: one round per player, each player mage once.
## `order` = mage order (peer ids); empty = random order of everyone connected now.
func start_party(order: Array = []) -> void:
	if not Net.is_server(self) or party_active:
		return
	var match_system := _match()
	if match_system == null or match_system.phase != Enums.Phase.LOBBY:
		return
	var ids: Array[int] = []
	for id in order:
		if Players.get_player(id) != null and not ids.has(int(id)):
			ids.append(int(id))
	if ids.is_empty():
		for p in Players.all():
			ids.append(p.peer_id)
		ids.shuffle()
	mage_order = ids
	round_index = 0
	for p in Players.all():
		_names[p.peer_id] = p.display_name
		_set_total(p.peer_id, 0, true)
	party_active = true
	print("[Score] Party start, mage order ", mage_order)
	_start_next_round.call_deferred()


func _match() -> MatchManager:
	return GameEvents.system(&"match") as MatchManager


func _set_total(peer_id: int, total: int, force := false) -> void:
	if not force and totals.get(peer_id, 0) == total:
		return
	Net.broadcast(self, &"_rpc_score", [peer_id, total, _names.get(peer_id, "")])


func _add(peer_id: int, points: int) -> void:
	if points == 0 or peer_id == 0:
		return
	if not _names.has(peer_id):
		var p := Players.get_player(peer_id)
		if p != null:
			_names[peer_id] = p.display_name
	_set_total(peer_id, get_total(peer_id) + points)
	print("[Score] ", peer_id, " +", points, " -> ", get_total(peer_id))


func _on_phase(phase: int, _duration: float) -> void:
	if phase == Enums.Phase.HUNT:
		_hunt_start_msec = Time.get_ticks_msec()
	elif phase == Enums.Phase.ROLE_REVEAL:
		_round_open = true
		_hunt_start_msec = -1
		_dead_at.clear()
	elif phase == Enums.Phase.LOBBY and party_active and Net.is_server(self):
		_start_next_round.call_deferred()


func _survived() -> float:
	return 0.0 if _hunt_start_msec < 0 else (Time.get_ticks_msec() - _hunt_start_msec) / 1000.0


func _on_player_died(id: int, killer: int, _cause: StringName) -> void:
	var match_system := _match()
	if not Net.is_server(self) or not _round_open or match_system == null:
		return
	if match_system.get_role(id) != Enums.Role.VILLAGER:
		return
	_dead_at[id] = _survived()
	if killer != 0 and killer == match_system.mage_id:
		_add(killer, tuning.mage_per_kill)


func _on_round_ended(winner: int, _reason: String) -> void:
	# WHY: the round can end inside the killing blow's own signal chain, before our player_died handler
	# ran; settle next frame so that last kill / death time is counted.
	if Net.is_server(self) and _round_open:
		_settle.call_deferred(winner, _survived())


func _settle(winner: int, total_time: float) -> void:
	var match_system := _match()
	if not _round_open or match_system == null:
		return
	_round_open = false
	if winner == Enums.Winner.MAGE:
		_add(match_system.mage_id, tuning.mage_win_bonus)
	for id in match_system.roles:
		if match_system.get_role(id) != Enums.Role.VILLAGER:
			continue
		var seconds: float = _dead_at.get(id, total_time)
		var points := int(seconds * tuning.villager_per_10s / 10.0)
		if winner == Enums.Winner.VILLAGERS:
			points += tuning.villager_win_bonus
		_add(id, points)


## Starts the next mage's round, skipping players who left; ends the party when none are left.
func _start_next_round() -> void:
	var match_system := _match()
	if not party_active or not Net.is_server(self) or match_system == null \
			or match_system.phase != Enums.Phase.LOBBY:
		return
	while round_index < mage_order.size() and Players.get_player(mage_order[round_index]) == null:
		print("[Score] Skip mage turn of ", mage_order[round_index], " (left)")
		round_index += 1
	if round_index >= mage_order.size() or Players.all().size() < maxi(2, match_system.tuning.min_players):
		Net.broadcast(self, &"_rpc_party_ended", [standings()])
		return
	var mage: int = mage_order[round_index]
	round_index += 1
	print("[Score] Party round ", round_index, "/", mage_order.size(), " mage ", mage)
	match_system.start_round(mage)


func _on_registered(id: int, player_name: String) -> void:
	_names[id] = player_name
	if not Net.is_server(self) or id == 1:
		return
	_rpc_snapshot.rpc_id(id, totals, _names, party_active)


func _on_session_ended(_message: String) -> void:
	party_active = false
	totals.clear()
	_names.clear()
	mage_order.clear()
	round_index = 0
	_round_open = false
	_party_autostarted = false


@rpc("authority", "call_local", "reliable")
func _rpc_score(peer_id: int, total: int, player_name: String) -> void:
	totals[peer_id] = total
	if player_name != "":
		_names[peer_id] = player_name
	GameEvents.score_changed.emit(peer_id, total)


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(all_totals: Dictionary, names: Dictionary, active: bool) -> void:
	_names = names.duplicate()
	party_active = active
	for id in all_totals:
		_rpc_score(id, all_totals[id], "")


@rpc("authority", "call_local", "reliable")
func _rpc_party_ended(final: Array) -> void:
	party_active = false
	print("[Score] Party ended, winner ", final[0]["name"] if not final.is_empty() else "-")
	GameEvents.party_ended.emit(final)
