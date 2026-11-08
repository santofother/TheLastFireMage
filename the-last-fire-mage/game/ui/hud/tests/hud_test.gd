## Fake-event HUD demo and assertions. Owner: S08. NET: standalone local scene.
## Run with --hud-demo to keep the preview open, --hud-screenshot=/absolute/file.png to capture.
extends Node

var _hud: Hud
var _failed := false

class FakeMage extends Node:
	func cooldown_left(ability: StringName) -> float:
		return 4.5 if ability == &"fire_wave" else 0.0

class FakePlayer extends Node:
	var peer_id := 1
	var role: int = Enums.Role.MAGE
	var mage: Node
	func get_ability(_ability: StringName) -> Node:
		return mage

class FakeMatch extends Node:
	var time_left := 125.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("243342"))
	_hud = preload("res://game/ui/hud/hud.tscn").instantiate()
	add_child(_hud)
	await get_tree().process_frame
	NetworkManager.player_names = {1: "Ash", 2: "Willow", 3: "Rowan"}
	GameEvents.role_assigned.emit(1, Enums.Role.MAGE)
	GameEvents.role_assigned.emit(2, Enums.Role.VILLAGER)
	GameEvents.role_assigned.emit(3, Enums.Role.VILLAGER)
	GameEvents.phase_changed.emit(Enums.Phase.ROLE_REVEAL, 5.0)
	_check(_label("Reveal").text == "YOU ARE THE MAGE", "role reveal")
	GameEvents.phase_changed.emit(Enums.Phase.HEAD_START, 30.0)
	_check(_hud.get("_blind").visible, "mage blindness")
	GameEvents.role_assigned.emit(1, Enums.Role.VILLAGER)
	_check(not _hud.get("_blind").visible, "villager can see")
	GameEvents.carry_changed.emit(2, &"chicken")
	_check(_label("Carry").text == "HANDS EMPTY", "ignore remote carry")
	GameEvents.carry_changed.emit(1, &"chicken")
	_check(_label("Carry").text.contains("Chicken"), "carry")
	GameEvents.interact_prompt_changed.emit("E · Pick up chicken")
	_check(_label("Prompt").text == "E · Pick up chicken", "prompt")
	GameEvents.role_assigned.emit(1, Enums.Role.MAGE)
	GameEvents.phase_changed.emit(Enums.Phase.HUNT, 312.0)
	_check(not _hud.get("_blind").visible, "hunt clears blindness")
	GameEvents.power_changed.emit(2, 99.0, 3, 2.0)
	_check(_hud.get("_power") == 0, "ignore remote power")
	GameEvents.power_changed.emit(1, 7.0, 2, 1.5)
	GameEvents.firestorm_stage.emit(2, Vector3.ZERO, 80.0, 6.0, 60.0)
	GameEvents.firestorm_warning.emit(3, 15.0)
	GameEvents.player_died.emit(2, 1, &"fire_wave")
	GameEvents.score_changed.emit(1, 12)
	_check(_label("Phase").text.contains("05:12"), "timer")
	_check(_label("Power").text.contains("TIER 3"), "power tier")
	_check(_hud.get("_meter").value == 7, "power meter")
	_check(_hud.get("_threshold").visible, "storm threshold")
	_check(_label("Warning").text == "FIRESTORM 3 IN 15 s", "storm warning")
	_check(_label("Feed").text.contains("Ash → Willow"), "kill feed")
	_check(_label("Cooldowns").text.contains("Fire Wave · READY"), "stub cooldown")
	var fake_player := FakePlayer.new()
	fake_player.mage = FakeMage.new()
	fake_player.add_child(fake_player.mage)
	var health := Health.new()
	health.name = "Health"
	fake_player.add_child(health)
	add_child(fake_player)
	GameEvents.local_player_ready.emit(fake_player)
	_check(_label("Cooldowns").text.contains("Fire Wave · 4.5s"), "live cooldown API")
	_check(_label("Health").text == "HEALTH 100 / 100", "initial health")
	health.apply_damage(35, 2, &"test")
	_hud.call("_refresh")
	_check(_hud.get("_health_meter").value == 65, "damage updates health bar")
	health.kill(2, &"test")
	_hud.call("_refresh")
	_check(_hud.get("_health_meter").value == 0, "death empties health bar")
	health.revive()
	_hud.call("_refresh")
	_check(_hud.get("_health_meter").value == 100, "revive restores health bar")
	VoiceManager.local_speaking = true
	VoiceManager.set("_speakers", {2: {"last": Time.get_ticks_msec() / 1000.0}})
	_hud.call("_refresh")
	_check(_label("Speaking").text.contains("Ash (you)") and _label("Speaking").text.contains("Willow"), "speaking states")
	VoiceManager.local_speaking = false
	VoiceManager.set("_speakers", {})
	var fake_match := FakeMatch.new()
	add_child(fake_match)
	GameEvents.register_system(&"match", fake_match)
	_hud.call("_process", 0.2)
	_check(_label("Phase").text.contains("02:05"), "synced timer overrides estimate")
	fake_match.free()
	Input.action_press("scoreboard")
	await get_tree().process_frame
	_check(_label("Scoreboard").visible, "Tab scoreboard")
	Input.action_release("scoreboard")
	GameEvents.round_ended.emit(Enums.Winner.MAGE, "all_dead")
	GameEvents.phase_changed.emit(Enums.Phase.RESULTS, 10.0)
	_check(_label("Results").visible and _label("Results").text.contains("MAGE WIN"), "winner")
	_check(_label("Results").text.contains("1 kills · 12 pts"), "summary")
	Input.action_press("scoreboard")
	await get_tree().process_frame
	_check(_label("Scoreboard").visible and not _label("Results").visible, "scoreboard over results")
	Input.action_release("scoreboard")
	_hud.call("_process", 9.0)
	_check(_label("Feed").text.is_empty(), "kill feed expires")
	GameEvents.party_ended.emit([{"id": 1, "name": "Ash", "total": 12}])
	_check(_label("Results").text.contains("Ash · 12 points"), "party standings")
	GameEvents.phase_changed.emit(Enums.Phase.LOBBY, 0.0)
	_check(not _hud.get("_root").visible, "lobby hides HUD")
	_check(_hud.get("_feed").is_empty(), "reset kill feed")
	fake_player.free()
	multiplayer.multiplayer_peer = null
	GameEvents.power_changed.emit(0, 0.0, 0, 1.0)
	_check(_hud.call("_local_id") == 0, "session end without a multiplayer peer")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_demo()
	# Check the mic strip and round HUD together, including the smaller playtest window.
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		get_window().size = dimensions
		await get_tree().process_frame
		var mic: ProgressBar = DebugOverlay.get("_mic_bar")
		_check(DebugOverlay.get("_hud").get_child_count() == 1, "legacy keybind hint removed")
		_check(mic.get_global_rect().position.x == 12, "mic remains bottom left")
		for key in ["Cooldowns", "Carry", "Power"]:
			_check(_label(key).get_global_rect().end.y + 8 <= mic.get_global_rect().position.y, key + " clears mic strip")
		_check(_label("Power").get_global_rect().end.x < _hud.get("_root").size.x, "power fits viewport")
		_check(_label("Cooldowns").get_global_rect().end.y <= _hud.get("_root").size.y, "cooldowns fit viewport")
	get_window().size = Vector2i(1280, 720)
	if NetworkManager.args.has("hud-screenshot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(NetworkManager.args["hud-screenshot"]))
	print("[TEST] HUD FAILED" if _failed else "[TEST] HUD PASSED")
	if not NetworkManager.args.has("hud-demo"):
		get_tree().quit(1 if _failed else 0)

func _demo() -> void:
	var player := FakePlayer.new()
	var health := Health.new()
	health.name = "Health"
	health.hp = 65.0
	player.add_child(health)
	add_child(player)
	GameEvents.local_player_ready.emit(player)
	GameEvents.role_assigned.emit(1, Enums.Role.MAGE)
	GameEvents.role_assigned.emit(2, Enums.Role.VILLAGER)
	GameEvents.role_assigned.emit(3, Enums.Role.VILLAGER)
	GameEvents.phase_changed.emit(Enums.Phase.HUNT, 312.0)
	GameEvents.power_changed.emit(1, 7.0, 2, 1.5)
	GameEvents.firestorm_stage.emit(2, Vector3.ZERO, 80.0, 6.0, 60.0)
	GameEvents.firestorm_warning.emit(3, 15.0)
	GameEvents.player_died.emit(2, 1, &"fire_wave")
	GameEvents.interact_prompt_changed.emit("E · Pick up chicken")

func _label(key: String) -> Label:
	return _hud.get_node("RoundHUD/" + key) as Label

func _check(condition: bool, detail: String) -> void:
	if not condition:
		_failed = true
		push_error("[TEST] FAIL HUD: " + detail)
