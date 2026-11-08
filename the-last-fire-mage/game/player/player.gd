class_name Player
extends CharacterBody3D
## Player character (villager and mage share it; role changes tuning + abilities). Owner: S03.
## Momentum, buffered/coyote jumps, crouch, one-shot ledge mantles, fall tumbles and contact bumps.
## Public contract: docs/ARCHITECTURE.md §Player; replicated movement flags listed below.
##
## NET: spawned by Main's MultiplayerSpawner on the server (data {id, name, pos, bot}). Node name = peer id.
## Multiplayer authority = owning peer (client-authoritative movement); local bots (S07) use authority 1.
## `Health` child is always server-authoritative. Position/rotation replicate via `Sync` (20 Hz).
## Server-side effects on movement (stun, lock, teleport, knockback, speed) are public funcs the SERVER
## calls; they RPC to every peer and the owning peer applies them.
##
## Public API:
## - vars: `peer_id`, `display_name`, `is_bot`, `role` (Enums.Role), `is_alive`, `velocity` (built-in),
##   `input` (PlayerInput), `input_driver`, `tuning` (PlayerTuning), `health`, `carry_socket`, `abilities`,
##   `camera_rig`, `camera`, `voice`
## - local (call on every peer): `set_role(role)`, `is_local()`, `can_control()`, `get_ability(name)`
## - server only: `stun(s)`, `set_input_lock(reason, on)`, `teleport(pos)`, `apply_knockback(v)`,
##   `set_speed_modifier(source, mult)`
## - signals: `role_changed(role)`, `stunned(seconds)`, `died(killer_id, cause)`, `revived`

## Role changed on this peer (after abilities were rebuilt). Fires on all peers.
signal role_changed(role: int)
## Server stunned this player. Fires on all peers.
signal stunned(seconds: float)
## Mirrors Health.died. Fires on all peers.
signal died(killer_id: int, cause: StringName)
## Mirrors Health.revived. Fires on all peers.
signal revived

const VILLAGER_TUNING := "res://game/player/tuning_villager.tres"
const MAGE_TUNING := "res://game/player/tuning_mage.tres"

## Owning peer id (bots: >= Players.BOT_ID_BASE). Set by the spawner before entering the tree.
var peer_id := 1
## Display name shown above the character.
var display_name := "Player"
## True for a server-side local bot (S07). Bots have authority 1 and never take the camera.
var is_bot := false
## Current role (Enums.Role). Change only through `set_role()`.
var role: int = Enums.Role.NONE
## Alive flag (from Health; synced).
var is_alive: bool:
	get:
		return health.is_alive if health else true
## This tick's intent. CONTRACT: movement and abilities read only this. Filled at the start of
## `_physics_process`; children (abilities) run their `_physics_process` after the player in the same tick.
var input := PlayerInput.new()
## When set, fills `input` instead of devices. Must have `fill_input(player: Player, input: PlayerInput,
## delta: float) -> void`. Bots (S07) set this. Only used on the authority peer.
var input_driver: Object = null
## Active movement tuning (villager or mage).
var tuning: PlayerTuning

## Server-authoritative health component.
@onready var health: Health = $Health
## Where carried things sit (S10). Marker3D in front of the chest.
@onready var carry_socket: Marker3D = $CarrySocket
## Role ability scenes are added here at runtime by `set_role()` (S09 mage, S10 interactor, ...).
@onready var abilities: Node3D = $Abilities
## Camera rig: yaw = player body, pitch = this node. Other cards take the view by calling
## `make_current()` on their own camera and give it back with `player.camera.make_current()`.
@onready var camera_rig: Node3D = $CameraRig
## Third-person camera; other systems may take and restore its view.
@onready var camera: Camera3D = $CameraRig/SpringArm/Camera
## Positional voice playback node.
@onready var voice: AudioStreamPlayer3D = $Voice
@onready var _spring: SpringArm3D = $CameraRig/SpringArm
@onready var _nameplate: Label3D = $Nameplate
@onready var _speaking_icon: Label3D = $Speaking
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _collision: CollisionShape3D = $Collision

## Replicated stance flag; remote peers resize their own collision and visuals.
var is_crouching := false
## Replicated quick mantle animation flag (owner alone moves the character).
var is_mantling := false
## Replicated landing tumble flag. While true, can_control() is false.
var is_tumbling := false
## Replicated sprint animation state.
var is_sprinting := false

