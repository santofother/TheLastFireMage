extends Node
## Drives the real menu: picks the blue villager, hosts, and checks the spawned body.
## Owner: villager picker. Public API: none; run through tools/tests/villager_picker_test.sh. NET: single host.


func _ready() -> void:
	add_child(load("res://game/main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	var main := GameEvents.system(&"main")
	var menu: Node = main.get_node("Menu")
	# The host-screen dropdown was removed (character is picked in the lobby); set the skin directly.
	VillagerSkins.local = 1
	menu._port_edit.text = str(NetworkManager.args.get("port"))
	menu._on_host_lan()
	await get_tree().create_timer(0.5).timeout
	var player: Player = Players.get_player(1)
	if player == null or player.villager_skin != 1:
		_fail("host should spawn with the blue skin")
		return
	var skeleton := player.get_node("VillagerVisual").find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton.find_child("BV_Body", false, false) == null or skeleton.find_child("RV_Body", false, false) != null:
		_fail("host should show only the blue meshes")
		return
	var spectator: Node = GameEvents.system(&"spectator")
	if spectator._ghost == null:
		spectator._ensure_nodes() # WHY: the manager only builds its nodes when spectating starts.
	spectator._build_ghost_model(player)
	if spectator._ghost.find_child("BV_Body", true, false) == null:
		_fail("spectator ghost should keep the blue body")
		return
	if not option.disabled:
		_fail("picker should lock while connected")
		return
	player.villager_skin = 99
	if player.villager_skin != VillagerSkins.NAMES.size() - 1:
		_fail("out-of-range skin ids must be clamped")
		return
	print("[TEST] VILLAGER PICKER PASSED")
	get_tree().quit()


func _fail(what: String) -> void:
	print("[TEST] FAIL ", what)
	get_tree().quit(1)
