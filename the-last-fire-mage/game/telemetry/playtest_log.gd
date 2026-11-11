extends Node
## Host-only playtest recorder (autoload "PlaytestLog"). Owner: head engineer (playtest tooling).
## Writes one JSON object per line to user://playtests/<date>_<time>.jsonl on the HOST's machine only.
## Clients never write or print anything. Nothing is sent over the network.
## Public API: `note(kind, data)` for ad-hoc markers; `log_dir()` for the folder. Off with `--no-playtest-log`.
## Find the files: Godot menu Project > Open User Data Folder, or macOS ~/Library/Application Support/Godot/
## app_userdata/The Last Fire Mage/playtests/. Read them with tools/playtest_report.py.
## NET: server only (gated on Net.is_online + multiplayer.is_server). Listens to GameEvents; contract-free.

const SAMPLE_SECONDS := 5.0 ## TUNE: how often positions/alive state are sampled during a round.

var _file: FileAccess
var _t0 := 0
var _round := 0
var _round_t0 := 0
var _in_round := false
var _sample_left := SAMPLE_SECONDS
var _stats: Dictionary = {} # peer_id -> {kills, deaths, damage_dealt, damage_taken, stuns, revives, chickens}
var _roles: Dictionary = {}
var _names: Dictionary = {}


func _ready() -> void:
	# WHY: headless runs are tests/bots; don't litter the user's real playtest folder unless a dir is given.
	if NetworkManager.args.has("no-playtest-log") \
			or (DisplayServer.get_name() == "headless" and not NetworkManager.args.has("playtest-dir")):
		set_process(false)
		return
	GameEvents.phase_changed.connect(_on_phase)
	GameEvents.role_assigned.connect(func(id: int, role: int) -> void:
		_roles[id] = role
		_emit("role", {"id": id, "name": _name(id), "role": Enums.role_name(role)}))
	GameEvents.round_ended.connect(_on_round_ended)
	GameEvents.player_damaged.connect(_on_damaged)
	GameEvents.player_died.connect(_on_died)
	GameEvents.player_revived.connect(func(id: int) -> void:
		_bump(id, "revives")
		_emit("revive", {"id": id, "name": _name(id)}))
	GameEvents.player_stunned.connect(func(id: int, secs: float) -> void:
		_bump(id, "stunned")
		_emit("stun", {"id": id, "name": _name(id), "seconds": secs}))
	GameEvents.chicken_killed.connect(func(killer: int, pos: Vector3) -> void:
		_bump(killer, "chickens")
		_emit("chicken_killed", {"by": killer, "x": snappedf(pos.x, 0.1), "z": snappedf(pos.z, 0.1)}))
	GameEvents.power_changed.connect(_on_power)
	GameEvents.firestorm_stage.connect(func(stage: int, _c: Vector3, radius: float, req: float, nxt: float) -> void:
		_emit("firestorm", {"stage": stage, "radius": snappedf(radius, 0.1), "required_power": req, "next_in": nxt}))
	GameEvents.score_changed.connect(func(id: int, total: int) -> void:
		_emit("score", {"id": id, "name": _name(id), "total": total}))
	GameEvents.party_ended.connect(func(standings: Array) -> void:
		_emit("party_ended", {"standings": standings})
		_close())
	NetworkManager.player_registered.connect(func(id: int, pname: String) -> void:
		_names[id] = pname
		_emit("join", {"id": id, "name": pname, "players": Players.all().size()}))
	NetworkManager.peer_left.connect(func(id: int) -> void:
		_emit("leave", {"id": id, "name": _name(id), "in_round": _in_round}))
	NetworkManager.session_ended.connect(func(reason: String) -> void:
		_emit("session_ended", {"reason": reason})
		_close())


## Free-form marker, e.g. from a debug key during a playtest: PlaytestLog.note("boring", {}).
func note(kind: String, data: Dictionary = {}) -> void:
	_emit(kind, data)


