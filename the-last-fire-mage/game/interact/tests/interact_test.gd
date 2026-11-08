## Host + client regression for carry, hide, search and validation. Owner: S10. Run by tools/tests/interact_test.sh.
## Bots drive the real Interactor through `player.input`; the client checks the replicated results.
extends Node3D

const SPOT_POS := Vector3(10, 0, 0)

var a: Player
var b: Player
var mage: Player
var chicken: Chicken
var chicken2: Chicken
var manager: InteractManager
var spot: HideSpot
var failed := false
var carry_events: Array = []


func _ready() -> void:
	var peer := ENetMultiplayerPeer.new()
	var hosting := NetworkManager.args.has("host")
	var port := int(NetworkManager.args.get("port", 24567))
	var result := peer.create_server(port) if hosting else peer.create_client("127.0.0.1", port)
	if result != OK:
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	manager = $Interact as InteractManager
	spot = $Spot as HideSpot
	spot.search_time = 0.3
	a = _player(Players.BOT_ID_BASE, Vector3(-20, 0, 0), Enums.Role.VILLAGER)
	b = _player(Players.BOT_ID_BASE + 1, Vector3(-20, 0, 3), Enums.Role.VILLAGER)
	mage = _player(Players.BOT_ID_BASE + 2, Vector3(-20, 0, 6), Enums.Role.MAGE)
	chicken = _chicken("Chicken", Vector3(0, 0, -1))
	chicken2 = _chicken("Chicken2", Vector3(20, 0, 0))
	GameEvents.carry_changed.connect(func(id: int, kind: StringName) -> void: carry_events.append([id, kind]))
	if hosting:
		multiplayer.peer_connected.connect(func(_id: int) -> void: _run())
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		print("[TEST] FAIL watchdog")
		get_tree().quit(1))


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


func _chicken(n: String, pos: Vector3) -> Chicken:
	var c := preload("res://game/chicken/chicken.tscn").instantiate() as Chicken
	c.name = n
	c.position = pos
	add_child(c)
	return c


func _check(ok: bool, label: String) -> void:
	print("[TEST] %s %s" % ["OK" if ok else "FAIL", label])
	failed = failed or not ok


func _wait(seconds: float = 0.15) -> void:
	await get_tree().create_timer(seconds).timeout


## Places `p` so it faces -z at `pos`, then waits for the transform to settle.
func _place(p: Player, pos: Vector3) -> void:
	p.global_position = pos
	p.rotation = Vector3.ZERO
	await get_tree().physics_frame


## Presses one input for exactly one Interactor tick.
func _press(p: Player, field: StringName) -> void:
	# WHY: physics_frame fires before nodes tick, so set/clear between two signals = exactly one tick.
	await get_tree().physics_frame
	p.input.set(field, true)
	await get_tree().physics_frame
	p.input.clear()
	await _wait()


