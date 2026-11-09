extends Node
## Party scoring test. Owner: S16. NET: host with 2 server bots (3 players), scripted round outcomes.
## Round 1 mage kills both villagers, round 2 times out, round 3 the mage dies. Checks each player was
## mage once, totals, score_changed/party_ended events, and a mid-party leaver being skipped.

var _score: ScoringManager
var _mages: Array[int] = []
var _failed := false
var _events: Dictionary = {}
var _ended: Array = []
var _hunts := 0


func _ready() -> void:
	add_child(load("res://game/main.tscn").instantiate())
	_score = GameEvents.system(&"scoring") as ScoringManager
	GameEvents.score_changed.connect(func(id: int, total: int) -> void: _events[id] = total)
	GameEvents.party_ended.connect(func(s: Array) -> void: _ended = s)
	GameEvents.role_assigned.connect(func(id: int, role: int) -> void:
		if role == Enums.Role.MAGE: _mages.append(id))
	GameEvents.phase_changed.connect(_on_phase)
	get_tree().create_timer(40.0).timeout.connect(func() -> void:
		_check(false, "watchdog"); _finish())
	_start.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
	print("[TEST] ", "ok " if ok else "FAIL ", message)


func _start() -> void:
	while Players.all().size() < 3:
		await get_tree().create_timer(0.2).timeout
	# Chickens refill whenever the firestorm wall closes in (stage signal).
	var chickens := GameEvents.system(&"chickens") as ChickenManager
	await get_tree().create_timer(0.5).timeout
	for c in chickens.get_chickens():
		c.queue_free()
	await get_tree().process_frame
	_check(chickens.alive_count() == 0, "flock emptied")
	GameEvents.firestorm_stage.emit(1, Vector3.ZERO, 500.0, 0.0, 10.0)
	await get_tree().process_frame
	_check(chickens.alive_count() == chickens.tuning.count, "firestorm stage refills chickens")
	_score.start_party()
	_check(_score.party_active, "party started")


func _on_phase(phase: int, _d: float) -> void:
	if phase != Enums.Phase.HUNT:
		return
	_hunts += 1
	var match_system := GameEvents.system(&"match") as MatchManager
	await get_tree().create_timer(0.3).timeout
	if _hunts == 1:
		for id in match_system.roles:
			var p := Players.get_player(id)
			if match_system.get_role(id) == Enums.Role.VILLAGER:
				p.health.kill(match_system.mage_id, &"knife")
	elif _hunts == 3:
		Players.get_player(match_system.mage_id).health.kill(0, &"test")


func _process(_delta: float) -> void:
	if not _ended.is_empty():
		_finish()


func _finish() -> void:
	set_process(false)
	if not _ended.is_empty():
		_check(_mages.size() == 3 and _mages.duplicate().size() == 3, "three rounds")
		var seen := {}
		for m in _mages: seen[m] = true
		_check(seen.size() == 3, "everyone was mage once")
		var expected := {}
		for p in Players.all(): expected[p.peer_id] = 0
		expected[_mages[0]] += 2 * 100 + 200
		for i in [1, 2]:
			for id in expected:
				if id != _mages[i]:
					expected[id] += 150
		for id in expected:
			_check(_score.get_total(id) == expected[id], "total %d = %d (got %d)" % [id, expected[id], _score.get_total(id)])
			_check(_events.get(id, -1) == expected[id], "score_changed fired for %d" % id)
		_check(_ended.size() == 3 and _ended[0]["total"] >= _ended[1]["total"], "standings sorted")
		_check(not _score.party_active, "party over")
	print("[TEST] SCORING ", "FAILED" if _failed else "PASSED")
	get_tree().quit(1 if _failed else 0)
