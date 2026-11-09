class_name BreakableProp
extends StaticBody3D
## Wooden furniture that splinters into a pile of planks. Owner: furnishing pass (S05 follow-up).
## Public API: `shatter(cause, seed_value, animate)`, `restore()`, `suspend_collision(seconds)`, `broken`.
## Expects a `Collision` child; every other Node3D child counts as the furniture itself. Built by tools/map/build_props.gd.
## NET: every peer runs the visuals. Only BreakableManager decides when a prop breaks.

const GROUP := &"breakable_prop"
## CONTRACT: sent over the network as ints by BreakableManager.
enum Cause { IMPACT, FIRE }

## TUNE: Planks left behind.
@export var pile_pieces := 7
## TUNE: Radius of the plank pile, metres.
@export var pile_radius := 0.24

## True once splintered. Cleared by `restore()`.
var broken := false

var _layer := 0
var _pile: Node3D

static var _plank_mesh: BoxMesh
static var _chip_mesh: BoxMesh
static var _wood: StandardMaterial3D
static var _char: StandardMaterial3D
static var _ember: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	_layer = collision_layer


## Hides the furniture and leaves a plank pile. `seed_value` keeps the pile identical on every peer.
func shatter(cause: int, seed_value: int, animate: bool) -> void:
	if broken:
		return
	broken = true
	collision_layer = 0
	# WHY: a player's move_and_slide can trigger this from inside a physics step.
	($Collision as CollisionShape3D).set_deferred(&"disabled", true)
	_show_furniture(false)
	_ensure_resources()
	_pile = _build_pile(cause == Cause.FIRE, seed_value)
	add_child(_pile)
	if animate and DisplayServer.get_name() != "headless":
		_burst(cause == Cause.FIRE)


## Puts the furniture back for a new round.
func restore() -> void:
	if not broken:
		return
	broken = false
	collision_layer = _layer
	($Collision as CollisionShape3D).set_deferred(&"disabled", false)
	_show_furniture(true)
	if _pile:
		_pile.queue_free()
		_pile = null


## NET: owner peer only. Lets a charging player keep moving while the server confirms the break.
func suspend_collision(seconds: float) -> void:
	var shape := $Collision as CollisionShape3D
	shape.set_deferred(&"disabled", true)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(shape) and not broken:
			shape.disabled = false)


# Hides the model and anything resting on it, such as candles on a table.
func _show_furniture(shown: bool) -> void:
	for child in get_children():
		if child is Node3D and child != _pile:
			(child as Node3D).visible = shown


func _build_pile(burnt: bool, seed_value: int) -> Node3D:
	var pile := Node3D.new()
	pile.name = "Pile"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value)
	for i in pile_pieces:
		var plank := MeshInstance3D.new()
		plank.mesh = _plank_mesh
		plank.material_override = _char if burnt else _wood
		var angle := rng.randf_range(0.0, TAU)
		var distance := pile_radius * sqrt(rng.randf())
		# Stack from the middle outward so the pile reads as a heap, not a flat scatter.
		var height := 0.03 + (1.0 - distance / pile_radius) * 0.07 * float(i % 3)
		plank.position = Vector3(cos(angle) * distance, height, sin(angle) * distance)
		plank.rotation = Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0.0, TAU), rng.randf_range(-0.22, 0.22))
		plank.scale = Vector3(rng.randf_range(0.7, 1.25), 1.0, rng.randf_range(0.8, 1.2))
		pile.add_child(plank)
	return pile


func _burst(burnt: bool) -> void:
	_emit(_chip_mesh, _char if burnt else _wood, 16, 3.6, 0.8, Vector3(0.0, -9.8, 0.0))
	if burnt:
		_emit(_chip_mesh, _ember, 12, 2.2, 0.55, Vector3(0.0, 1.2, 0.0))


func _emit(mesh: Mesh, material: Material, amount: int, speed: float, life: float, gravity: Vector3) -> void:
	var chips := CPUParticles3D.new()
	chips.mesh = mesh
	chips.material_override = material
	chips.amount = amount
	chips.one_shot = true
	chips.explosiveness = 1.0
	chips.lifetime = life
	chips.direction = Vector3.UP
	chips.spread = 65.0
	chips.initial_velocity_min = speed * 0.45
	chips.initial_velocity_max = speed
	chips.angular_velocity_min = -540.0
	chips.angular_velocity_max = 540.0
	chips.gravity = gravity
	chips.position = Vector3.UP * 0.25
	chips.finished.connect(chips.queue_free)
	add_child(chips)
	chips.emitting = true


static func _ensure_resources() -> void:
	if _plank_mesh:
		return
	_plank_mesh = BoxMesh.new()
	_plank_mesh.size = Vector3(0.06, 0.035, 0.34)
	_chip_mesh = BoxMesh.new()
	_chip_mesh.size = Vector3(0.05, 0.02, 0.09)
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.56, 0.37, 0.21)
	_wood.roughness = 1.0
	_char = StandardMaterial3D.new()
	_char.albedo_color = Color(0.12, 0.09, 0.08)
	_char.roughness = 1.0
	_ember = StandardMaterial3D.new()
	_ember.albedo_color = Color(1.0, 0.55, 0.16)
	_ember.emission_enabled = true
	_ember.emission = Color(1.0, 0.42, 0.08)
	_ember.emission_energy_multiplier = 3.0