## Absolute path of the folder logs are written to.
func log_dir() -> String:
	return String(NetworkManager.args.get("playtest-dir", ProjectSettings.globalize_path("user://playtests")))


func _process(delta: float) -> void:
	if not _in_round or _file == null:
		return
	_sample_left -= delta
	if _sample_left > 0.0:
		return
	_sample_left = SAMPLE_SECONDS
	var rows: Array = []
	for p in Players.all():
		rows.append({"id": p.peer_id, "role": Enums.role_name(p.role), "alive": p.is_alive,
			"x": snappedf(p.global_position.x, 0.1), "y": snappedf(p.global_position.y, 0.1),
			"z": snappedf(p.global_position.z, 0.1)})
	_emit("sample", {"players": rows})


func _on_phase(phase: int, duration: float) -> void:
	if phase == Enums.Phase.ROLE_REVEAL:
		_round += 1
		_stats.clear()
		_roles.clear()
		for p in Players.all():
			_names[p.peer_id] = p.display_name
	if phase == Enums.Phase.HEAD_START:
		_round_t0 = Time.get_ticks_msec()
		_in_round = true
		_sample_left = 0.5 # first sample soon after start, then every SAMPLE_SECONDS
	_emit("phase", {"phase": Enums.Phase.keys()[phase], "duration": duration,
		"players": Players.all().size()})


func _on_round_ended(winner: int, reason: String) -> void:
	_in_round = false
	var per: Array = []
	for id in _stats:
		var s: Dictionary = _stats[id]
		s["id"] = id
		s["name"] = _name(id)
		s["role"] = Enums.role_name(int(_roles.get(id, 0)))
		per.append(s)
	_emit("round_end", {"winner": Enums.Winner.keys()[winner], "reason": reason,
		"round_seconds": snappedf((Time.get_ticks_msec() - _round_t0) / 1000.0, 0.1), "players": per})


func _on_damaged(id: int, amount: float, source: int, cause: StringName) -> void:
	_bump(source, "damage_dealt", amount)
	_bump(id, "damage_taken", amount)
	_emit("damage", {"id": id, "by": source, "amount": snappedf(amount, 0.1), "cause": String(cause)})


func _on_died(id: int, killer: int, cause: StringName) -> void:
	_bump(id, "deaths")
	_bump(killer, "kills")
	var p := Players.get_player(id)
	var pos: Vector3 = p.global_position if p != null else Vector3.ZERO
	_emit("death", {"id": id, "name": _name(id), "by": killer, "cause": String(cause),
		"x": snappedf(pos.x, 0.1), "z": snappedf(pos.z, 0.1)})


func _on_power(mage: int, power: float, tier: int, mult: float) -> void:
	_emit("power", {"mage": mage, "power": snappedf(power, 0.1), "tier": tier, "mult": snappedf(mult, 0.01)})


func _bump(id: int, key: String, by: float = 1.0) -> void:
	if id == 0:
		return
	var s: Dictionary = _stats.get(id, {})
	s[key] = snappedf(float(s.get(key, 0.0)) + by, 0.1)
	_stats[id] = s


func _name(id: int) -> String:
	return String(_names.get(id, str(id)))


func _emit(kind: String, data: Dictionary) -> void:
	if not Net.is_online(self) or not multiplayer.is_server():
		return
	if _file == null and not _open():
		return
	var row := {"t": snappedf((Time.get_ticks_msec() - _t0) / 1000.0, 0.01), "round": _round, "ev": kind}
	row.merge(data)
	_file.store_line(JSON.stringify(row))
	_file.flush()


func _open() -> bool:
	DirAccess.make_dir_recursive_absolute(log_dir())
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/%s.jsonl" % [log_dir(), stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("[Playtest] cannot open %s" % path)
		set_process(false)
		return false
	_t0 = Time.get_ticks_msec()
	_round = 0
	print("[Playtest] recording to ", path)
	return true


func _close() -> void:
	_in_round = false
	_file = null # FileAccess closes on release; next session opens a new file.
