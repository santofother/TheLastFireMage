class_name InteractManager
extends Node
## Server-side bookkeeping for interactions: who carries what, one carrier at a time, hide-spot contents and
## mage searches. Owner: S10. Registered as GameEvents.system(&"interact").
## NET: server only decides; results reach peers through the carried object's own synced state
## (e.g. Chicken.carrier_id), GameEvents.carry_changed and the `_rpc_spot` mirror.
## Public API: `carried_by(peer_id) -> Node`, `carrier_of(obj) -> int` (server); `carried_kind(peer_id)`,
## `may_carry(player)` (every peer); `server_*` are called by Interactor/HideSpot after an RPC.

## Log/test prefix: [Interact].
var tuning: InteractTuning

var _carry := {} # NET: server only. peer_id -> carried Node
var _kinds := {} # every peer. peer_id -> kind StringName
var _occupied: Array[HideSpot] = [] # NET: server only. Spots with something inside
var _searches := {} # NET: server only. HideSpot -> {"id": peer_id, "left": seconds}


func _enter_tree() -> void:
	GameEvents.register_system(&"interact", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/interact/tuning_interact.tres", "interact") as InteractTuning
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.session_ended.connect(_on_session_ended)
	GameEvents.player_died.connect(_on_player_died)


func _physics_process(delta: float) -> void:
	if not Net.is_server(self):
		return
	for id: int in _carry.keys():
		if _is_gone(_carry[id]):
			_end_carry(id)
	for spot in _occupied.duplicate():
		_purge_spot(spot)
	for spot: HideSpot in _searches.keys():
		_tick_search(spot, delta)


## What a player carries (null = nothing). Server only.
func carried_by(peer_id: int) -> Node:
	var obj: Node = _carry.get(peer_id)
	return obj if is_instance_valid(obj) else null


## Peer id carrying `obj` (0 = nobody). Server only.
func carrier_of(obj: Node) -> int:
	for id: int in _carry:
		if _carry[id] == obj:
			return id
	return 0


## Kind a player carries (&"" = nothing). NET: every peer.
func carried_kind(peer_id: int) -> StringName:
	return _kinds.get(peer_id, &"")


## May `player` pick something up? Villagers with free hands. NET: every peer.
func may_carry(player: Node) -> bool:
	return player.role == Enums.Role.VILLAGER and carried_kind(player.peer_id) == &""


## NET: server only. Validates and performs `player` using `target`.
func server_interact(player: Player, target: Interactable) -> void:
	if not Net.is_server(self) or target == null or not target.is_in_group(&"interactable"):
		return
	if not player.can_control():
		_reject(player, "cannot act")
		return
	if player.global_position.distance_to(target.global_position) > target.max_distance + tuning.range_slack:
		_reject(player, "too far from %s" % target.get_parent().name)
		return
	if not target.can_interact(player):
		_reject(player, "%s not usable" % target.get_parent().name)
		return
	var root := target.get_parent()
	if root.has_method(&"can_be_carried"):
		_begin_carry(player, root)
	target.interact(player)


## NET: server only. Drops (`throw` false) or throws what `player` carries.
func server_release(player: Player, throw: bool, aim: Vector3) -> void:
	if not Net.is_server(self) or carried_by(player.peer_id) == null:
		return
	if not player.can_control():
		_reject(player, "cannot act")
		return
	var impulse := Vector3.ZERO
	if throw:
		impulse = _clean_aim(player, aim) * tuning.throw_speed + Vector3.UP * tuning.throw_lift
	_drop(player.peer_id, _release_point(player), impulse)


## NET: server only, from HideSpot. Moves the carried object into `spot`. The spot already validated capacity.
func server_hide(player: Player, spot: HideSpot) -> void:
	var obj := carried_by(player.peer_id)
	if obj == null or not obj.has_method(&"on_hidden"):
		return
	_end_carry(player.peer_id)
	spot.store(obj)
	if spot not in _occupied:
		_occupied.append(spot)
	obj.call(&"on_hidden", spot)
	_sync_spot(spot)
	print("[Interact] %d hid %s in %s" % [player.peer_id, obj.name, spot.name])


## NET: server only, from HideSpot. Empty-handed villager takes an object out.
func server_take(player: Player, spot: HideSpot) -> void:
	var obj := spot.take_last()
	if obj == null:
		return
	_purge_spot(spot)
	obj.call(&"on_unhidden")
	_begin_carry(player, obj)
	_sync_spot(spot)
	print("[Interact] %d took %s from %s" % [player.peer_id, obj.name, spot.name])


## NET: server only, from HideSpot. Starts the mage's timed search; `_tick_search` finishes it.
func server_start_search(player: Player, spot: HideSpot) -> void:
	for active: Dictionary in _searches.values():
		if active.id == player.peer_id:
			return
	if _searches.has(spot):
		return
	_searches[spot] = {"id": player.peer_id, "left": spot.search_time}
	_sync_spot(spot)
	print("[Interact] %d searching %s" % [player.peer_id, spot.name])


func _begin_carry(player: Player, obj: Node) -> void:
	_carry[player.peer_id] = obj
	obj.call(&"on_picked_up", player)
	player.set_speed_modifier(&"carry", float(obj.call(&"carry_speed_multiplier")))
	var kind := _kind_of(obj)
	Net.broadcast(self, &"_rpc_carry", [player.peer_id, kind])
	print("[Interact] %d picked up %s" % [player.peer_id, obj.name])


## Removes the carry entry and slow; the object is handled by the caller.
func _end_carry(peer_id: int) -> void:
	_carry.erase(peer_id)
	var player := Players.get_player(peer_id)
	if player:
		player.set_speed_modifier(&"carry", 1.0)
	Net.broadcast(self, &"_rpc_carry", [peer_id, &""])


func _drop(peer_id: int, pos: Vector3, impulse: Vector3) -> void:
	var obj := carried_by(peer_id)
	_end_carry(peer_id)
	if obj:
		obj.call(&"on_dropped", pos, impulse)


func _is_gone(obj: Variant) -> bool:
	if not is_instance_valid(obj) or (obj as Node).is_queued_for_deletion():
		return true
	var health := (obj as Node).get_node_or_null(^"Health") as Health
	return health != null and not health.is_alive


func _kind_of(obj: Node) -> StringName:
	var area := obj.get_node_or_null(^"Interactable") as Interactable
	return area.kind if area and area.kind != &"" else &"item"


## Point just in front of the carrier's chest, pulled back if a wall is in the way.
func _release_point(player: Player) -> Vector3:
	var chest := player.global_position + Vector3.UP * player.tuning.height * 0.6
	var target := chest - player.global_basis.z * tuning.release_forward
	var query := PhysicsRayQueryParameters3D.create(chest, target, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return chest if hit else target


## WHY: pitch is not replicated, so the client's aim is used, but forged or backwards aims fall back to
## the body's forward. The server still picks the speed.
func _clean_aim(player: Player, aim: Vector3) -> Vector3:
	var forward := -player.global_basis.z
	if not aim.is_finite() or aim.length_squared() < 0.9 or aim.length_squared() > 1.1:
		return forward
	return aim.normalized() if aim.dot(forward) >= cos(deg_to_rad(80.0)) else forward


func _tick_search(spot: HideSpot, delta: float) -> void:
	var active: Dictionary = _searches[spot]
	var player := Players.get_player(active.id) as Player
	var area := spot.get_node(^"Interactable") as Interactable
	if player == null or not player.can_control() \
			or player.global_position.distance_to(area.global_position) > area.max_distance + tuning.range_slack:
		_searches.erase(spot)
		_sync_spot(spot)
		print("[Interact] search of %s cancelled" % spot.name)
		return
	active.left -= delta
	if active.left <= 0.0:
		_finish_search(spot, player)


func _finish_search(spot: HideSpot, mage: Player) -> void:
	_searches.erase(spot)
	var away := mage.global_position - spot.global_position
	away = Vector3(away.x, 0.0, away.z).normalized()
	var found := 0
	var obj := spot.take_last()
	while obj != null:
		if not _is_gone(obj):
			obj.call(&"on_unhidden")
			# WHY: toward the mage, because that side is known to be open (spots stand against walls).
			var dir := away.rotated(Vector3.UP, found * 0.7)
			obj.call(&"on_dropped", spot.global_position + dir * 0.9 + Vector3.UP * 0.5,
				Vector3.UP * tuning.search_pop_speed)
			found += 1
		obj = spot.take_last()
	_occupied.erase(spot)
	_sync_spot(spot)
	print("[Interact] search of %s found %d" % [spot.name, found])


func _purge_spot(spot: HideSpot) -> void:
	var changed := false
	for obj in spot._contents.duplicate():
		if _is_gone(obj):
			spot.forget(obj)
			changed = true
	if spot._contents.is_empty():
		_occupied.erase(spot)
	if changed:
		_sync_spot(spot)


func _sync_spot(spot: HideSpot) -> void:
	var searcher: int = _searches[spot].id if _searches.has(spot) else 0
	Net.broadcast(self, &"_rpc_spot", [spot.get_path(), spot.hidden_objects().size(), searcher])


func _reject(player: Player, why: String) -> void:
	print("[Interact] rejected %d: %s" % [player.peer_id, why])


func _on_player_died(peer_id: int, _killer: int, _cause: StringName) -> void: # every peer
	if Net.is_server(self) and _carry.has(peer_id):
		var player := Players.get_player(peer_id) as Node3D
		_drop(peer_id, player.global_position + Vector3.UP * 0.5, Vector3.ZERO)


func _on_peer_left(peer_id: int) -> void: # WHY: the player node may already be gone, so drop where it is.
	if Net.is_server(self) and _carry.has(peer_id):
		var obj := carried_by(peer_id) as Node3D
		_drop(peer_id, obj.global_position if obj else Vector3.ZERO, Vector3.ZERO)


func _on_player_registered(peer_id: int, _player_name: String) -> void: # NET: server only, late joiners
	if not Net.is_online(self) or peer_id == 1 or Players.is_bot_id(peer_id):
		return
	for id: int in _kinds:
		_rpc_carry.rpc_id(peer_id, id, _kinds[id])
	for spot: HideSpot in get_tree().get_nodes_in_group(&"hide_spot"):
		if spot.hidden_count > 0 or spot.searcher_id != 0:
			_rpc_spot.rpc_id(peer_id, spot.get_path(), spot.hidden_count, spot.searcher_id)


func _on_session_ended(_reason: String) -> void:
	_carry.clear()
	_kinds.clear()
	_occupied.clear()
	_searches.clear()
	for spot: HideSpot in get_tree().get_nodes_in_group(&"hide_spot"):
		spot._contents.clear()
		spot.hidden_count = 0
		spot.searcher_id = 0


# NET: server decided, every peer applies. The RPC body emits carry_changed so the server's listeners fire too.
@rpc("authority", "call_local", "reliable")
func _rpc_carry(peer_id: int, kind: StringName) -> void:
	if kind == &"":
		_kinds.erase(peer_id)
	else:
		_kinds[peer_id] = kind
	GameEvents.carry_changed.emit(peer_id, kind)


@rpc("authority", "call_local", "reliable")
func _rpc_spot(path: NodePath, count: int, searcher: int) -> void:
	var spot := get_node_or_null(path) as HideSpot
	if spot:
		spot.hidden_count = count
		spot.searcher_id = searcher
