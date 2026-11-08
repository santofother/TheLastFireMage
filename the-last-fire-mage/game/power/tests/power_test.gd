## Power reward, decay, round reset and late snapshot regression. Owner: S13. NET: host + client.
extends Node

var power: PowerManager
var failed := false

class FakeMatch extends Node:
	func get_role(id: int) -> int:
		return Enums.Role.VILLAGER if id == 2 else Enums.Role.MAGE

func _ready() -> void:
	var match_system := FakeMatch.new()
	add_child(match_system)
	GameEvents.register_system(&"match", match_system)
	power = preload("res://game/power/power_manager.tscn").instantiate()
	add_child(power)
	power.set_process(false)
	var hosting := NetworkManager.args.has("host")
	if hosting:
		GameEvents.role_assigned.emit(1, Enums.Role.MAGE)
		GameEvents.phase_changed.emit(Enums.Phase.HUNT, 60.0)
		GameEvents.chicken_killed.emit(99, Vector3.ZERO)
		_check(power.current_power() == 0, "ignore other killers")
		GameEvents.chicken_killed.emit(1, Vector3.ZERO)
		_check(power.current_power() == 1, "chicken reward")
		GameEvents.player_died.emit(2, 1, &"knife")
		_check(power.current_power() == 4 and power.current_tier() == 1, "villager reward and tier unlock")
	var peer := ENetMultiplayerPeer.new()
	var port := int(NetworkManager.args["port"])
	var error := peer.create_server(port) if hosting else peer.create_client("127.0.0.1", port)
	if error != OK:
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	if hosting:
		multiplayer.peer_connected.connect(_run)
	get_tree().create_timer(15.0).timeout.connect(func() -> void: get_tree().quit(1))

func _run(id: int) -> void:
	await get_tree().create_timer(0.4).timeout
	power._on_registered(id, "Late joiner")
	await get_tree().create_timer(0.2).timeout
	_verify.rpc_id(id, 4.0, 1)
	power._process(5.0)
	_check(is_equal_approx(power.current_power(), 3.96), "timed decay")
	_check(power.multiplier() > 1.25, "effectiveness above tier base")
	power._process(5000.0)
	_check(power.current_power() == 3 and power.current_tier() == 1, "decay preserves tier floor")
	_check(power.multiplier() == 1.25, "effectiveness tier floor")
	power.add_power(-5, &"test")
	_check(power.current_power() == 3, "reject negative award")
	GameEvents.player_died.emit(1, 1, &"test")
	_check(power.current_power() == 3, "ignore mage suicide")
	GameEvents.phase_changed.emit(Enums.Phase.RESULTS, 10.0)
	GameEvents.player_died.emit(2, 1, &"knife")
	_check(power.current_power() == 6 and power.current_tier() == 2, "last villager reward after match result")
	GameEvents.phase_changed.emit(Enums.Phase.ROLE_REVEAL, 5.0)
	_check(power.current_power() == 0 and power.current_tier() == 0 and power.multiplier() == 1, "new round reset")
	GameEvents.phase_changed.emit(Enums.Phase.HUNT, 60.0)
	GameEvents.chicken_killed.emit(1, Vector3.ZERO)
	_verify.rpc_id(id, 1.0, 0)
	await get_tree().create_timer(0.3).timeout
	_finish.rpc_id(id)
	print("[TEST] POWER PASSED" if not failed else "[TEST] FAIL POWER")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if failed else 0)

@rpc("authority", "reliable")
func _verify(expected: float, tier: int) -> void:
	_check(is_equal_approx(power.current_power(), expected) and power.current_tier() == tier, "client replicated power")
	power.add_power(100, &"test")
	_check(is_equal_approx(power.current_power(), expected), "client cannot award power")

@rpc("authority", "reliable")
func _finish() -> void:
	print("[TEST] POWER CLIENT PASSED" if not failed else "[TEST] FAIL POWER CLIENT")
	get_tree().quit(1 if failed else 0)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error("[TEST] FAIL POWER: " + label)
