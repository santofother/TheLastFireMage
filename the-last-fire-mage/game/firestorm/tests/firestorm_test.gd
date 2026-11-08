extends Node
## Storm integration over the real Main, Match, Power and Health. Owner: S14.
## NET: host, an early client, and a client joining during the first storm warning for stage 2.

const _BOT_ID := Players.BOT_ID_BASE + 30
const _CAUSE := &"firestorm"

var _storm: FirestormManager
var _match: MatchManager
var _power: PowerManager
var _stages: Array[int] = []
var _warnings: Array[int] = []
var _failed := false
var _damaged := false
var _mage_died := false
var _round_won := false
var _finished := false
var _closed := false
var _saw_plan := false
var _late := false
var _hosting := false
var _previous_radius := INF


func _ready() -> void:
	_late = NetworkManager.args.has("late-client")
	_hosting = NetworkManager.args.has("host")
	GameEvents.firestorm_stage.connect(_on_stage)
	GameEvents.firestorm_warning.connect(_on_warning)
	GameEvents.player_damaged.connect(_on_damage)
	GameEvents.player_died.connect(_on_death)
	GameEvents.round_ended.connect(_on_result)
	GameEvents.phase_changed.connect(_on_phase)
	add_child(load("res://game/main.tscn").instantiate())
	_storm = GameEvents.system(&"firestorm") as FirestormManager
	_match = GameEvents.system(&"match") as MatchManager
	_power = GameEvents.system(&"power") as PowerManager
	if _hosting:
		NetworkManager.player_registered.connect(_start_when_ready)
	get_tree().create_timer(18.0).timeout.connect(func() -> void:
		_check(false, "watchdog timeout")
		get_tree().quit(1))


func _start_when_ready(id: int, _pname: String) -> void:
	if id != 1 and _match.phase == Enums.Phase.LOBBY:
		_start_round.call_deferred()


func _start_round() -> void:
	GameEvents.system(&"main").spawn_player(_BOT_ID, "Storm Bot", true)
	_match.start_round(1)


func _process(_delta: float) -> void:
	if not _storm:
		return
	if not _saw_plan and _storm.final_zone_radius > 0.0:
		_saw_plan = true
		_check_plan()
	if _storm.stage == 0:
		_previous_radius = INF
		return
	var radius := _storm.zone_radius
	if radius > _previous_radius + 0.001:
		_check(false, "the ring must shrink monotonically")
	_previous_radius = radius
	_closed = _closed or is_equal_approx(radius, _storm.final_zone_radius)


func _on_phase(phase: int, _duration: float) -> void:
	if phase == Enums.Phase.HUNT and _hosting:
		var bot := Players.get_player(_BOT_ID) as Player
		bot.set_physics_process(false)
		bot.global_position = Vector3(30.0, 1.0, 0.0)
	elif phase == Enums.Phase.LOBBY and _round_won and not _finished:
		_finish.call_deferred()


func _check_plan() -> void:
	_check(is_equal_approx(_storm.final_zone_radius, 2.0), "final ring announced in HUNT")
	if not _late:
		_check(_storm.stage == 0 and _storm.is_inside(Vector3(100.0, 0.0, 100.0)),
			"no damage boundary before activation")


func _on_stage(number: int, target: Vector3, radius: float, required: float, time_to_next: float) -> void:
	_stages.append(number)
	_check(required == [0.0, 3.0, 6.0, 10.0][number - 1] and _storm.required_power() == required,
		"stage %d matches S13 power tier" % number)
	_check(_storm.is_inside(_storm.zone_center + Vector3.UP * 100.0), "safe zone is horizontal")
	_check((_storm.zone_radius + 0.001 >= radius) and (time_to_next > 0.0) == (number < 4),
		"stage reports target radius and next-stage time")
	if number == 4:
		_check(target.is_equal_approx(_storm.final_zone_center) and radius == _storm.final_zone_radius,
			"last stage closes at the announced destination")
	if _hosting and number == 2:
		# Let the mage recover from a brief deficit, then satisfy the third threshold as well.
		get_tree().create_timer(0.45).timeout.connect(func() -> void: _power.add_power(6.0, &"test"))


func _on_warning(number: int, seconds: float) -> void:
	_warnings.append(number)
	_check(number == _storm.stage + 1 and seconds > 0.0 and seconds <= 1.1, "warning precedes its stage")
	if _hosting and number == 2:
		print("[TEST] FIRESTORM JOIN WINDOW")


func _on_damage(id: int, amount: float, source: int, cause: StringName) -> void:
	if id == _BOT_ID and cause == _CAUSE:
		_damaged = true
		_check(source == 0 and amount > 0.0, "environment damages the outside bot")


func _on_death(id: int, killer: int, cause: StringName) -> void:
	if id == 1:
		_mage_died = true
		_check(killer == 0 and cause == _CAUSE and _stages.back() == 4 and _closed,
			"mage survives earlier deficit and dies to final-stage firestorm")


func _on_result(winner: int, reason: String) -> void:
	_round_won = true
	_check(winner == Enums.Winner.VILLAGERS and reason == "mage_died", "Match awards villagers the round")


func _finish() -> void:
	_finished = true
	_check(_stages == [1, 2, 3, 4], "all stages delivered including current stage for late client")
	_check(_warnings == ([2, 3, 4] if _late else [1, 2, 3, 4]), "all applicable warnings delivered")
	_check(_saw_plan and _damaged and _mage_died, "plan and health events reached this peer")
	_check(_storm.stage == 0 and _storm.required_power() == 0.0 and _storm.final_zone_radius == 0.0,
		"storm state cleared on return to lobby")
	print("[TEST] FIRESTORM PASSED" if not _failed else "[TEST] FAIL FIRESTORM")
	# Close the host first, after the clients have consumed the lobby reset.
	await get_tree().create_timer(0.3 if _hosting else 0.6).timeout
	if _hosting:
		NetworkManager.leave("Firestorm test complete")
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		print("[TEST] FAIL ", message)
