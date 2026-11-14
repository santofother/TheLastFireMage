class_name Player
extends CharacterBody3D
## Player character (villager and mage share it; role changes tuning + abilities). Owner: S03.
## Momentum, buffered/coyote jumps, crouch, one-shot ledge mantles, fall tumbles and contact bumps.
## Public contract: docs/ARCHITECTURE.md §Player; replicated movement flags listed below.
##
## NET: spawned by Main's MultiplayerSpawner on the server (data {id, name, pos, bot}). Node name = peer id.
## Multiplayer authority = owning peer (client-authoritative movement); local bots (S07) use authority 1.
## `Health` child is always server-authoritative. Position/rotation replicate via `Sync` (20 Hz) as one timestamped
## snapshot (`net_state`); remote peers buffer snapshots and render NET_INTERP_DELAY in the past, interpolating
## between them, so other players move (and therefore animate) smoothly online.
# WHY: raw position replication snapped remote players 20x a second; the visuals read speed from those jumps,
# so walk/run animations stuttered and flipped to idle between packets, worse with internet jitter.
## Server-side effects on movement (stun, lock, teleport, knockback, speed) are public funcs the SERVER
## calls; they RPC to every peer and the owning peer applies them.
##
## Public API:
## - vars: `peer_id`, `display_name`, `is_bot`, `role` (Enums.Role), `is_alive`, `velocity` (built-in),
##   `input` (PlayerInput), `input_driver`, `tuning` (PlayerTuning), `health`, `carry_socket`, `abilities`,
##   `camera_rig`, `camera`, `voice`, `stamina` (owner only)
## - local (call on every peer): `set_role(role)`, `is_local()`, `can_control()`, `get_ability(name)`,
##   `net_position()` (newest received position, no interpolation delay)
## - server only: `stun(s)`, `set_input_lock(reason, on)`, `teleport(pos)`, `apply_knockback(v)`,
##   `set_speed_modifier(source, mult)`
## - downed villagers: `bleed_out_left`, `being_revived` (all peers), `stun_time_left()`
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
## Villager body (`VillagerSkins` id). Cosmetic, so the owner sets it and the synchronizer sends it.
# NET: owner peer writes; every peer applies. Values are clamped because they come from clients.
var villager_skin := 0:
	set(value):
		villager_skin = VillagerSkins.clamp_id(value)
		if is_node_ready():
			_villager_visual.set_skin(villager_skin)
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
@onready var _speaking_icon: Label3D = $Speaking
# WHY: the capsule is still the mage's body. Villagers hide it and show $VillagerVisual instead.
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _villager_visual: VillagerVisual = $VillagerVisual
@onready var _mage_visual: MageVisual = $MageVisual
@onready var _collision: CollisionShape3D = $Collision

## Replicated stance flag; remote peers resize their own collision and visuals.
var is_crouching := false
## Replicated quick mantle animation flag (owner alone moves the character).
var is_mantling := false
## Replicated landing tumble flag. While true, can_control() is false.
var is_tumbling := false
## Replicated sprint animation state.
var is_sprinting := false
## Owner's remaining movement stamina; read locally by the HUD.
var stamina := 0.0
## Replicated: the owner's controller is off the floor. Remote peers cannot ask is_on_floor() themselves.
var is_airborne := false
## Replicated: metres the feet are currently pulled up by a mid-air crouch (0 = not tucked).
# NET: owner peer writes; every peer sizes its capsule and offsets its visuals from it.
var air_tuck_lift := 0.0
## Replicated movement snapshot [send_time, px, py, pz, qx, qy, qz, qw]. Owner writes it every physics tick.
# NET: owner peer writes; remote peers buffer and interpolate (see _net_interpolate). CONTRACT: this replaces
# the old raw `position`/`rotation` replication; don't add those back to Sync.
var net_state := PackedFloat32Array():
	set = _set_net_state