func _run() -> void:
	await _wait(0.6)
	# Two bots, one chicken, same tick.
	await _place(a, Vector3(0, 0, 0))
	await _place(b, Vector3(0.5, 0, 0))
	_check((a.get_ability(&"Interactor") as Interactor).find_target() != null, "bot finds chicken")
	await get_tree().physics_frame
	a.input.interact_pressed = true
	b.input.interact_pressed = true
	await get_tree().physics_frame
	a.input.clear()
	b.input.clear()
	await _wait()
	var winner := a if manager.carrier_of(chicken) == a.peer_id else b
	var loser := b if winner == a else a
	_check(manager.carrier_of(chicken) in [a.peer_id, b.peer_id], "one bot got the chicken")
	_check(manager.carried_by(loser.peer_id) == null, "the other bot got nothing")
	_check(chicken.carrier_id == winner.peer_id, "chicken knows its carrier")
	_check(is_equal_approx(winner.speed_multiplier(), chicken.tuning.carry_speed_mult), "carrier slowed")
	_check(is_equal_approx(loser.speed_multiplier(), 1.0), "other bot not slowed")
	_check(carry_events.count([winner.peer_id, &"chicken"]) == 1, "carry_changed fired once")
	# Moves with the carrier.
	await _place(winner, Vector3(-3, 0, 4))
	await _wait()
	_check(chicken.global_position.distance_to(winner.carry_socket.global_position) < 0.05, "chicken at carry socket")
	# Validation: distance and role.
	await _place(loser, Vector3(15, 0, 0))
	chicken2.global_position = Vector3(22, 0, 0)
	var loser_i := loser.get_ability(&"Interactor") as Interactor
	loser_i._rpc_interact(chicken2.get_node(^"Interactable").get_path())
	_check(chicken2.carrier_id == 0, "server rejects out-of-range pickup")
	await _place(mage, Vector3(21.5, 0, 0))
	var mage_i := mage.get_ability(&"Interactor") as Interactor
	mage_i._rpc_interact(chicken2.get_node(^"Interactable").get_path())
	_check(chicken2.carrier_id == 0, "mage cannot pick up chickens")
	await _place(mage, Vector3(-20, 0, 6))
	# Hide: carrier stands in front of the crate.
	await _place(winner, SPOT_POS + Vector3(0, 0, 1.5))
	await _press(winner, &"interact_pressed")
	_check(chicken.is_hidden and chicken.state == Chicken.State.HIDDEN, "chicken hidden")
	_check(spot.hidden_objects() == [chicken], "spot holds chicken")
	_check(manager.carried_by(winner.peer_id) == null, "carry ended by hiding")
	_check(is_equal_approx(winner.speed_multiplier(), 1.0), "slow removed by hiding")
	_client_expect.rpc(&"hidden")
	await _wait(0.3)
	# Hidden chickens can't be grabbed directly.
	loser_i._rpc_interact(chicken.get_node(^"Interactable").get_path())
	_check(chicken.is_hidden, "hidden chicken not pickable directly")
	# Take it back out, and put it back.
	await _press(winner, &"interact_pressed")
	_check(not chicken.is_hidden and chicken.carrier_id == winner.peer_id, "villager takes chicken out")
	_check(spot.hidden_count == 0, "spot empty after take")
	await _press(winner, &"interact_pressed")
	_check(chicken.is_hidden, "hidden again")
	# Capacity.
	spot.capacity = 1
	await _place(loser, Vector3(21.5, 0, 0))
	loser_i._rpc_interact(chicken2.get_node(^"Interactable").get_path())
	await _wait()
	_check(manager.carrier_of(chicken2) == loser.peer_id, "second chicken picked up")
	await _place(loser, SPOT_POS + Vector3(1.5, 0, 0))
	loser_i._rpc_interact(spot.get_node(^"Interactable").get_path())
	_check(manager.carrier_of(chicken2) == loser.peer_id, "full spot rejects chicken")
	await _place(loser, Vector3(-10, 0, 0))
	spot.capacity = 2
	# Search: leaving cancels it; staying finds the chicken.
	await _place(winner, Vector3(-20, 0, 0))
	await _place(mage, SPOT_POS + Vector3(0, 0, 1.5))
	await _press(mage, &"interact_pressed")
	_check(spot.searcher_id == mage.peer_id and chicken.is_hidden, "search takes time")
	await _place(mage, Vector3(-20, 0, 6))
	await _wait(0.4)
	_check(spot.searcher_id == 0 and chicken.is_hidden, "walking away cancels search")
	await _place(mage, SPOT_POS + Vector3(0, 0, 1.5))
	await _press(mage, &"interact_pressed")
	await _wait(0.4)
	_check(not chicken.is_hidden and chicken.carrier_id == 0, "search finds chicken")
	_check(spot.hidden_count == 0 and spot.searcher_id == 0, "spot empty after search")
	await _place(mage, Vector3(-20, 0, 6))
	_client_expect.rpc(&"found")
	await _wait(0.3)
	# Throw, drop, death. `loser` still carries chicken2.
	var before: Vector3 = loser.global_position
	await _press(loser, &"primary_pressed")
	_check(chicken2.carrier_id == 0 and manager.carried_by(loser.peer_id) == null, "throw releases")
	await _wait(0.15)
	_check(chicken2.global_position.distance_to(before) > 1.0, "thrown chicken flew")
	_check(is_equal_approx(loser.speed_multiplier(), 1.0), "slow removed by throw")
	await _wait(0.8)
	await _place(loser, chicken2.global_position + Vector3(0, 0, 1))
	await _press(loser, &"interact_pressed")
	_check(manager.carrier_of(chicken2) == loser.peer_id, "pick up again")
	await _press(loser, &"drop_pressed")
	_check(chicken2.carrier_id == 0, "drop releases")
	await _wait(0.6)
	await _place(loser, chicken2.global_position + Vector3(0, 0, 1))
	await _press(loser, &"interact_pressed")
	_check(manager.carrier_of(chicken2) == loser.peer_id, "pick up before death")
	_probe.rpc(loser.get_path(), chicken.get_node(^"Interactable").get_path())
	await _wait(0.3)
	_check(manager.carried_by(loser.peer_id) == chicken2 and chicken.carrier_id == 0, "non-owner request rejected")
	loser.health.kill(mage.peer_id, &"test")
	await _wait(0.2)
	_check(chicken2.carrier_id == 0 and manager.carried_by(loser.peer_id) == null, "death drops chicken")
	# Carried thing removed from the game (round reset / killed).
	await _place(winner, chicken.global_position + Vector3(0, 0, 1))
	await _press(winner, &"interact_pressed")
	_check(manager.carrier_of(chicken) == winner.peer_id, "pick up before kill")
	chicken.health.kill(mage.peer_id, &"test")
	await _wait(0.2)
	_check(manager.carried_by(winner.peer_id) == null and is_equal_approx(winner.speed_multiplier(), 1.0),
		"killed chicken ends carry")
	_finish.rpc(failed)
	await _wait(0.3)
	print("[TEST] INTERACT %s" % ["FAILED" if failed else "PASSED"])
	get_tree().quit(1 if failed else 0)


# Client spoofs a bot it doesn't own.
@rpc("authority", "call_remote", "reliable")
func _probe(player_path: NodePath, target: NodePath) -> void:
	var interactor := (get_node(player_path) as Player).get_ability(&"Interactor") as Interactor
	interactor._rpc_interact.rpc_id(1, target)


@rpc("authority", "call_remote", "reliable")
func _client_expect(stage: StringName) -> void:
	await _wait(0.2)
	if stage == &"hidden":
		_check(chicken.is_hidden and chicken.carrier_id == 0 and not chicken.visible, "client: chicken hidden")
		_check(spot.hidden_count == 1, "client: spot count")
		_check(carry_events.any(func(e: Array) -> bool: return e[1] == &"chicken"), "client: carry_changed fired")
	else:
		_check(not chicken.is_hidden and chicken.visible and spot.hidden_count == 0, "client: chicken found")


@rpc("authority", "call_remote", "reliable")
func _finish(server_failed: bool) -> void:
	print("[TEST] INTERACT CLIENT %s" % ["FAILED" if failed or server_failed else "PASSED"])
	get_tree().quit(1 if failed or server_failed else 0)