var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _mantle_armed := false
var _takeoff_y := 0.0
var _fall_peak_y := 0.0
var _tumble_left := 0.0
var _tumble_angle := 0.0
var _mantle_elapsed := 0.0
var _mantle_start := Vector3.ZERO
var _mantle_target := Vector3.ZERO
var _last_bump_ms := -1000000
var _standing_height := 0.0
var _locks: Dictionary = {} # StringName reason -> true
var _stun_left := 0.0
var _speed_mods: Dictionary = {} # StringName source -> float
var _knockback := Vector3.ZERO
var _pending_look := Vector2.ZERO
var _default_layer := 0


func _enter_tree() -> void:
	set_multiplayer_authority(1 if is_bot else peer_id)


func _ready() -> void:
	add_to_group(&"players")
	_nameplate.text = display_name
	_spring.add_excluded_object(get_rid())
	_default_layer = collision_layer
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(absf(peer_id * 0.618034), 1.0), 0.55, 0.9)
	_body_mesh.material_override = mat
	_apply_tuning(VILLAGER_TUNING, "villager")
	health.damaged.connect(func(a: float, src: int, c: StringName) -> void:
		GameEvents.player_damaged.emit(peer_id, a, src, c))
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)
	if is_local():
		camera.current = true
		_nameplate.visible = false
		VoiceManager.listener = self
		GameEvents.local_player_ready.emit(self)
	else:
		VoiceManager.register_speaker(peer_id, voice, self)


func _exit_tree() -> void:
	VoiceManager.unregister_speaker(peer_id)


## True only on the peer whose human controls this player (false for bots and remote players).
func is_local() -> bool:
	return is_multiplayer_authority() and not is_bot


## True when movement/abilities may act: alive, not stunned/tumbling, no input lock.
func can_control() -> bool:
	return is_alive and _stun_left <= 0.0 and _locks.is_empty() and not is_tumbling


## Shows the speaking icon (called every frame for the local player; remote via VoiceManager).
func set_speaking(on: bool) -> void:
	_speaking_icon.visible = on


## NET: call on EVERY peer (MatchManager does this inside its own RPC). Swaps tuning and rebuilds the
## ability scenes from RoleScenes. Abilities get this player's authority (the owning peer).
func set_role(new_role: int) -> void:
	role = new_role
	if role == Enums.Role.MAGE:
		_apply_tuning(MAGE_TUNING, "mage")
	else:
		_apply_tuning(VILLAGER_TUNING, "villager")
	for c in abilities.get_children():
		abilities.remove_child(c)
		c.queue_free()
	for path in RoleScenes.for_role(role):
		var node: Node = load(path).instantiate()
		abilities.add_child(node)
		node.set_multiplayer_authority(get_multiplayer_authority(), true)
	role_changed.emit(role)


## Ability node by its scene root name (e.g. &"MageAbilities"), or null.
func get_ability(ability_name: StringName) -> Node:
	return abilities.get_node_or_null(NodePath(ability_name))


# ------------------------------------------------------------------ server-called hooks

## NET: server only. Freezes control for `seconds` (longest stun wins). Fires `stunned` everywhere.
func stun(seconds: float) -> void:
	if Net.is_server(self):
		Net.broadcast(self, &"_rpc_stun", [seconds])


## NET: server only. Named input lock (e.g. &"head_start", &"reveal"). Control is off while any lock is set.
func set_input_lock(reason: StringName, locked: bool) -> void:
	if Net.is_server(self):
		Net.broadcast(self, &"_rpc_lock", [reason, locked])


## NET: server only. Moves the player (spawns, round reset). The owning peer applies it.
func teleport(pos: Vector3) -> void:
	if Net.is_server(self):
		Net.broadcast(self, &"_rpc_teleport", [pos])


## NET: server only. Adds a velocity impulse (fire wave knockback, bumps). The owning peer applies it.
func apply_knockback(impulse: Vector3) -> void:
	if Net.is_server(self):
		Net.broadcast(self, &"_rpc_knockback", [impulse])


## NET: server only. Speed multiplier per source (e.g. &"carry" 0.85, &"net" 0.5); 1.0 removes it.
func set_speed_modifier(source: StringName, mult: float) -> void:
	if Net.is_server(self):
		Net.broadcast(self, &"_rpc_speed", [source, mult])


## Product of all speed modifiers (1.0 = none).
func speed_multiplier() -> float:
	var m := 1.0
	for v in _speed_mods.values():
		m *= v
	return m


