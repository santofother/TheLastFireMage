## Deterministic host + client combat contract regression. Owner: S09. No public API.
extends Node3D

var mage: Player
var victim: Player
var combat: MageAbilities
var chicken: Chicken
var died_by := 0
var failed := false

func _ready() -> void:
	var peer := ENetMultiplayerPeer.new()
	var hosting := NetworkManager.args.has("host")
	var port := int(NetworkManager.args.get("port", 24567))
	var result := peer.create_server(port) if hosting else peer.create_client("127.0.0.1", port)
	if result != OK:
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	mage = _player(1, Vector3.ZERO, Enums.Role.MAGE)
	victim = _player(1000000, Vector3(0, 0, -1.2), Enums.Role.VILLAGER)
	chicken = preload("res://game/chicken/chicken.tscn").instantiate() as Chicken
	chicken.name = "Chicken"
	chicken.position = Vector3(20, 0, 0)
	add_child(chicken)
	chicken.set_physics_process(false)
	combat = mage.get_ability(&"MageAbilities") as MageAbilities
	GameEvents.player_died.connect(func(id: int, killer: int, _cause: StringName) -> void:
		if id == victim.peer_id: died_by = killer)
	if hosting:
		multiplayer.peer_connected.connect(func(_id: int) -> void: _run())
	get_tree().create_timer(15.0).timeout.connect(func() -> void: get_tree().quit(1))

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
	print("[TEST] %s %s" % ["OK" if ok else "FAIL", label])
	failed = failed or not ok

func _cast(ability: StringName) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	mage.input.clear()
	if ability == &"knife": mage.input.primary_pressed = true
	if ability == &"ignite": mage.input.ability_1_pressed = true
	if ability == &"fire_wave": mage.input.ability_2_pressed = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	mage.input.clear()

func _run() -> void:
	await get_tree().create_timer(0.4).timeout
	combat.tuning.knife_cooldown = 0.15
	combat.tuning.wave_cooldown = 0.15
	combat.tuning.ignite_duration = 0.4
	victim.position.z = -3.0
	await _cast(&"knife")
	_check(victim.health.hp == 100, "out of range")
	await get_tree().create_timer(0.2).timeout
	victim.position.z = -1.2
	await _cast(&"knife")
	_check(victim.health.hp == 80, "in range")
	await _cast(&"knife")
	_check(victim.health.hp == 80, "cooldown rejects duplicate")
	await get_tree().create_timer(0.2).timeout
	victim.position.z = 1.2
	await _cast(&"knife")
	_check(victim.health.hp == 80, "behind mage rejected")
	victim.position.z = -1.2
	await get_tree().create_timer(0.2).timeout
	combat._rpc_request(&"knife", Vector3(NAN, 0, 0))
	combat._rpc_request(&"knife", Vector3.BACK)
	_check(victim.health.hp == 80, "invalid aim rejected")
	mage.set_input_lock(&"test", true)
	await _cast(&"knife")
	_check(victim.health.hp == 80, "locked mage rejected")
	mage.set_input_lock(&"test", false)
	await _cast(&"ignite")
	_check(combat.is_ignited() and combat.cooldown_left(&"ignite") > 0, "ignite active")
	await _cast(&"knife")
	_check(victim.health.hp == 40, "ignited damage")
	await get_tree().create_timer(0.45).timeout
	_check(not combat.is_ignited(), "ignite expires")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.2)
	collision.shape = shape
	wall.add_child(collision)
	wall.position = Vector3(0, 0.5, -0.6)
	add_child(wall)
	await _cast(&"fire_wave")
	_check(victim.health.hp == 40, "wave blocked by wall")
	await _cast(&"knife")
	_check(victim.health.hp == 40, "knife blocked by wall")
	wall.queue_free()
	await get_tree().create_timer(0.2).timeout
	victim.health.invulnerable = true
	await _cast(&"fire_wave")
	_check(victim.health.hp == 40 and victim._knockback == Vector3.ZERO, "invulnerable target unaffected")
	victim.health.invulnerable = false
	await get_tree().create_timer(0.2).timeout
	await _cast(&"fire_wave")
	_check(victim.health.hp == 5 and victim._knockback.length() > 0, "wave damage and knockback")
	await _cast(&"knife")
	_check(died_by == mage.peer_id, "kill attribution")
	victim.health.revive()
	victim.position = Vector3(0, 0, -2.8)
	GameEvents.power_changed.emit(1, 20.0, 1, 2.0)
	await get_tree().create_timer(0.2).timeout
	await _cast(&"knife")
	_check(victim.health.hp == 60, "power scales range and damage")
	victim.position.z = -5
	chicken.position = Vector3(0, 0, -1)
	await get_tree().create_timer(0.2).timeout
	await _cast(&"knife")
	_check(not chicken.health.is_alive, "chicken target")
	_probe.rpc()
	await get_tree().create_timer(0.3).timeout
	_check(victim.health.hp == 60, "non-owner remote request rejected")
	_finish.rpc(failed)
	await get_tree().create_timer(0.2).timeout
	print("[TEST] COMBAT %s" % ["FAILED" if failed else "PASSED"])
	get_tree().quit(1 if failed else 0)

@rpc("authority", "call_remote", "reliable")
func _probe() -> void:
	combat._rpc_request.rpc_id(1, &"fire_wave", Vector3.FORWARD)

@rpc("authority", "call_remote", "reliable")
func _finish(server_failed: bool) -> void:
	_check(died_by == 1, "replicated death attribution")
	_check(combat.cooldown_left(&"ignite") > 0, "replicated cooldown")
	_check(victim.health.hp == 60, "replicated damage")
	print("[TEST] COMBAT CLIENT %s" % ["FAILED" if failed or server_failed else "PASSED"])
	get_tree().quit(1 if failed or server_failed else 0)