## Vertical offset for the character model: keeps the head still during a tuck and smooths step-ups.
var visual_y_offset := 0.0
## Seconds until a downed villager bleeds out. Counts on every peer for the HUD; the server decides the death.
var bleed_out_left := 0.0
## True while a villager is holding revive on this downed player (bleed-out pauses). Set by the server.
var being_revived := false
var _revive_ping_msec := -1000000 # NET: server. Last tick an Interactor channelled a revive on us.
var _stun_fx: Node3D

var _step_offset := 0.0
var _step_distance_debt := 0.0
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _mantle_armed := false
var _mantled_in_air := false
var _takeoff_y := 0.0
var _fall_peak_y := 0.0
var _jumped_in_air := false ## FIX(S11, Claude): true only if airborne from a jump (walking off = no damage)
var _jump_sprinted := false
var _stamina_delay := 0.0
var _sprint_exhausted := false
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
var _snaps: Array = [] # remote only: [sender_time, position, quaternion], oldest first
var _clock_offset := INF # remote only: local clock - sender clock (+ fastest latency seen), min-filtered

const NET_INTERP_DELAY := 0.1 # TUNE seconds remote players are rendered in the past (2 sync intervals)
const NET_MAX_EXTRAPOLATE := 0.15 # TUNE seconds to keep moving on a stalled connection before holding still
const NET_SNAP_DISTANCE := 6.0 # TUNE metres: a bigger jump between snapshots is a teleport, not motion


func _enter_tree() -> void:
	set_multiplayer_authority(1 if is_bot else peer_id)


func _ready() -> void:
	add_to_group(&"players")
	_spring.add_excluded_object(get_rid())
	_default_layer = collision_layer
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(absf(peer_id * 0.618034), 1.0), 0.55, 0.9)
	_body_mesh.material_override = mat
	_apply_tuning(VILLAGER_TUNING, "villager")
	_update_role_visual()
	if is_multiplayer_authority():
		villager_skin = posmod(peer_id, VillagerSkins.NAMES.size()) if is_bot else VillagerSkins.local
	_villager_visual.set_skin(villager_skin)
	health.damaged.connect(func(a: float, src: int, c: StringName) -> void:
		GameEvents.player_damaged.emit(peer_id, a, src, c))
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)
	health.downed.connect(_on_downed)
	health.recovered.connect(_on_recovered)
	_add_revive_interactable()
	_build_stun_fx()
	if is_local():
		camera.current = true
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
	return is_alive and not health.is_downed and _stun_left <= 0.0 and _locks.is_empty() and not is_tumbling


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
	_update_role_visual()
	for c in abilities.get_children():
		abilities.remove_child(c)
		c.queue_free()
	for path in RoleScenes.for_role(role):
		var node: Node = load(path).instantiate()
		abilities.add_child(node)
		node.set_multiplayer_authority(get_multiplayer_authority(), true)
	role_changed.emit(role)


## Seconds of stun left (accurate on the owning peer and the server; other peers count down too).
func stun_time_left() -> float:
	return _stun_left


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
		_snaps.clear() # remote copies: don't slide back toward pre-teleport snapshots
		_reset_movement()
		_refill_stamina()


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
	died.emit(killer_id, cause)
	GameEvents.player_died.emit(peer_id, killer_id, cause)


func _on_downed() -> void:
	bleed_out_left = tuning.bleed_out_time
	being_revived = false
	_reset_movement()
	is_crouching = false
	_update_stance()
	_body_mesh.rotation.x = -PI / 2.0
	_body_mesh.position.y = tuning.radius


func _on_recovered() -> void:
	_reset_movement()
	_body_mesh.rotation.x = 0.0
	_body_mesh.position.y = tuning.height / 2.0


## Lets living villagers revive this player with E while they are downed. Server validates via InteractManager.
func _add_revive_interactable() -> void:
	var node := Interactable.new()
	node.name = "Interactable"
	node.collision_layer = 8
	node.collision_mask = 0
	node.kind = &"revive"
	node.max_distance = 2.5
	node.hold_time = tuning.revive_hold_time
	node.condition = func(who: Node) -> bool:
		return who != self and health.is_downed and health.is_alive and who.is_alive \
			and who.role == Enums.Role.VILLAGER
	node.prompt_provider = func(_who: Node) -> String: return "Hold to revive %s" % display_name
	node.interacted.connect(func(_who: Node) -> void:
		health.recover(health.max_hp * tuning.revive_hp_fraction))
	add_child(node)