@rpc("any_peer", "call_local", "reliable")
func _rpc_stun(seconds: float) -> void:
	if not Net.from_server(self):
		return
	_stun_left = maxf(_stun_left, seconds)
	stunned.emit(seconds)
	GameEvents.player_stunned.emit(peer_id, seconds)


@rpc("any_peer", "call_local", "reliable")
func _rpc_lock(reason: StringName, locked: bool) -> void:
	if not Net.from_server(self):
		return
	if locked:
		_locks[reason] = true
	else:
		_locks.erase(reason)


@rpc("any_peer", "call_local", "reliable")
func _rpc_teleport(pos: Vector3) -> void:
	if Net.from_server(self):
		# FIX(S04, Codex): players must not carry each other as platforms during round teleports.
		platform_floor_layers &= ~2
		global_position = pos
		_reset_movement()


@rpc("any_peer", "call_local", "reliable")
func _rpc_knockback(impulse: Vector3) -> void:
	if Net.from_server(self):
		_knockback += impulse


@rpc("any_peer", "call_local", "reliable")
func _rpc_speed(source: StringName, mult: float) -> void:
	if not Net.from_server(self):
		return
	if is_equal_approx(mult, 1.0):
		_speed_mods.erase(source)
	else:
		_speed_mods[source] = mult


# ------------------------------------------------------------------ death (corpse look)

func _on_died(killer_id: int, cause: StringName) -> void:
	_reset_movement()
	is_crouching = false
	_update_stance()
	collision_layer = 0 # CONTRACT: dead bodies don't block or get hit; they still rest on the floor
	_body_mesh.rotation.x = -PI / 2.0
	_body_mesh.position.y = tuning.radius
	_nameplate.visible = false
	died.emit(killer_id, cause)
	GameEvents.player_died.emit(peer_id, killer_id, cause)


func _on_revived() -> void:
	collision_layer = _default_layer
	_reset_movement()
	_body_mesh.rotation.x = 0.0
	_body_mesh.position.y = tuning.height / 2.0
	_nameplate.visible = not is_local()
	revived.emit()
	GameEvents.player_revived.emit(peer_id)


# ------------------------------------------------------------------ input + movement

func _unhandled_input(event: InputEvent) -> void:
	if is_local() and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pending_look += event.relative * tuning.mouse_sensitivity


