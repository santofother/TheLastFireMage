## Offline (server-only) regression for items, stun diminishing returns, ground breaking, cart and laundry
## line. Owner: S15. Run by tools/tests/counterplay_test.sh. No public API.
extends Node3D

var manager: CounterplayManager
var mage: Player
var a: Player
var b: Player
var failed := false


func _ready() -> void:
	manager = $Counterplay as CounterplayManager
	mage = _player(1, Vector3.ZERO, Enums.Role.MAGE)
	a = _player(Players.BOT_ID_BASE, Vector3(0, 0, 8), Enums.Role.VILLAGER)
	b = _player(Players.BOT_ID_BASE + 1, Vector3(5, 0, 8), Enums.Role.VILLAGER)
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		print("[TEST] FAIL watchdog")
		get_tree().quit(1))
	_run.call_deferred()


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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Spawns an item at the thrower and throws it at the mage.
func _throw(kind: StringName, thrower: Player, break_chance := 0.0) -> CounterItem:
	var item := manager.spawn_item(kind, thrower.global_position + Vector3(0, 1.2, 0), break_chance) as CounterItem
	await get_tree().physics_frame
	item.on_picked_up(thrower)
	var dir := (mage.global_position - thrower.global_position).normalized()
	item.on_dropped(thrower.global_position + Vector3(0, 1.2, 0) + dir * 0.5, dir * 12.0 + Vector3.UP * 2.0)
	return item


func _run() -> void:
	await _wait(0.3)
	var item := manager.spawn_item(&"pot", Vector3(20, 0.1, 20)) as CounterItem
	_check(item != null and item.kind == &"pot", "item spawns")
	_check(item.can_be_carried(), "free item can be carried")
	# Pot hits the mage: stunned, item breaks.
	var stuns: Array = []
	mage.stunned.connect(func(s: float) -> void: stuns.append(s))
	var pot := await _throw(&"pot", a)
	await _wait(1.0)
	_check(not is_instance_valid(pot) or pot.is_queued_for_deletion(), "pot broke on the mage")
	_check(stuns.size() == 1 and is_equal_approx(stuns[0], manager.tuning.pot_stun), "first hit stuns full length")
	# Second hit from another villager inside the window: shorter.
	var bucket := await _throw(&"bucket", b)
	var abilities := mage.get_ability(&"MageAbilities") as MageAbilities
	abilities._rpc_cast(&"ignite", 0.0, 5.0)
	_check(abilities.is_ignited(), "mage ignited")
	await _wait(1.0)
	_check(stuns.size() == 2 and is_equal_approx(stuns[1], manager.tuning.stun_duration * manager.tuning.dr_factor),
		"second hit stuns shorter")
	_check(not abilities.is_ignited(), "bucket puts out Ignite")
	_check(not is_instance_valid(bucket) or bucket.is_queued_for_deletion(), "bucket broke on the mage")
	# Same source again: cooldown.
	_check(manager.request_stun(mage, 1.0, a.peer_id) == 0.0, "same source is on cooldown")
	_check(manager.request_stun(mage, 1.0, 0) > 0.0 and stuns.size() == 3, "environment source has no cooldown")
	# Net slows, then it wears off.
	manager.tuning.net_slow_time = 0.4
	var net := await _throw(&"net", a)
	await _wait(0.8)
	_check(is_equal_approx(mage.speed_multiplier(), manager.tuning.net_slow), "net slows the mage")
	await _wait(0.6)
	_check(is_equal_approx(mage.speed_multiplier(), 1.0), "net slow wears off")
	_check(not is_instance_valid(net) or net.is_queued_for_deletion(), "net broke on the mage")
	# Miss: item thrown away from the mage lands; break chance 0 = stays, 1 = breaks.
	var floor_item := manager.spawn_item(&"pot", Vector3(15, 1.0, 15), 0.0) as CounterItem
	floor_item.on_dropped(floor_item.global_position, Vector3.ZERO)
	var fragile := manager.spawn_item(&"pot", Vector3(18, 1.0, 15), 1.0) as CounterItem
	fragile.on_dropped(fragile.global_position, Vector3.ZERO)
	await _wait(1.0)
	_check(is_instance_valid(floor_item) and floor_item.state == CounterItem.State.IDLE and floor_item.can_be_carried(),
		"normal item survives landing and can be picked up again")
	_check(not is_instance_valid(fragile) or fragile.is_queued_for_deletion(), "dead-area item breaks on the ground")
	# Environment pieces.
	var cart := $Cart as TippableCart
	await _wait(0.1)
	mage.global_position = Vector3(10, 0, 1.5)
	a.global_position = Vector3(10, 0, -1.5)
	manager.tuning.stun_cooldown = 0.0
	manager.tuning.dr_window = 0.0
	var before := stuns.size()
	(cart.get_node(^"Interactable") as Interactable).interact(a)
	_check(cart.tipped and stuns.size() == before + 1 and is_equal_approx(stuns[-1], manager.tuning.cart_stun),
		"tipped cart stuns the mage in its path")
	var line := $Laundry as LaundryLine
	(line.get_node(^"Interactable") as Interactable).interact(a)
	_check(line.sheet_up and line.get_node(^"Sheet").visible, "laundry sheet blocks sight")
	# A dead player's item: caught by a living villager it survives; ghosts grab and throw through the server.
	a.global_position = Vector3(25, 0, 25)
	var caught := manager.spawn_item(&"pot", Vector3(25, 3, 25), 1.0) as CounterItem
	caught.on_dropped(caught.global_position, Vector3.DOWN)
	await _wait(1.0)
	_check(is_instance_valid(caught) and not caught.is_queued_for_deletion() and caught.break_chance == 0.0,
		"item hitting a living villager does not break")
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(20000 + randi() % 20000)
	multiplayer.multiplayer_peer = peer
	var glass := manager.spawn_item(&"net", Vector3(40, 30.1, 40), 0.9) as CounterItem
	await get_tree().physics_frame
	_check(manager.ghost_nearest_item(Vector3(41, 30, 40)) == glass, "ghost finds an item on the glass")
	manager.ghost_pickup(glass, Vector3(41, 30, 40))
	_check(glass.state == CounterItem.State.IDLE, "living players cannot use ghost pickup")
	mage.health.kill(0, &"test")
	manager.ghost_pickup(glass, Vector3(41, 30, 40))
	_check(manager.ghost_held_kind == &"net", "dead player grabs the item")
	manager.ghost_throw(Vector3(41, 30, 40), Vector3(0, -1, 0))
	_check(glass.state == CounterItem.State.AIR and manager.ghost_held_kind == &"", "dead player throws it down")
	print("[TEST] COUNTERPLAY %s" % ["FAILED" if failed else "PASSED"])
	get_tree().quit(1 if failed else 0)