## NET: server only. An Interactor calls this every tick it channels a revive on this player.
func note_revive_hold() -> void:
	_revive_ping_msec = Time.get_ticks_msec()


# A downed villager dies after `bleed_out_time` unless revived. A revive in progress pauses the clock.
func _tick_bleed_out(delta: float) -> void:
	if not health.is_downed or not is_alive:
		return
	if Net.is_server(self):
		var reviving := Time.get_ticks_msec() - _revive_ping_msec < 250
		if reviving != being_revived:
			Net.broadcast(self, &"_rpc_bleed", [bleed_out_left, reviving])
	if being_revived:
		return
	bleed_out_left = maxf(0.0, bleed_out_left - delta)
	if Net.is_server(self) and bleed_out_left <= 0.0:
		print("[Game] %s bled out" % name)
		health.kill(0, &"bled_out")


@rpc("any_peer", "call_local", "reliable")
func _rpc_bleed(left: float, reviving: bool) -> void:
	if Net.from_server(self):
		bleed_out_left = left
		being_revived = reviving


# Cartoon stars circling the head while stunned, so everyone can see a stun land (see StunStars).
func _build_stun_fx() -> void:
	_stun_fx = StunStars.new()
	add_child(_stun_fx)


func _update_stun_fx(delta: float) -> void:
	(_stun_fx as StunStars).tick(delta, _stun_left > 0.0 and is_alive, tuning.height + visual_y_offset)


func _on_revived() -> void:
	collision_layer = _default_layer
	_reset_movement()
	_body_mesh.rotation.x = 0.0
	_body_mesh.position.y = tuning.height / 2.0
	revived.emit()
	GameEvents.player_revived.emit(peer_id)


# ------------------------------------------------------------------ input + movement

func _unhandled_input(event: InputEvent) -> void:
	if is_local() and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pending_look += event.relative * tuning.mouse_sensitivity


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_net_interpolate() # before the child visuals sample our position this tick
	_physics_step(delta)
	if is_multiplayer_authority():
		net_state = PackedFloat32Array([_net_now(), position.x, position.y, position.z,
			quaternion.x, quaternion.y, quaternion.z, quaternion.w])


static func _net_now() -> float:
	return Time.get_ticks_usec() / 1000000.0


# NET: remote peers. Called by Sync for every received snapshot.
func _set_net_state(v: PackedFloat32Array) -> void:
	net_state = v
	if v.size() < 8 or is_multiplayer_authority():
		return
	var t := v[0]
	var pos := Vector3(v[1], v[2], v[3])
	var q := Quaternion(v[4], v[5], v[6], v[7]).normalized()
	if not is_inside_tree():
		position = pos # spawn state
		quaternion = q
		return
	# Min-filtered clock offset: tracks the fastest delivery; drifts up slowly if the route gets slower.
	var off := _net_now() - t
	_clock_offset = off if off < _clock_offset else _clock_offset + (off - _clock_offset) * 0.02
	if not _snaps.is_empty():
		var last: Array = _snaps[_snaps.size() - 1]
		if t <= float(last[0]):
			return # duplicate or out of order
		if pos.distance_to(last[1]) > NET_SNAP_DISTANCE:
			_snaps.clear() # teleport: jump there instead of sliding across the map
			position = pos
			quaternion = q
	_snaps.append([t, pos, q])
	if _snaps.size() > 32:
		_snaps.pop_front()


## Newest known position: the owner's real one, or the latest received snapshot on remote peers (no
## interpolation delay). Use it for tight server-side checks; visuals and most gameplay use global_position.
func net_position() -> Vector3:
	if is_multiplayer_authority() or _snaps.is_empty():
		return global_position
	return get_parent().global_transform * (_snaps[_snaps.size() - 1][1] as Vector3)


