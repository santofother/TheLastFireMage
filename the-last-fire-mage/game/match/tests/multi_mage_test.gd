extends Node
## Verifies the host's mage count assigns multiple roles and preserves a villager.

func _ready() -> void:
	add_child(load("res://game/main.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	NetworkManager.args["bots"] = 3
	NetworkManager.args["mages"] = 2
	NetworkManager.host_enet(int(NetworkManager.args.get("port")))
	await get_tree().create_timer(0.5).timeout
	var match_system = GameEvents.system(&"match")
	var bot_manager = GameEvents.system(&"bots")
	bot_manager.set_lobby_count(2)
	await get_tree().process_frame
	await get_tree().process_frame
	if Players.all().size() != 3:
		print("[TEST] FAIL removing a lobby bot")
		get_tree().quit(1)
		return
	bot_manager.set_lobby_count(3)
	await get_tree().process_frame
	if Players.all().size() != 4:
		print("[TEST] FAIL adding a lobby bot")
		get_tree().quit(1)
		return
	match_system.start_round()
	var mages := 0
	var villagers := 0
	for player in Players.all():
		if match_system.get_role(player.peer_id) == Enums.Role.MAGE:
			mages += 1
		elif match_system.get_role(player.peer_id) == Enums.Role.VILLAGER:
			villagers += 1
	if mages != 2 or villagers != 2:
		print("[TEST] FAIL multi-mage roles: ", mages, " / ", villagers)
		get_tree().quit(1)
		return
	print("[TEST] MULTI MAGE PASSED")
	get_tree().quit()
