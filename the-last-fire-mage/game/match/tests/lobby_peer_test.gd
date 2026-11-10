extends Node
## Exercises guest lobby state and appearance replication between two real peers.

func _ready() -> void:
	add_child(load("res://game/main.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	var host := NetworkManager.args.has("host")
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		var match_system = GameEvents.system(&"match")
		if not host:
			var local = Players.local_player()
			if local != null:
				local.character_variant = 1
				if match_system._lobby.visible and match_system.get_node("UI/Lobby/Content/Title").text == "JOINED LOBBY" and not match_system._start.visible:
					print("[TEST] GUEST LOBBY PASSED")
					await get_tree().create_timer(2.0).timeout
					get_tree().quit()
					return
		else:
			for player in Players.all():
				if player.peer_id != 1 and player.character_variant == 1:
					print("[TEST] CHARACTER SYNC PASSED")
					get_tree().quit()
					return
	print("[TEST] FAIL lobby peer test timed out")
	get_tree().quit(1)