## Render remote players NET_INTERP_DELAY behind the newest data, interpolating between snapshots.
func _net_interpolate() -> void:
	if _snaps.is_empty():
		return
	var rt := _net_now() - _clock_offset - NET_INTERP_DELAY
	while _snaps.size() > 2 and float(_snaps[1][0]) <= rt:
		_snaps.pop_front()
	var a: Array = _snaps[0]
	if _snaps.size() == 1 or rt <= float(a[0]):
		position = a[1]
		quaternion = a[2]
		return
	var b: Array = _snaps[1]
	var span := maxf(float(b[0]) - float(a[0]), 0.001)
	var w := (rt - float(a[0])) / span
	if w > 1.0: # data is late: keep moving a little (extrapolate), then hold
		w = 1.0 + minf(rt - float(b[0]), NET_MAX_EXTRAPOLATE) / span
	position = (a[1] as Vector3).lerp(b[1], w)
	quaternion = (a[2] as Quaternion).slerp(b[2], clampf(w, 0.0, 1.0))


func _physics_step(delta: float) -> void:
	_update_stance()
	_update_pose(delta)
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-tuning.step_smoothing * delta))
	visual_y_offset = _step_offset - air_tuck_lift
	_stun_left = maxf(0.0, _stun_left - delta)
	_update_stun_fx(delta)
	_tick_bleed_out(delta)
	if not is_multiplayer_authority():
		return
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
		_mantled_in_air = false
		_mantle_armed = false
		_takeoff_y = global_position.y
		_fall_peak_y = global_position.y
	else:
		_fall_peak_y = maxf(_fall_peak_y, global_position.y)
		velocity += get_gravity() * delta

	_update_crouch(grounded)
	_update_stance()
	# WHY: jumping out of a crouch stands first; holding crouch then tucks the legs next tick (crouch jump).
	var can_jump := can_control() and air_tuck_lift <= 0.0 and (not is_crouching or _has_standing_room()) \
		and stamina >= tuning.jump_stamina_cost
	var mantle_cost := 0.0 if _jumped_in_air else tuning.jump_stamina_cost
	if input.jump_pressed and not grounded and can_control() and not is_crouching and not _mantled_in_air and stamina >= mantle_cost:
		if _try_space_mantle():
			if mantle_cost > 0.0:
				_spend_stamina(mantle_cost)
			is_sprinting = false
			return
	is_sprinting = can_control() and input.sprint and not is_crouching \
		and not input.move.is_zero_approx() and not _sprint_exhausted and stamina > 0.0
	_stamina_delay = maxf(0.0, _stamina_delay - delta)
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0 and can_jump:
		_spend_stamina(tuning.jump_stamina_cost)
		if is_crouching:
			is_crouching = false
			_update_stance()
		velocity.y = tuning.jump_velocity
		_jumped_in_air = true
		_jump_sprinted = is_sprinting
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_mantle_armed = true
		grounded = false
	elif is_sprinting and grounded:
		_spend_stamina(tuning.sprint_stamina_per_second * delta)
	elif grounded and _stamina_delay <= 0.0 and is_alive and not health.is_downed:
		stamina = minf(tuning.max_stamina, stamina + tuning.stamina_recovery_per_second * delta)
		if stamina >= minf(tuning.sprint_recovery_stamina, tuning.max_stamina):
			_sprint_exhausted = false

	if grounded:
		# WHY: sliding up a ramp leaves upward speed in velocity.y; kept, it launched players off every crest
		# and notch (a free hop plus extra distance). On the floor, slope motion comes from move_and_slide.
		velocity.y = minf(velocity.y, 0.0)
	var speed := tuning.crouch_speed if is_crouching and air_tuck_lift <= 0.0 else (
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
		is_sprinting = false
		return
	if grounded and can_control():
		_try_step_up(delta)
	else:
		_step_distance_debt = 0.0
	var approach := velocity
	_move_paying_step_debt(delta)
	is_airborne = not is_on_floor()
	_bump_players(approach)
	_smash_furniture(approach)
	if is_on_floor() and not grounded and velocity.y <= 0.0:
		var drop := _fall_peak_y - global_position.y
		var sprawls := drop >= tuning.fall_tumble_height
		# CONTRACT: whenever the sprawl plays the player takes fall damage, even after a mid-air mantle.
		if is_alive and (sprawls or not _mantled_in_air):
			_report_fall(maxf(drop, tuning.fall_story_height) if sprawls else drop, _jump_sprinted, _jumped_in_air)
		_jumped_in_air = false
		if is_alive and sprawls:
			_tumble_left = tuning.tumble_duration
			is_tumbling = true
			_jump_buffer_left = 0.0
			input.clear()
	if global_position.y < tuning.void_height:
		global_position = Vector3(0.0, tuning.respawn_height, 0.0)
		_reset_movement()


## FIX(S11, Claude): no fall damage below `fall_story_height` (3.1 m) however you leave the ledge.
## Above it, walking/sprinting off (no jump) does reduced damage; jumps hurt more.
## NET: owner peer reports the fall, server validates the sender and applies damage.
func _report_fall(fall_height: float, sprinted: bool, jumped: bool = true) -> void:
	if fall_height < tuning.fall_story_height:
		return
	# FIX(S14, Codex): Measure the ledge drop separately so the jump arc doesn't count as roof height.
	var ledge_drop := _takeoff_y - global_position.y
	if Net.is_server(self):
		_apply_fall_damage(fall_height, sprinted, jumped, ledge_drop)
	else:
		_rpc_fall.rpc_id(1, fall_height, sprinted, jumped, ledge_drop)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_fall(fall_height: float, sprinted: bool, jumped: bool, ledge_drop: float) -> void:
	if not Net.is_server(self) or Net.sender_id(self) != get_multiplayer_authority():
		return
	_apply_fall_damage(fall_height, sprinted, jumped, ledge_drop)


func _apply_fall_damage(fall_height: float, sprinted: bool, jumped: bool, ledge_drop: float) -> void:
	if not is_alive or health.is_downed or fall_height < tuning.fall_story_height:
		return
	var base := tuning.fall_damage_walk_off
	if jumped:
		base = tuning.fall_damage_sprint_jump if sprinted else tuning.fall_damage_jump
	var damage := base * tuning.fall_damage_scale * minf(fall_height, 60.0) / tuning.fall_story_height
	if ledge_drop >= tuning.fall_story_height and ledge_drop <= tuning.one_story_drop_max:
		damage *= 0.5
	# WHY: a lethal fall downs the player (revivable by a villager) a limited number of times per round.
	# The mage never goes down: a lethal fall kills it outright.
	if damage >= health.hp and not health.invulnerable and role == Enums.Role.VILLAGER \
			and health.downs_used < tuning.fall_downs_allowed:
		health.down(tuning.downed_hp)
		return
	health.apply_damage(damage, 0, &"fall")


# FIX(S02, Codex): the shipped stub ignored Space in the air; probe a ledge on a fresh press.
func _try_space_mantle() -> bool:
	var direction := (global_basis * Vector3(input.move.x, 0, input.move.y)).normalized()
	if direction.is_zero_approx():
		direction = -global_basis.z
	var origin := global_position + Vector3.UP * tuning.mantle_space_probe_height
	var wall := _ray(origin, origin + direction * (tuning.radius + tuning.mantle_space_reach))
	if wall.is_empty() or absf((wall.normal as Vector3).y) > 0.2:
		return false
	var sample: Vector3 = wall.position - wall.normal * (tuning.radius + tuning.mantle_space_clearance)
	var top := _ray(Vector3(sample.x, global_position.y + tuning.mantle_space_max_rise, sample.z),
		Vector3(sample.x, origin.y, sample.z))
	if top.is_empty() or (top.normal as Vector3).dot(Vector3.UP) < cos(floor_max_angle):
		return false
	var target: Vector3 = top.position + Vector3.UP * tuning.mantle_space_clearance
	if not _capsule_clear(target, tuning.height):
		return false
	var lift := Vector3(global_position.x, target.y, global_position.z)
	# WHY: sweep up and then across so the pull cannot pass through ceilings or walls.
	if test_move(global_transform, lift - global_position) or test_move(
		Transform3D(global_basis, lift), target - lift):
		return false
	# WHY: this path used to set global_position directly, which read as a teleport.
	_begin_mantle(target)
	return true


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
	_begin_mantle(target)
	return true


func _begin_mantle(target: Vector3) -> void:
	_mantle_start = global_position
	_mantle_target = target
	_mantle_elapsed = 0.0
	_mantled_in_air = true
	_mantle_armed = false # One pull per takeoff: no wall scaling or repeated upward grabs.
	_jump_buffer_left = 0.0
	is_mantling = true
	velocity = Vector3.ZERO


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
		_jumped_in_air = false
		_fall_peak_y = global_position.y


func _update_role_visual() -> void:
	var mage := role == Enums.Role.MAGE
	_villager_visual.visible = not mage
	# FIX(mage model): the capsule and nose are replaced by the mage model.
	_mage_visual.visible = mage
	_body_mesh.visible = false
	$Nose.visible = false


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


# Ground crouch shortens the capsule from the top. Air crouch pulls the feet up instead (head stays put),
# so a tuck timed near the apex clears a slightly taller ledge. CONTRACT: only the authority calls this.
func _update_crouch(grounded: bool) -> void:
	if grounded:
		if air_tuck_lift > 0.0:
			_step_offset -= air_tuck_lift
			air_tuck_lift = 0.0
		is_crouching = input.crouch or (is_crouching and not _has_standing_room())
	elif input.crouch and air_tuck_lift <= 0.0 and not is_crouching:
		_tuck_legs()
	elif not input.crouch and air_tuck_lift > 0.0:
		_untuck_legs()


func _tuck_legs() -> void:
	var apex := 1.0 - clampf(absf(velocity.y) / maxf(tuning.jump_velocity, 0.01), 0.0, 1.0)
	var lift := minf(lerpf(tuning.crouch_jump_lift_min, tuning.crouch_jump_lift_max, apex),
		tuning.height - tuning.radius * 2.0 - 0.01)
	if lift <= 0.0:
		return
	global_position.y += lift
	air_tuck_lift = lift
	is_crouching = true
	camera_rig.position.y -= lift


func _untuck_legs() -> void:
	# Feet may be over a ledge now; then they stay up until landing.
	if test_move(global_transform.translated(Vector3.UP * tuning.collision_clearance), Vector3.DOWN * air_tuck_lift):
		return
	global_position.y -= air_tuck_lift
	camera_rig.position.y += air_tuck_lift
	air_tuck_lift = 0.0
	is_crouching = false


# Runs over kerbs and low ledges instead of stopping dead. Solid world geometry only: players, chickens and
# breakable furniture still block, and steep rock is rejected by the floor-angle check.
func _try_step_up(delta: float) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if planar.length() < tuning.step_min_speed or velocity.y > 0.1:
		return
	var direction := planar.normalized()
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, direction * maxf(planar.length() * delta, 0.05), hit):
		return
	var collider := hit.get_collider()
	if collider is CharacterBody3D or collider is BreakableProp:
		return
	# WHY: a walkable contact (ramp, rounded kerb edge) is handled by move_and_slide. Stepping there turned
	# every ramp into a run of tiny teleports that hopped and jittered the camera.
	if hit.get_normal().dot(Vector3.UP) >= cos(floor_max_angle) - 0.01:
		return
	var up := Vector3.UP * (tuning.step_max_height + tuning.collision_clearance)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	var nudge := direction * tuning.radius * 0.6
	if test_move(raised, nudge):
		return
	var above := raised.translated(nudge)
	var down := KinematicCollision3D.new()
	if not test_move(above, Vector3.DOWN * (up.length() + 0.05), down):
		return
	var rise: float = above.origin.y - down.get_travel().length() - global_position.y
	if rise < tuning.step_min_height or rise > tuning.step_max_height:
		return
	var point := down.get_position() + direction * 0.03
	var top := _ray(point + Vector3.UP * 0.3, point + Vector3.DOWN * 0.3)
	if top.is_empty() or (top.normal as Vector3).dot(Vector3.UP) < cos(floor_max_angle):
		return
	global_position += nudge + Vector3.UP * (rise + 0.005)
	_step_distance_debt += nudge.length()
	_step_offset -= rise
	camera_rig.position.y -= rise


