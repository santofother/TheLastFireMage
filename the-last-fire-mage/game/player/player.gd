class_name Player
extends CharacterBody3D
## Player character (villager and mage share it; role changes tuning + abilities). Owner: S03.
## S02 wrote the contract surface below; S03 rewrites the movement internals but keeps every public
## member and its behaviour. See docs/ARCHITECTURE.md §Player.
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
const MOUSE_SENS := 0.0025 # TUNE: radians per pixel (move to settings later)

## Owning peer id (bots: >= Players.BOT_ID_BASE). Set by the spawner before entering the tree.
var peer_id := 1
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

@onready var health: Health = $Health
## Where carried things sit (S10). Marker3D in front of the chest.
@onready var carry_socket: Marker3D = $CarrySocket
## Role ability scenes are added here at runtime by `set_role()` (S09 mage, S10 interactor, ...).
@onready var abilities: Node3D = $Abilities
## Camera rig: yaw = player body, pitch = this node. Other cards take the view by calling
## `make_current()` on their own camera and give it back with `player.camera.make_current()`.
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/SpringArm/Camera
@onready var voice: AudioStreamPlayer3D = $Voice
@onready var _spring: SpringArm3D = $CameraRig/SpringArm
@onready var _nameplate: Label3D = $Nameplate
@onready var _speaking_icon: Label3D = $Speaking
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _collision: CollisionShape3D = $Collision

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


## True when movement/abilities may act: alive, not stunned, no input lock.
func can_control() -> bool:
	return is_alive and _stun_left <= 0.0 and _locks.is_empty()


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
		global_position = pos
		velocity = Vector3.ZERO


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
	collision_layer = 0 # CONTRACT: dead bodies don't block or get hit; they still rest on the floor
	_body_mesh.rotation.x = -PI / 2.0
	_body_mesh.position.y = tuning.radius
	_nameplate.visible = false
	died.emit(killer_id, cause)
	GameEvents.player_died.emit(peer_id, killer_id, cause)


func _on_revived() -> void:
	collision_layer = _default_layer
	_body_mesh.rotation.x = 0.0
	_body_mesh.position.y = tuning.height / 2.0
	_nameplate.visible = not is_local()
	revived.emit()
	GameEvents.player_revived.emit(peer_id)


# ------------------------------------------------------------------ input + movement (S03 replaces movement)

func _unhandled_input(event: InputEvent) -> void:
	if is_local() and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pending_look += event.relative * MOUSE_SENS


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_read_input(delta)
	_stun_left = maxf(0.0, _stun_left - delta)
	if is_local():
		set_speaking(VoiceManager.local_speaking)
	if not is_on_floor():
		velocity += get_gravity() * delta

	if NetworkManager.test_target != null and is_local(): # headless test hook
		var t: Vector2 = NetworkManager.test_target
		global_position.x = t.x
		global_position.z = t.y
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	rotate_y(-input.look_delta.x)
	camera_rig.rotation.x = clampf(camera_rig.rotation.x - input.look_delta.y, -1.2, 0.6)
	if input.jump_pressed and is_on_floor():
		velocity.y = tuning.jump_velocity
	var speed := (tuning.sprint_speed if input.sprint else tuning.walk_speed) * speed_multiplier()
	var move := (transform.basis * Vector3(input.move.x, 0, input.move.y)).normalized() * speed
	velocity.x = move.x + _knockback.x
	velocity.z = move.z + _knockback.z
	velocity.y += _knockback.y
	_knockback = Vector3.ZERO if _knockback.length() < 0.1 else _knockback * 0.85
	move_and_slide()
	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 0)
		velocity = Vector3.ZERO


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
