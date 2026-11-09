## Server-validated knife, Ignite and Fire Wave; owner input and replicated feedback.
## Owner: S09. API: power_multiplier, tuning, cooldown_left(), is_ignited().
class_name MageAbilities
extends Node3D

## Fire effectiveness from GameEvents.power_changed; base is 1.0.
var power_multiplier := 1.0
## Private tuning copy; mage_combat CLI overrides are supported.
var tuning: MageCombatTuning
var _player: Player
var _cooldowns := {&"knife": 0.0, &"ignite": 0.0, &"fire_wave": 0.0, &"locate": 0.0}
var _ignite_left := 0.0
var _power_tier := 0
var _flame: MeshInstance3D
## Positions from the latest Locate this owner received (tests and debug read it).
var last_locator_points := PackedVector3Array()

func _ready() -> void:
	_player = get_parent().get_parent() as Player
	tuning = Tuning.load_tuning("res://game/mage/tuning_mage_combat.tres", "mage_combat") as MageCombatTuning
	GameEvents.power_changed.connect(_on_power_changed)
	_flame = $Flame
	_request_snapshot.call_deferred()

func _physics_process(delta: float) -> void:
	for key in _cooldowns:
		_cooldowns[key] = maxf(0.0, float(_cooldowns[key]) - delta)
	_ignite_left = maxf(0.0, _ignite_left - delta)
	_flame.visible = is_ignited()
	$Knife.visible = false
	if _flame.visible: # FIX(mage model): burn on the held blade instead of in front of the capsule.
		_flame.global_position = (_player.get_node("MageVisual") as MageVisual).hand_position() + Vector3.UP * 0.1
	if not _player.is_multiplayer_authority() or not _player.can_control():
		return
	var aim := -_player.camera_rig.global_basis.z
	if _player.input.ability_1_pressed:
		_request(&"ignite", aim)
	if _player.input.primary_pressed:
		_request(&"knife", aim)
	if _player.input.ability_2_pressed:
		_request(&"fire_wave", aim)
	if _player.input.ability_3_pressed:
		_request(&"locate", aim)

func _request(ability: StringName, aim: Vector3) -> void:
	if cooldown_left(ability) > 0.0:
		return
	if Net.is_server(self):
		_rpc_request(ability, aim)
	else:
		_rpc_request.rpc_id(1, ability, aim)

# NET: requests carry intent only. Position, targets, damage and cooldowns come from the server.
@rpc("any_peer", "call_local", "reliable")
func _rpc_request(ability: StringName, aim: Vector3) -> void:
	if not Net.is_server(self) or Net.sender_id(self) != _player.get_multiplayer_authority():
		return
	if not _player.can_control() or _player.role != Enums.Role.MAGE:
		return
	if not _cooldowns.has(ability) or cooldown_left(ability) > 0.0:
		return
	if not aim.is_finite() or aim.length_squared() < 0.9 or aim.length_squared() > 1.1:
		return
	aim = aim.normalized()
	# WHY: pitch is not replicated by Player; allow pitch but reject backwards forged aim.
	if aim.dot(-_player.global_basis.z) < cos(deg_to_rad(80.0)):
		return
	var cooldown := tuning.knife_cooldown
	if ability == &"ignite":
		cooldown = tuning.ignite_cooldown
	elif ability == &"fire_wave":
		# FIX(S14, Codex): Use the server's unlocked tier at the time of the cast.
		cooldown = tuning.wave_cooldown * pow(tuning.wave_cooldown_per_tier, _power_tier)
	elif ability == &"locate":
		cooldown = tuning.locator_cooldown
	Net.broadcast(self, &"_rpc_cast", [ability, cooldown, tuning.ignite_duration])
	if ability == &"locate":
		_send_locator()
	elif ability != &"ignite":
		_attack(ability, aim)

@rpc("any_peer", "call_local", "reliable")
func _rpc_cast(ability: StringName, cooldown: float, duration: float) -> void:
	if not Net.from_server(self):
		return
	_cooldowns[ability] = cooldown
	if ability == &"ignite":
		_ignite_left = duration
	# FIX(mage model): the model plays confirmed casts on every peer; the placeholder knife box is hidden.
	_player.get_node("MageVisual").play_cast(ability)