# WHY: a step-up nudges the player forward. Those metres come out of the next ticks of normal movement,
# otherwise every notch on a ramp adds distance on top of the run speed.
func _move_paying_step_debt(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z)
	var travel := planar.length() * delta
	if _step_distance_debt <= 0.0 or travel <= 0.0:
		move_and_slide()
		return
	var paid := minf(_step_distance_debt, travel)
	_step_distance_debt -= paid
	var scaled := planar * (1.0 - paid / travel)
	velocity.x = scaled.x
	velocity.z = scaled.y
	move_and_slide()
	velocity.x = planar.x
	velocity.z = planar.y


func _update_stance() -> void:
	if tuning == null:
		return
	var crouched := tuning.height - air_tuck_lift if air_tuck_lift > 0.0 else tuning.crouch_height
	var height := crouched if is_crouching and is_alive else tuning.height
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
	var drop := air_tuck_lift if air_tuck_lift > 0.0 else (tuning.height - tuning.crouch_height if is_crouching else 0.0)
	var height := tuning.camera_height - drop
	camera_rig.position.y = lerpf(camera_rig.position.y, height, blend)
	camera.fov = lerpf(camera.fov, tuning.camera_fov + (tuning.sprint_fov_kick if is_sprinting else 0.0), blend)


# Charging into wooden furniture breaks it; the server confirms. Keeps the player's run going on a hit.
func _smash_furniture(approach: Vector3) -> void:
	if not is_alive:
		return
	var breakables := GameEvents.system(&"breakables") as BreakableManager
	if breakables == null:
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var prop := hit.get_collider() as BreakableProp
		if prop == null:
			continue
		var momentum := -approach.dot(hit.get_normal()) * tuning.body_mass
		if breakables.report_impact(self, prop, momentum):
			velocity.x = approach.x
			velocity.z = approach.z
			return


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
	# Newest received positions, not the 100 ms-delayed interpolated ones (contact is a tight check).
	var offset := other.net_position() - net_position()
	if absf(offset.y) > maxf(tuning.height, other.tuning.height):
		return
	offset.y = 0.0
	if offset.length() > tuning.radius + other.tuning.radius + tuning.bump_contact_slack:
		return
	_last_bump_ms = Time.get_ticks_msec()
	other.apply_knockback(offset.normalized() * tuning.bump_speed)