func _physics_process(delta: float) -> void:
	_update_stance()
	_update_pose(delta)
	if not is_multiplayer_authority():
		return
	_stun_left = maxf(0.0, _stun_left - delta)
	_tumble_left = maxf(0.0, _tumble_left - delta)
	is_tumbling = _tumble_left > 0.0
	_read_input(delta)
	if is_local():
		set_speaking(VoiceManager.local_speaking)
		_update_camera(delta)

	if NetworkManager.test_target != null and is_local(): # CONTRACT: existing network test hook
		var t: Vector2 = NetworkManager.test_target
		global_position.x = t.x
		global_position.z = t.y
		velocity = Vector3.ZERO
		move_and_slide()
		return

	rotate_y(-input.look_delta.x)
	camera_rig.rotation.x = clampf(camera_rig.rotation.x - input.look_delta.y,
		tuning.pitch_min, tuning.pitch_max)
	if not can_control():
		_jump_buffer_left = 0.0
		_mantle_armed = false
		is_mantling = false
	if is_mantling:
		_tick_mantle(delta)
		return

	var grounded := is_on_floor()
	_coyote_left = tuning.coyote_time if grounded else maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if input.jump_pressed:
		_jump_buffer_left = tuning.jump_buffer
	if grounded:
		_mantle_armed = false
		_takeoff_y = global_position.y
		_fall_peak_y = global_position.y
	else:
		_fall_peak_y = maxf(_fall_peak_y, global_position.y)
		velocity += get_gravity() * delta

	is_crouching = input.crouch or (is_crouching and not _has_standing_room())
	_update_stance()
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0 and can_control() and not is_crouching:
		velocity.y = tuning.jump_velocity
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_mantle_armed = true
		grounded = false

	is_sprinting = can_control() and input.sprint and not is_crouching and not input.move.is_zero_approx()
	var speed := tuning.crouch_speed if is_crouching else (
		tuning.sprint_speed if is_sprinting else tuning.walk_speed)
	var wish := global_basis * Vector3(input.move.x, 0.0, input.move.y).limit_length()
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var target := wish * speed * speed_multiplier()
	if grounded:
		var rate := tuning.ground_deceleration if wish.is_zero_approx() else tuning.ground_acceleration
		planar = planar.move_toward(target, rate * delta)
	elif wish.is_zero_approx():
		planar = planar.move_toward(Vector3.ZERO, tuning.air_deceleration * delta)
	else:
		# WHY: accelerate only the missing component along intent; never clamp takeoff speed in air.
		var missing := maxf(0.0, target.length() - planar.dot(wish.normalized()))
		planar += wish.normalized() * minf(missing, tuning.air_acceleration * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	velocity += _knockback
	_knockback = Vector3.ZERO
	if _mantle_armed and can_control() and not is_crouching and not grounded and _try_mantle(wish):
		return
	var approach := velocity
	move_and_slide()
	_bump_players(approach)
	if is_on_floor() and not grounded and velocity.y <= 0.0:
		if is_alive and _fall_peak_y - global_position.y >= tuning.fall_tumble_height:
			_tumble_left = tuning.tumble_duration
			is_tumbling = true
			_jump_buffer_left = 0.0
			input.clear()
	if global_position.y < tuning.void_height:
		global_position = Vector3(0.0, tuning.respawn_height, 0.0)
		_reset_movement()


func _try_mantle(wish: Vector3) -> bool:
	if wish.is_zero_approx():
		return false
	var direction := wish.normalized()
	var origin := global_position + Vector3.UP * tuning.mantle_probe_height
	var wall := _ray(origin, origin + direction * (tuning.radius + tuning.mantle_reach))
	if wall.is_empty() or absf((wall.normal as Vector3).y) > tuning.mantle_wall_max_normal_y:
		return false
	var sample: Vector3 = wall.position - wall.normal * (tuning.radius + tuning.mantle_inset)
	var top := _ray(Vector3(sample.x, _takeoff_y + tuning.mantle_max_height + tuning.collision_clearance, sample.z),
		Vector3(sample.x, _takeoff_y + tuning.mantle_min_height - tuning.collision_clearance, sample.z))
	if top.is_empty() or (top.normal as Vector3).dot(Vector3.UP) < cos(floor_max_angle):
		return false
	var rise: float = top.position.y - _takeoff_y
	if rise < tuning.mantle_min_height or rise > tuning.mantle_max_height:
		return false
	var target: Vector3 = top.position + Vector3.UP * tuning.collision_clearance
	if target.y <= global_position.y or not _capsule_clear(target, tuning.height):
		return false
	var lift := Vector3(global_position.x, target.y, global_position.z)
	# WHY: two swept segments prevent mantling through an overhang or across an intervening wall.
	if test_move(global_transform, lift - global_position) or test_move(
		Transform3D(global_basis, lift), target - lift):
		return false
	_mantle_start = global_position
	_mantle_target = target
	_mantle_elapsed = 0.0
	_mantle_armed = false # One pull per takeoff: no wall scaling or repeated upward grabs.
	is_mantling = true
	velocity = Vector3.ZERO
	return true


func _tick_mantle(delta: float) -> void:
	_mantle_elapsed += delta
	var t := minf(1.0, _mantle_elapsed / tuning.mantle_duration)
	var lift := Vector3(_mantle_start.x, _mantle_target.y, _mantle_start.z)
	var next: Vector3
	if t < tuning.mantle_lift_fraction:
		next = _mantle_start.lerp(lift, smoothstep(0.0, tuning.mantle_lift_fraction, t))
	else:
		next = lift.lerp(_mantle_target, smoothstep(tuning.mantle_lift_fraction, 1.0, t))
	var hit := move_and_collide(next - global_position)
	if hit != null or t >= 1.0:
		is_mantling = false
		_fall_peak_y = global_position.y


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 16, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _capsule_clear(feet: Vector3, height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = tuning.radius
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height / 2.0))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _has_standing_room() -> bool:
	return _capsule_clear(global_position + Vector3.UP * tuning.collision_clearance, tuning.height)


func _update_stance() -> void:
	if tuning == null:
		return
	var height := tuning.crouch_height if is_crouching and is_alive else tuning.height
	if is_equal_approx(_standing_height, height):
		return
	_standing_height = height
	(_collision.shape as CapsuleShape3D).height = height
	_collision.position.y = height / 2.0
	(_body_mesh.mesh as CapsuleMesh).height = height
	if is_alive:
		_body_mesh.position.y = height / 2.0
	$Nose.position.y = height * 0.8
	carry_socket.position.y = height * 0.6


