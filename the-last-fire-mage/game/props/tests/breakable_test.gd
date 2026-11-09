## Host + client furniture regression: momentum, walking, flame, walls, late join, round reset. Owner: furnishing pass.
## No public API. Host prints `[TEST] BREAKABLE PASSED`; client prints `[TEST] BREAKABLE CLIENT PASSED`.
extends Node3D

const CHAIR := preload("res://game/props/chair.tscn")

var manager: BreakableManager
var charge: BreakableProp
var stroll: BreakableProp
var burn: BreakableProp
var hidden_chair: BreakableProp
var knifed: BreakableProp
var late: BreakableProp
var mage: Player
var runner: Player
var combat: MageAbilities
var driver := RunDriver.new()
var failed := false


class RunDriver:
	var sprint := false
	var running := false

	func fill_input(_player: Node, input: PlayerInput, _delta: float) -> void:
		input.move = Vector2(0, -1) if running else Vector2.ZERO
		input.sprint = sprint and running


func _ready() -> void:
	var peer := ENetMultiplayerPeer.new()
	var hosting := NetworkManager.args.has("host")
	var port := int(NetworkManager.args.get("port", 24567))
	var result := peer.create_server(port) if hosting else peer.create_client("127.0.0.1", port)
	if result != OK:
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	manager = BreakableManager.new()
	manager.name = "Breakables"
	add_child(manager)
	_static_box(Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	_static_box(Vector3(12.8, 1.0, -2.8), Vector3(1.0, 2.0, 0.2))
	charge = _chair("ChargeChair", Vector3(0, 0, -4))
	stroll = _chair("StrollChair", Vector3(6, 0, -4))
	burn = _chair("BurnChair", Vector3(11.7, 0, -2))
	hidden_chair = _chair("HiddenChair", Vector3(12.6, 0, -3.5))
	knifed = _chair("KnifedChair", Vector3(30, 0, -1))
	late = _chair("LateChair", Vector3(20, 0, -1))
	mage = _player(1, Vector3(12, 0, 0), Enums.Role.MAGE)
	runner = _player(1000000, Vector3(0, 0.05, 0), Enums.Role.VILLAGER)
	combat = mage.get_ability(&"MageAbilities") as MageAbilities
	if hosting:
		_host_setup.call_deferred()
		multiplayer.peer_connected.connect(func(id: int) -> void: _host_run(id))
	else:
		_client_run.call_deferred()
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("[TEST] FAIL breakable test timed out")
		get_tree().quit(1))


func _static_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _chair(label: String, pos: Vector3) -> BreakableProp:
	var chair := CHAIR.instantiate() as BreakableProp
	chair.name = label
	chair.position = pos
	add_child(chair)
	return chair


func _player(id: int, pos: Vector3, role: int) -> Player:
	var p := preload("res://game/player/player.tscn").instantiate() as Player
	p.peer_id = id
	p.is_bot = true
	p.name = str(id)
	p.position = pos
	add_child(p)
	p.set_role(role)
	p.set_physics_process(false)
	return p


func _check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		print("[TEST] FAIL ", label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _host_setup() -> void:
	await _frames(4)
	# Broken before the client exists, so only the join snapshot can tell it.
	manager.burn_cone(late.global_position + Vector3(0, 0.65, 1.5), Vector3.FORWARD, 4.0, 60.0)
	_check(late.broken, "fire breaks a chair in the open")


func _run_at(prop: BreakableProp, start: Vector3, sprinting: bool) -> void:
	runner.global_position = start
	runner.velocity = Vector3.ZERO
	runner.input_driver = driver
	driver.sprint = sprinting
	driver.running = true
	runner.set_physics_process(true)
	await _frames(70)
	driver.running = false
	runner.set_physics_process(false)
	runner.velocity = Vector3.ZERO
	print("[TEST] ran at %s sprint=%s broken=%s stopped z=%.2f" % [prop.name, sprinting, prop.broken, runner.global_position.z])


func _host_run(id: int) -> void:
	await _frames(10)
	NetworkManager.player_registered.emit(id, "client")
	await get_tree().create_timer(0.4).timeout
	await _run_at(stroll, Vector3(6, 0.05, 0), false)
	_check(not stroll.broken, "walking into a chair leaves it standing")
	_check(runner.global_position.z > -3.9, "a standing chair blocks the player")
	await _run_at(charge, Vector3(0, 0.05, 0), true)
	_check(charge.broken, "sprinting into a chair breaks it")
	_check(runner.global_position.z < -4.1, "the sprinter carries on through the broken chair")
	_check(charge.get_node_or_null("Pile") != null, "a pile of wood is left behind")
	combat._attack(&"knife", Vector3.FORWARD)
	_check(not knifed.broken, "a plain knife does not splinter furniture")
	combat._attack(&"fire_wave", Vector3.FORWARD)
	await _frames(2)
	_check(burn.broken, "fire wave splinters a chair in the cone")
	_check(not hidden_chair.broken, "a wall protects the chair behind it")
	# The hidden chair stands behind the wall, so a server-side report from far away must be refused.
	manager._rpc_impact(manager._index_of(hidden_chair), 99999.0)
	_check(not hidden_chair.broken, "server refuses an impossible impact")
	await get_tree().create_timer(0.8).timeout
	_check(manager.broken_count() == 3, "three chairs broken: late, charge, burn")
	GameEvents.phase_changed.emit(Enums.Phase.ROLE_REVEAL, 1.0)
	await _frames(3)
	_check(manager.broken_count() == 0 and not charge.broken and charge.collision_layer == 256, "new round restores furniture")
	_check(not ((charge.get_node("Collision") as CollisionShape3D).disabled), "restored furniture collides again")
	_check(_rebuilt_visible(), "restored furniture shows its model")
	await get_tree().create_timer(1.0).timeout
	if not failed:
		print("[TEST] BREAKABLE PASSED")
	get_tree().quit(1 if failed else 0)


func _rebuilt_visible() -> bool:
	return (charge.get_node("Model") as Node3D).visible and charge.get_node_or_null("Pile") == null


func _client_run() -> void:
	# The host needs ~8 s of scripted runs; sample states around the round reset.
	await multiplayer.connected_to_server
	var waited := 0.0
	while not burn.broken and waited < 14.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check(late.broken, "late joiner learns of earlier breaks")
	_check(charge.broken, "client saw the sprint break")
	_check(burn.broken and burn.get_node_or_null("Pile") != null, "client saw the fire break and pile")
	_check(not stroll.broken and not hidden_chair.broken, "client keeps unbroken chairs")
	GameEvents.phase_changed.emit(Enums.Phase.ROLE_REVEAL, 1.0)
	await get_tree().create_timer(0.3).timeout
	_check(not charge.broken and not late.broken, "client restores furniture for a new round")
	if not failed:
		print("[TEST] BREAKABLE CLIENT PASSED")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(1 if failed else 0)