func _attack(ability: StringName, aim: Vector3) -> void:
	var wave := ability == &"fire_wave"
	var power := clampf(power_multiplier, 0.1, 10.0)
	var reach := (tuning.wave_range if wave else tuning.knife_range) * power
	var angle := minf(170.0, (tuning.wave_angle_deg if wave else tuning.knife_angle_deg) * power)
	var damage := (tuning.wave_damage if wave else (tuning.ignite_damage if is_ignited() else tuning.knife_damage)) * power
	var origin := _player.global_position + Vector3.UP * 0.65
	var sphere := SphereShape3D.new()
	sphere.radius = reach + 1.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = 2 | 4 | 32
	query.exclude = [_player.get_rid()]
	var seen: Array[Health] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 128):
		var health := Health.find_on(hit.collider)
		if not health or health in seen or not health.is_alive or health.invulnerable:
			continue
		seen.append(health)
		var target := health.get_parent() as Node3D
		if not target or target == _player:
			continue
		# CONTRACT: mages on the same side never damage each other.
		if target is Player and target.role == Enums.Role.MAGE:
			continue
		var point := target.global_position + Vector3.UP * (0.4 if target is Player else 0.25)
		var offset := point - origin
		if offset.length() > reach or (offset.length() > 0.01 and aim.dot(offset.normalized()) < cos(deg_to_rad(angle * 0.5))):
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, point, 1 | 16, [_player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		# FIX(S14, Codex): Boost player hits and keep chicken damage on the shared path.
		var hit_damage := tuning.wave_player_damage * power if wave and target is Player else damage
		health.apply_damage(hit_damage, _player.peer_id, ability)
		if wave and target is Player:
			target.apply_knockback((aim + Vector3.UP * 0.25).normalized() * tuning.wave_knockback * power)
		Net.broadcast(self, &"_rpc_hit", [target.get_path(), point])
	# Fire Wave and ignited swings splinter wooden furniture; a plain knife does not.
	var breakables := GameEvents.system(&"breakables") as BreakableManager
	if breakables and (wave or is_ignited()):
		breakables.burn_cone(origin, aim, reach, angle)
	if wave:
		Net.broadcast(self, &"_rpc_wave", [origin, aim, reach, angle])

@rpc("any_peer", "call_local", "unreliable", 1)
func _rpc_hit(target_path: NodePath, point: Vector3) -> void:
	if not Net.from_server(self) or DisplayServer.get_name() == "headless":
		return
	var target := get_node_or_null(target_path) as Player
	var effect := preload("res://game/mage/mage_feedback.gd").new()
	get_tree().current_scene.add_child(effect)
	effect.hit(point, target)

@rpc("any_peer", "call_local", "unreliable", 1)
func _rpc_wave(origin: Vector3, aim: Vector3, reach: float, angle: float) -> void:
	if not Net.from_server(self) or DisplayServer.get_name() == "headless":
		return
	var effect := preload("res://game/mage/mage_feedback.gd").new()
	get_tree().current_scene.add_child(effect)
	effect.wave(origin, aim, reach, angle)

func _on_power_changed(mage_id: int, _power: float, tier: int, multiplier: float) -> void:
	if _player.peer_id == mage_id and is_finite(multiplier):
		power_multiplier = multiplier
		_power_tier = tier

# NET: server only. Only the mage who pressed Locate is told where the villagers are.
func _send_locator() -> void:
	var points := _nearby_villager_positions()
	print("[Mage] Locate by %d found %d villagers" % [_player.peer_id, points.size()])
	if _player.is_local():
		_rpc_locator(points)
	elif not _player.is_bot and Net.is_online(self):
		_rpc_locator.rpc_id(_player.get_multiplayer_authority(), points)


func _nearby_villager_positions() -> PackedVector3Array:
	var points := PackedVector3Array()
	var range_squared := tuning.locator_range * tuning.locator_range
	for villager in Players.alive_with_role(Enums.Role.VILLAGER):
		var position_in_world: Vector3 = villager.global_position
		if not villager.health.is_downed and _player.global_position.distance_squared_to(position_in_world) <= range_squared:
			points.append(position_in_world + Vector3.UP * 1.3)
	return points


@rpc("any_peer", "call_remote", "unreliable", 1)
func _rpc_locator(points: PackedVector3Array) -> void:
	if not Net.from_server(self) or not _player.is_local():
		return
	last_locator_points = points
	if DisplayServer.get_name() == "headless":
		return
	var effect := preload("res://game/mage/mage_feedback.gd").new()
	effect.top_level = true
	add_child(effect)
	effect.locator(points, _player.global_position, tuning.locator_range, tuning.locator_show_time)


## FIX(S15, Claude): NET: server only. Puts out Ignite (water bucket hit). Fires on every peer.
func extinguish() -> void:
	if Net.is_server(self):
		Net.broadcast(self, &"_rpc_extinguish")

@rpc("any_peer", "call_local", "reliable")
func _rpc_extinguish() -> void:
	if Net.from_server(self):
		_ignite_left = 0.0

## True while the knife burns, on every peer.
func is_ignited() -> bool:
	return _ignite_left > 0.0

## Seconds until an ability is ready; HUD countdown mirrors server-approved casts.
func cooldown_left(ability: StringName) -> float:
	return float(_cooldowns.get(ability, 0.0))

func _request_snapshot() -> void:
	if Net.is_online(self) and not Net.is_server(self):
		_rpc_snapshot_request.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_snapshot_request() -> void:
	if Net.is_server(self):
		_rpc_snapshot.rpc_id(Net.sender_id(self), _cooldowns, _ignite_left, power_multiplier)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_snapshot(cooldowns: Dictionary, ignite_left: float, power: float) -> void:
	if Net.from_server(self):
		_cooldowns = cooldowns
		_ignite_left = ignite_left
		power_multiplier = power