func _update_pose(delta: float) -> void:
	if not is_alive:
		return # CONTRACT: death owns the corpse pose.
	_tumble_angle = _tumble_angle + tuning.tumble_roll_speed * delta if is_tumbling else 0.0
	_body_mesh.rotation.x = _tumble_angle


func _update_camera(delta: float) -> void:
	var blend := 1.0 - exp(-tuning.camera_response * delta)
	var height := tuning.camera_height - (tuning.height - tuning.crouch_height if is_crouching else 0.0)
	camera_rig.position.y = lerpf(camera_rig.position.y, height, blend)
	camera.fov = lerpf(camera.fov, tuning.camera_fov + (tuning.sprint_fov_kick if is_sprinting else 0.0), blend)


func _bump_players(approach: Vector3) -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := hit.get_collider() as Player
		if other == null or not other.is_alive or not is_alive:
			continue
		var normal := hit.get_normal()
		normal.y = 0.0
		if normal.is_zero_approx() or -approach.dot(normal) < tuning.bump_min_speed:
			continue
		if Time.get_ticks_msec() - _last_bump_ms < tuning.bump_cooldown * 1000.0:
			return
		_knockback += normal.normalized() * tuning.bump_recoil
		if Net.is_server(self):
			_rpc_bump(other.name)
		else:
			_rpc_bump.rpc_id(1, other.name)
		# Owner rate-limits requests too; the server independently validates and rate-limits.
		_last_bump_ms = Time.get_ticks_msec()
		return


@rpc("any_peer", "call_remote", "reliable")
func _rpc_bump(other_name: StringName) -> void:
	# NET: server alone validates contact and decides the pushed player's impulse.
	if not Net.is_server(self) or Net.sender_id(self) != get_multiplayer_authority() or not is_alive:
		return
	if Time.get_ticks_msec() - _last_bump_ms < tuning.bump_cooldown * 1000.0:
		return
	var other := get_parent().get_node_or_null(NodePath(other_name)) as Player
	if other == null or other == self or not other.is_alive:
		return
	var offset := other.global_position - global_position
	if absf(offset.y) > maxf(tuning.height, other.tuning.height):
		return
	offset.y = 0.0
	if offset.length() > tuning.radius + other.tuning.radius + tuning.bump_contact_slack:
		return
	_last_bump_ms = Time.get_ticks_msec()
	other.apply_knockback(offset.normalized() * tuning.bump_speed)


func _reset_movement() -> void:
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_mantle_armed = false
	is_mantling = false
	is_tumbling = false
	is_sprinting = false
	_tumble_left = 0.0
	_fall_peak_y = global_position.y
	_takeoff_y = global_position.y


func _read_input(delta: float) -> void:
	input.clear_edges()
	if input_driver != null:
		input_driver.fill_input(self, input, delta)
	elif is_local() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.fill_from_devices()
		input.look_delta = _pending_look
	else:
		input.clear()
	_pending_look = Vector2.ZERO
	if not can_control():
		input.clear()


func _apply_tuning(path: String, section: String) -> void:
	tuning = Tuning.load_tuning(path, section) as PlayerTuning
	health.max_hp = tuning.max_hp
	_standing_height = 0.0
	floor_snap_length = tuning.floor_snap
	floor_max_angle = deg_to_rad(tuning.floor_max_angle_degrees)
	_spring.spring_length = tuning.camera_distance
	_spring.position.x = tuning.camera_shoulder
	_spring.margin = tuning.camera_margin
	_spring.collision_mask = 1 | 16
	camera.fov = tuning.camera_fov
	var shape := (_collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	shape.radius = tuning.radius
	shape.height = tuning.height
	_collision.shape = shape
	_collision.position.y = tuning.height / 2.0
	var mesh := (_body_mesh.mesh as CapsuleMesh).duplicate() as CapsuleMesh
	mesh.radius = tuning.radius
	mesh.height = tuning.height
	_body_mesh.mesh = mesh
	_body_mesh.position.y = tuning.height / 2.0
	$Nose.position = Vector3(0, tuning.height * 0.8, -tuning.radius - 0.05)
	camera_rig.position.y = tuning.camera_height
	_nameplate.position.y = tuning.height + 0.35
	_speaking_icon.position.y = tuning.height + 0.7
	voice.position.y = tuning.height * 0.85
	carry_socket.position = Vector3(0, tuning.height * 0.6, -tuning.radius - 0.25)

	_update_stance()
	if not is_alive:
		_body_mesh.rotation.x = -PI / 2.0
		_body_mesh.position.y = tuning.radius
