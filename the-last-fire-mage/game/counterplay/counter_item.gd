class_name CounterItem
extends Node3D
## A throwable villager tool (bucket, clay pot, fishing net). Owner: S15.
## Implements the CARRYABLE interface of the interact system (ARCHITECTURE §Interact), so pick up / drop /
## throw come from S10. Kinds: &"bucket" (stun + puts out Ignite), &"pot" (short stagger), &"net" (slow).
## NET: server simulates (authority 1); clients show synced state ($Sync: position, state, carrier_id).
## Spawned by CounterplayManager's MultiplayerSpawner (data: name, pos, kind, break_chance).
## Flight (server): ballistic, swept against the mage (-> manager applies the effect, item breaks) and the
## world. On world impact it breaks with probability `break_chance` (dead-area items 0.9), else stays. A dead
## player's item that touches a living villager is caught: it drops straight down and cannot break.
## Public API: `kind`, `state`, `carrier_id`, `break_chance`, `thrower_id`, signals `hit_mage`, `broke`.

enum State { IDLE, CARRIED, AIR }

## Server: the item hit the mage (before the effect is applied).
signal hit_mage(mage: Node)
## Server: the item broke (hit or ground impact).
signal broke

const GRAVITY := 9.8
const KILL_Y := -20.0
## Items above this height are on the dead players' layer and only ghosts can see them.
const DEAD_LAYER_MIN_Y := 25.0

## Item type, set at spawn on every peer.
var kind: StringName = &"bucket"
var state := State.IDLE
var carrier_id := 0
## Chance to break when it lands on the ground (server). 0 for normal item_spawn items.
var break_chance := 0.0
## Peer id of whoever threw it last (stun cooldown source).
var thrower_id := 0
var velocity := Vector3.ZERO
var home := Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group(&"counter_items")
	if home == Vector3.ZERO:
		home = global_position
	var area := $Interactable as Interactable
	area.kind = kind
	area.prompt = "Pick up %s" % kind
	_apply_look()


func _process(_delta: float) -> void:
	var held_by_ghost := state == State.CARRIED and carrier_id == 0
	var spectator := GameEvents.system(&"spectator") as SpectatorManager
	var ghost_view := spectator != null and spectator.is_spectating
	_mesh.visible = not held_by_ghost and (not in_dead_layer() or ghost_view)


## True while resting on the dead players' layer (a ghost may pick it up).
func in_dead_layer() -> bool:
	return state == State.IDLE and global_position.y >= DEAD_LAYER_MIN_Y


## NET: server only. A ghost picked this up; it is hidden until thrown.
func take_by_ghost(ghost_id: int) -> void:
	thrower_id = ghost_id
	state = State.CARRIED


## NET: server only. Launches a ghost's held item from the glass layer.
func throw_by_ghost(from: Vector3, impulse: Vector3) -> void:
	global_position = from
	velocity = impulse
	state = State.AIR


func _physics_process(delta: float) -> void:
	if carrier_id != 0 and state == State.CARRIED:
		var carrier := Players.get_player(carrier_id) as Node3D
		if carrier:
			var socket := carrier.get(&"carry_socket") as Node3D
			global_transform = socket.global_transform if socket else carrier.global_transform
		return
	if state != State.AIR or not Net.is_server(self):
		return
	_fly(delta)


func _fly(delta: float) -> void: # NET: server only
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var mage := _mage_hit(from, to)
	if mage != null:
		global_position = to
		hit_mage.emit(mage)
		var manager := GameEvents.system(&"counterplay") as CounterplayManager
		if manager:
			manager.apply_item_hit(self, mage)
		_break("hit mage")
		return
	if break_chance > 0.0 and _villager_hit(from, to):
		print("[Counterplay] %s %s caught by a living villager" % [kind, name])
		break_chance = 0.0
		velocity = Vector3.ZERO
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		global_position = hit.position + Vector3.UP * 0.05
		velocity = Vector3.ZERO
		state = State.IDLE
		if randf() < break_chance:
			_break("hit the ground")
			return
		break_chance = 0.0 # WHY: it landed intact, so living villagers can use it like any other item.
		return
	global_position = to
	if to.y < KILL_Y:
		global_position = home
		velocity = Vector3.ZERO
		state = State.IDLE


func _villager_hit(from: Vector3, to: Vector3) -> bool:
	for v in Players.alive_with_role(Enums.Role.VILLAGER):
		var base: Vector3 = v.global_position
		var height: float = v.tuning.height if v.tuning else 1.0
		for t in [0.0, 0.5, 1.0]:
			var p := from.lerp(to, t)
			if p.y >= base.y - 0.1 and p.y <= base.y + height \
					and Vector2(p.x - base.x, p.z - base.z).length() <= 0.6:
				return true
	return false


## First living mage whose body the segment passes through (cylinder around the player's axis).
func _mage_hit(from: Vector3, to: Vector3) -> Node:
	var manager := GameEvents.system(&"counterplay") as CounterplayManager
	var radius := (manager.tuning.hit_radius if manager else 0.45) + 0.3
	for m in Players.alive_with_role(Enums.Role.MAGE):
		var base: Vector3 = m.global_position
		var height: float = m.tuning.height if m.tuning else 1.8
		for t in [0.0, 0.5, 1.0]:
			var p := from.lerp(to, t)
			if p.y >= base.y - 0.1 and p.y <= base.y + height \
					and Vector2(p.x - base.x, p.z - base.z).length() <= radius:
				return m
	return null


func _break(why: String) -> void: # NET: server only
	print("[Counterplay] %s %s broke (%s)" % [kind, name, why])
	broke.emit()
	state = State.IDLE
	queue_free()


func _apply_look() -> void:
	var mat := StandardMaterial3D.new()
	match kind:
		&"bucket":
			mat.albedo_color = Color(0.35, 0.55, 0.85)
		&"pot":
			mat.albedo_color = Color(0.75, 0.4, 0.25)
		_:
			mat.albedo_color = Color(0.8, 0.75, 0.55)
	_mesh.material_override = mat
	if kind == &"net":
		_mesh.scale = Vector3(1.6, 0.4, 1.6)


# ------------------------------------------------------------------ Carryable (S10 calls on the server)

## Carryable: free items on the ground can be picked up.
func can_be_carried() -> bool:
	return carrier_id == 0 and state != State.AIR


## Carryable: carrier speed multiplier.
func carry_speed_multiplier() -> float:
	var manager := GameEvents.system(&"counterplay") as CounterplayManager
	return manager.tuning.carry_speed_mult if manager else 0.9


## Carryable, NET: server only.
func on_picked_up(carrier: Node3D) -> void:
	carrier_id = int(carrier.get(&"peer_id"))
	thrower_id = carrier_id
	state = State.CARRIED
	velocity = Vector3.ZERO


## Carryable, NET: server only. `impulse` = throw velocity (zero = plain drop, which falls but never breaks).
func on_dropped(pos: Vector3, impulse: Vector3) -> void:
	carrier_id = 0
	global_position = pos
	velocity = impulse
	state = State.AIR


## Carryable: items can't be hidden.
func on_hidden(_spot: Node3D) -> void:
	on_dropped(global_position, Vector3.ZERO)


## Carryable.
func on_unhidden() -> void:
	state = State.IDLE
