class_name BreakableManager
extends Node
## Decides which town furniture breaks and tells every peer. Owner: furnishing pass (S05 follow-up).
## System name `&"breakables"`, node `Systems/Breakables`.
## Public API: `report_impact(player, prop, momentum) -> bool` (owner peer), `burn_cone(...)` (server),
## `is_broken(prop)`, `broken_count()`.
## NET: server decides. Peers replay `_rpc_broken`; late joiners get `_rpc_snapshot`.

## CONTRACT: physics layer 9. Players collide with it; flame, camera and chickens do not.
const FURNITURE_MASK := 256

## TUNE: mass x speed into the surface needed to break a prop. Villager walk 4, sprint 6.5.
@export var break_momentum := 5.0
## TUNE: Largest gap the server accepts between a reporting player and the prop, metres.
@export var impact_reach := 2.75
## TUNE: Seconds a charging player's own client ignores the prop while the server answers.
@export var predict_seconds := 0.45

var _props: Array[BreakableProp] = []
var _index: Dictionary = {}
var _broken: Dictionary = {}


func _enter_tree() -> void:
	GameEvents.register_system(&"breakables", self)


func _ready() -> void:
	GameEvents.phase_changed.connect(_on_phase_changed)
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.session_ended.connect(func(_reason: String) -> void: _restore_all())


## NET: movement authority of `player`. Returns true when the hit is hard enough to break the prop.
func report_impact(player: Player, prop: BreakableProp, momentum: float) -> bool:
	if prop.broken or momentum < break_momentum:
		return false
	var index := _index_of(prop)
	if index < 0:
		return false
	if Net.is_server(self):
		_resolve_impact(player, index, momentum)
	else:
		prop.suspend_collision(predict_seconds)
		_rpc_impact.rpc_id(1, index, momentum)
	return true


## NET: server only. Splinters every wooden prop inside a flame cone with a clear path from `origin`.
func burn_cone(origin: Vector3, aim: Vector3, reach: float, angle_deg: float) -> void:
	if not Net.is_server(self):
		return
	_ensure_props()
	var sphere := SphereShape3D.new()
	sphere.radius = reach + 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = FURNITURE_MASK
	var space := get_viewport().find_world_3d().direct_space_state
	var limit := cos(deg_to_rad(angle_deg * 0.5))
	for hit in space.intersect_shape(query, 256):
		var prop := hit.collider as BreakableProp
		if prop == null or prop.broken:
			continue
		var point := prop.global_position + Vector3.UP * 0.25
		var offset := point - origin
		if offset.length() > reach or (offset.length() > 0.01 and aim.dot(offset.normalized()) < limit):
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, point, 1)
		if space.intersect_ray(ray).is_empty():
			_break(_index_of(prop), BreakableProp.Cause.FIRE)


## True when `prop` has splintered this round.
func is_broken(prop: BreakableProp) -> bool:
	return prop.broken


## How many props are splintered right now.
func broken_count() -> int:
	return _broken.size()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_impact(index: int, momentum: float) -> void:
	if not Net.is_server(self):
		return
	var player := Players.get_player(Net.sender_id(self)) as Player
	if player:
		_resolve_impact(player, index, momentum)


# NET: server only. Movement is client-authoritative, so cap what a client can claim.
func _resolve_impact(player: Player, index: int, momentum: float) -> void:
	_ensure_props()
	if index < 0 or index >= _props.size() or not player.is_alive:
		return
	var prop := _props[index]
	var limit := player.tuning.body_mass * (player.tuning.sprint_speed * 1.25 + 18.0)
	if momentum < break_momentum or momentum > limit:
		return
	if player.global_position.distance_to(prop.global_position) > impact_reach:
		return
	_break(index, BreakableProp.Cause.IMPACT)


func _break(index: int, cause: int) -> void:
	if index < 0 or _broken.has(index):
		return
	_broken[index] = cause
	print("[Props] %s splintered (%s)" % [_props[index].name, BreakableProp.Cause.keys()[cause]])
	Net.broadcast(self, &"_rpc_broken", [index, cause])


@rpc("any_peer", "call_local", "reliable")
func _rpc_broken(index: int, cause: int) -> void:
	if not Net.from_server(self):
		return
	_ensure_props()
	if index >= 0 and index < _props.size():
		_broken[index] = cause
		_props[index].shatter(cause, index, true)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_snapshot(broken: PackedInt32Array, causes: PackedInt32Array) -> void:
	if not Net.from_server(self):
		return
	_ensure_props()
	for i in broken.size():
		_broken[broken[i]] = causes[i]
		_props[broken[i]].shatter(causes[i], broken[i], false)


func _on_registered(id: int, _player_name: String) -> void:
	if not Net.is_server(self) or id == 1 or _broken.is_empty():
		return
	var causes := PackedInt32Array()
	var broken := PackedInt32Array(_broken.keys())
	for index in broken:
		causes.append(_broken[index])
	_rpc_snapshot.rpc_id(id, broken, causes)


func _on_phase_changed(phase: int, _duration: float) -> void:
	if phase == Enums.Phase.ROLE_REVEAL:
		_restore_all()


func _restore_all() -> void:
	for index: int in _broken:
		if index < _props.size() and is_instance_valid(_props[index]):
			_props[index].restore()
	_broken.clear()


func _index_of(prop: BreakableProp) -> int:
	_ensure_props()
	return int(_index.get(prop, -1))


# WHY: main._ready loads the map after its children (this system) are ready.
func _ensure_props() -> void:
	if not _props.is_empty() and is_instance_valid(_props[0]):
		return
	_props.clear()
	_index.clear()
	for node in get_tree().get_nodes_in_group(BreakableProp.GROUP):
		_props.append(node as BreakableProp)
	# CONTRACT: the saved town is identical on every peer, so sorted paths give shared indices.
	_props.sort_custom(func(a: BreakableProp, b: BreakableProp) -> bool:
		return String(a.get_path()) < String(b.get_path()))
	for i in _props.size():
		_index[_props[i]] = i
