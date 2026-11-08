extends Node3D
## Headless chicken test (host + one client). Owner: S06. Run by `tools/tests/chicken_test.sh`.
## Host: bakes a flat navmesh, spawns 10 chickens, scares one with a fake threat, carries/drops one,
## checks all moved and none fell through, kills one. Client: checks synced movement, carry placement,
## the `chicken_killed` event and that the dead chicken is gone.

const COUNT := 10

var _mgr: ChickenManager
var _fail := 0
var _t := 0.0
var _start: Dictionary = {} # name -> Vector3
var _steps: Dictionary = {}
var _kills := 0
var _carry_seen := -1.0
var _scared := false
var _threat: Node3D

@onready var carrier: Node3D = $FakeCarrier


func _ready() -> void:
	_mgr = $Chickens as ChickenManager
	($Nav as NavigationRegion3D).bake_navigation_mesh(false)
	print("[TEST] navmesh polygons: %d" % ($Nav as NavigationRegion3D).navigation_mesh.get_polygon_count())
	var port := int(NetworkManager.args.get("port", NetworkManager.DEFAULT_PORT))
	if NetworkManager.args.has("host"):
		NetworkManager.host_enet(port)
	else:
		NetworkManager.join_enet("127.0.0.1", port)
	GameEvents.chicken_killed.connect(func(k: int, _p: Vector3) -> void:
		_kills += 1
		print("[TEST] chicken_killed by %d" % k))
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		_check(false, "watchdog"); _finish())


func _physics_process(delta: float) -> void:
	_t += delta
	if NetworkManager.args.has("host"):
		_host_tick()
	else:
		_client_tick()


func _host_tick() -> void:
	if _once(&"spawn", 1.5):
		_mgr.spawn_chickens(COUNT)
		_check(_mgr.alive_count() == COUNT, "spawned %d" % COUNT)
		for c in _mgr.get_chickens():
			_start[c.name] = c.global_position
		print("[TEST] has_nav=%s" % (_mgr.get_chickens()[0] as Chicken)._has_nav())
	if _start.is_empty():
		return
	if _once(&"threat", 3.0):
		var c := _chicken("Chicken1")
		_threat = Node3D.new()
		_threat.set_script(load("res://game/chicken/tests/fake_player.gd"))
		_threat.add_child(Marker3D.new())
		_threat.get_child(0).name = "CarrySocket"
		_threat.add_to_group(&"players")
		add_child(_threat)
		_threat.global_position = c.global_position + Vector3(1.0, 0, 0)
	if _threat and not _scared and _chicken("Chicken1").state == Chicken.State.FLEE:
		_scared = true
	if _once(&"threat_off", 4.5):
		_check(_scared, "chicken flees from a nearby player")
		_threat.queue_free()
	if _once(&"pickup", 5.0):
		var c := _chicken("Chicken2")
		_check(c.can_be_carried(), "can_be_carried while free")
		c.on_picked_up(carrier)
		_check(not c.can_be_carried(), "not carryable while carried")
		_check(is_equal_approx(c.carry_speed_multiplier(), _mgr.tuning.carry_speed_mult), "carry speed mult")
	if _once(&"drop", 7.0):
		var c := _chicken("Chicken2")
		_check(c.global_position.distance_to(carrier.carry_socket.global_position) < 0.05, "host: at socket")
		c.on_dropped(carrier.global_position + Vector3(-1, 0.5, 0), Vector3(-2, 2, 0))
	if _once(&"check", 11.0):
		for c in _mgr.get_chickens():
			var moved: float = (c.global_position - _start[c.name]).length()
			_check(moved > 0.5, "host: %s moved %.2f" % [c.name, moved])
			_check(c.global_position.y > -0.5, "host: %s above floor (y=%.2f)" % [c.name, c.global_position.y])
		print("[TEST] KILL Chicken3")
		(_chicken("Chicken3") as Chicken).health.kill(1, &"test")
	if _once(&"after", 13.0):
		_check(_kills == 1, "host: chicken_killed fired once")
		_check(_chicken("Chicken3") == null, "host: dead chicken freed")
		_check(_mgr.alive_count() == COUNT - 1, "host: alive_count %d" % _mgr.alive_count())
		_finish()


func _client_tick() -> void:
	if _start.is_empty():
		if _mgr.get_chickens().size() == COUNT:
			for c in _mgr.get_chickens():
				_start[c.name] = c.global_position
			print("[TEST] client sees %d chickens" % COUNT)
		return
	var c2 := _chicken("Chicken2")
	if c2 and c2.carrier_id == 999 and _carry_seen < 0.0:
		_carry_seen = _t
	if _carry_seen > 0.0 and _once(&"carry", _carry_seen + 0.5):
		_check(c2.global_position.distance_to(carrier.carry_socket.global_position) < 0.05, "client: carried at socket")
	if _kills > 0 and _once(&"after", _t + 0.0):
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			_check(_carry_seen > 0.0, "client: saw carry")
			_check(_chicken("Chicken3") == null, "client: dead chicken gone")
			_check(_mgr.get_chickens().size() == COUNT - 1, "client: %d chickens left" % _mgr.get_chickens().size())
			for c in _mgr.get_chickens():
				var moved: float = (c.global_position - _start[c.name]).length()
				_check(moved > 0.3, "client: %s moved %.2f" % [c.name, moved])
				_check(c.global_position.y > -0.5, "client: %s above floor" % c.name)
			_finish())


func _chicken(n: String) -> Chicken:
	return _mgr.get_node_or_null("Chickens/" + n) as Chicken


## True exactly once, the first tick after `at` seconds.
func _once(key: StringName, at: float) -> bool:
	if _steps.has(key) or _t < at:
		return false
	_steps[key] = true
	return true


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
	print("[TEST] %s %s" % ["ok" if ok else "FAIL", msg])


func _finish() -> void:
	print("[TEST] CHICKEN %s" % ("PASSED" if _fail == 0 else "FAILED (%d)" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)
