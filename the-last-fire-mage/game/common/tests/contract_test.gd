extends Node
## Headless contract test (S02). Boots main.tscn, hosts ENet, and checks the shared contracts:
## systems registered, InputMap actions, map markers, player contract nodes, set_role abilities,
## tuning + --tune overrides, Health damage/death/revive events, server hooks (stun/lock).
## Run: tools/tests/contract_test.sh → expects "[TEST] CONTRACT PASSED".

const SYSTEMS := [&"main", &"match", &"chickens", &"bots", &"interact", &"spectator", &"power",
	&"firestorm", &"counterplay", &"scoring", &"hud"]
const ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint",
	&"crouch", &"interact", &"drop", &"primary", &"ability_1", &"ability_2", &"push_to_talk",
	&"scoreboard", &"debug", &"menu"]

var _fails := 0
var _events: Array[String] = []


func _ready() -> void:
	for sig in ["player_damaged", "player_died", "player_revived", "player_stunned", "local_player_ready"]:
		GameEvents.connect(sig, func(a = null, b = null, c = null, d = null) -> void: _events.append(sig))
	get_tree().create_timer(30.0).timeout.connect(func() -> void: # safety net: never hang the runner
		print("[TEST] FAIL timeout"); get_tree().quit(1))
	add_child(load("res://game/main.tscn").instantiate())
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("[TEST] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	for s in SYSTEMS:
		_check(GameEvents.system(s) != null, "system registered: %s" % s)
	for a in ACTIONS:
		_check(InputMap.has_action(a) and not InputMap.action_get_events(a).is_empty(), "input action: %s" % a)
	for g in [&"villager_spawn", &"mage_spawn", &"chicken_spawn", &"item_spawn", &"hide_spot"]:
		_check(not get_tree().get_nodes_in_group(g).is_empty(), "map markers: %s" % g)

	var port := int(NetworkManager.args.get("port", 24695))
	_check(NetworkManager.host_enet(port) == OK, "host on port %d" % port)
	for i in 10:
		await get_tree().physics_frame
	var p := Players.get_player(1) as Player
	_check(p != null, "host player spawned")
	if p == null:
		return _finish()
	_check(Players.local_player() == p and p.is_local(), "local player lookup")
	_check(_events.has("local_player_ready"), "local_player_ready fired")
	_check(p.health is Health and p.carry_socket is Marker3D and p.abilities != null and p.camera is Camera3D,
		"player contract nodes")
	_check(p.health.get_multiplayer_authority() == 1, "health is server-authoritative")
	_check(is_equal_approx(p.tuning.walk_speed, 4.0), "villager tuning by default")

	p.set_role(Enums.Role.MAGE)
	await get_tree().process_frame
	_check(p.get_ability(&"MageAbilities") is MageAbilities, "mage gets MageAbilities")
	_check(p.get_ability(&"Interactor") is Interactor, "mage gets Interactor")
	_check(is_equal_approx(p.tuning.walk_speed, 4.5), "mage tuning applied")
	p.set_role(Enums.Role.VILLAGER)
	await get_tree().process_frame
	_check(p.get_ability(&"MageAbilities") == null and p.get_ability(&"Interactor") != null, "villager abilities")

	var m := GameEvents.system(&"match") as MatchManager
	_check(m.tuning != null and is_equal_approx(m.tuning.hunt_time, 12.0), "--tune override (match.hunt_time=12)")

	p.stun(0.5)
	p.set_input_lock(&"test", true)
	await get_tree().physics_frame
	_check(not p.can_control() and _events.has("player_stunned"), "stun + input lock")
	p.set_input_lock(&"test", false)

	p.health.apply_damage(30.0, 0, &"test")
	await get_tree().process_frame
	_check(is_equal_approx(p.health.hp, 70.0) and _events.has("player_damaged"), "damage event + hp")
	p.health.apply_damage(500.0, 0, &"test")
	await get_tree().process_frame
	_check(not p.is_alive and _events.has("player_died") and p.collision_layer == 0, "death event + corpse")
	p.health.revive()
	await get_tree().process_frame
	_check(p.is_alive and _events.has("player_revived") and p.collision_layer == 2, "revive event")
	_finish()


func _finish() -> void:
	print("[TEST] CONTRACT %s (%d failures)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	NetworkManager.leave("test done")
	get_tree().quit(0 if _fails == 0 else 1)