func _reset_movement() -> void:
	_mantled_in_air = false
	_jumped_in_air = false
	_jump_sprinted = false
	air_tuck_lift = 0.0
	_step_offset = 0.0
	_step_distance_debt = 0.0
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_mantle_armed = false
	is_mantling = false
	is_tumbling = false
	is_sprinting = false
	is_airborne = false
	_tumble_left = 0.0
	_fall_peak_y = global_position.y
	_takeoff_y = global_position.y


func _spend_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = maxf(0.0, stamina - amount)
	_stamina_delay = tuning.stamina_recovery_delay
	if stamina <= 0.0:
		_sprint_exhausted = true


func _refill_stamina() -> void:
	stamina = tuning.max_stamina
	_stamina_delay = 0.0
	_sprint_exhausted = false


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
	_refill_stamina()
	health.max_hp = tuning.max_hp
	_standing_height = 0.0
	floor_snap_length = tuning.floor_snap
	floor_max_angle = deg_to_rad(tuning.floor_max_angle_degrees)
	# WHY: same speed up and down ramps, and a near head-on wall contact slides instead of sticking.
	floor_constant_speed = true
	wall_min_slide_angle = 0.0
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
	_speaking_icon.position.y = tuning.height + 0.7
	voice.position.y = tuning.height * 0.85
	carry_socket.position = Vector3(0, tuning.height * 0.6, -tuning.radius - 0.25)

	_update_stance()
	if not is_alive:
		_body_mesh.rotation.x = -PI / 2.0
		_body_mesh.position.y = tuning.radius
