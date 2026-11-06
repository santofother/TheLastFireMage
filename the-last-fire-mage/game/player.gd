extends CharacterBody3D
## Greybox third-person capsule. The owning peer simulates its own movement (client-authoritative for
## this spike); position/rotation replicate via MultiplayerSynchronizer. To go server-authoritative later,
## send input to the server instead and make the server the synchronizer authority.

const SPEED := 5.0
const JUMP_VELOCITY := 4.8
const MOUSE_SENS := 0.0025

var peer_id := 1
var display_name := "Player"

@onready var nameplate: Label3D = $Nameplate
@onready var speaking_icon: Label3D = $Speaking
@onready var voice: AudioStreamPlayer3D = $Voice
@onready var pivot: Node3D = $CameraPivot
@onready var spring: SpringArm3D = $CameraPivot/SpringArm
@onready var camera: Camera3D = $CameraPivot/SpringArm/Camera
@onready var body_mesh: MeshInstance3D = $Body


func _enter_tree() -> void:
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	nameplate.text = display_name
	spring.add_excluded_object(get_rid())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(peer_id * 0.618034, 1.0), 0.55, 0.9)
	body_mesh.material_override = mat
	if is_multiplayer_authority():
		camera.current = true
		nameplate.visible = false
		VoiceManager.listener = self
	else:
		VoiceManager.register_speaker(peer_id, voice, self)


func _exit_tree() -> void:
	VoiceManager.unregister_speaker(peer_id)


func set_speaking(on: bool) -> void:
	speaking_icon.visible = on


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * MOUSE_SENS, -1.2, 0.6)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	set_speaking(VoiceManager.local_speaking)
	if not is_on_floor():
		velocity += get_gravity() * delta

	if NetworkManager.test_target != null: # headless test hook
		var t: Vector2 = NetworkManager.test_target
		global_position.x = t.x
		global_position.z = t.y
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var dir := Vector2.ZERO
	if active:
		if Input.is_physical_key_pressed(KEY_W): dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): dir.y += 1
		if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): dir.x += 1
		if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var move := transform.basis * Vector3(dir.x, 0, dir.y)
	move = move.normalized() * SPEED
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()
	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 0)
		velocity = Vector3.ZERO
