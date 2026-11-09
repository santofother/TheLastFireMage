class_name CounterplayManager
extends Node3D
## Villager tools to briefly stop the mage: throwable items at `item_spawn`, environment pieces. Owner: S15.
## Registered as GameEvents.system(&"counterplay").
## NET: server validates hits and applies effects through Player.stun / set_speed_modifier.
## Items (CounterItem) are spawned into `$Items` by `$ItemSpawner` at nodes in group `item_spawn`, and at
## nodes in group `dead_item_spawn` (the dead players' overhead area; those items break on the ground with
## `tuning.dead_break_chance`). A taken/broken item is replaced after `tuning.item_respawn_time`.
## Public API: `request_stun(target, seconds, source_id)`, `request_slow(target, mult, seconds)`,
## `spawn_item(kind, pos, break_chance)`, `apply_item_hit(item, mage)`, `clear_items()`, `tuning`,
## ghost side (any peer, local player only): `ghost_nearest_item(focus)`, `ghost_pickup(item, focus)`,
## `ghost_throw(focus, aim)`, `ghost_held_kind`.
## Environment scenes (place on the map): `tippable_cart.tscn`, `laundry_line.tscn`.

const ITEM_SCENE := preload("res://game/counterplay/counter_item.tscn")
const KINDS: Array[StringName] = [&"bucket", &"pot", &"net"]

var tuning: CounterplayTuning
var _next_id := 1
var _generation := 0 # bumped by clear_items so old items don't schedule respawns
var _last_stun_by_source := {} # NET: server. source_id -> msec of its last stun
var _stun_log := {} # NET: server. target peer_id -> Array[float] msec of recent stuns
var _slow_ends := {} # NET: server. target peer_id -> msec when the net slow ends
var _respawn: Array[Dictionary] = [] # NET: server. {"at": msec, "marker": Node3D, "dead": bool}
var _ghost_held := {} # NET: server. peer_id -> CounterItem
var _ghost_throw_ms := {} # NET: server. peer_id -> msec of the last throw
var _dead_spots_built := false # NET: server

## Kind of item the local ghost holds (&"" = none). Updated by the server.
var ghost_held_kind: StringName = &""

@onready var items_root: Node3D = $Items
@onready var spawner: MultiplayerSpawner = $ItemSpawner


func _enter_tree() -> void:
	GameEvents.register_system(&"counterplay", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/counterplay/tuning_counterplay.tres", "counterplay") as CounterplayTuning
	spawner.spawn_function = _spawn_item
	GameEvents.phase_changed.connect(_on_phase_changed)
	NetworkManager.session_ended.connect(func(_r: String) -> void: clear_items())
	NetworkManager.hosting_started.connect(func() -> void: _spawn_all.call_deferred())


func _physics_process(_delta: float) -> void:
	if not Net.is_server(self):
		return
	var now := Time.get_ticks_msec()
	for id: int in _slow_ends.keys():
		if now >= _slow_ends[id]:
			_slow_ends.erase(id)
			var p := Players.get_player(id)
			if p:
				p.set_speed_modifier(&"net", 1.0)
	for entry in _respawn.duplicate():
		if now >= entry["at"]:
			_respawn.erase(entry)
			if is_instance_valid(entry["marker"]):
				_spawn_at_marker(entry["marker"], entry["dead"])


## NET: server only. Stuns `target` (a Player) with diminishing returns. Returns the seconds applied (0 when
## the source is on cooldown). `source_id` 0 = environment (no cooldown).
func request_stun(target: Node, seconds: float, source_id: int) -> float:
	if not Net.is_server(self) or target == null or not target.has_method(&"stun") or seconds <= 0.0:
		return 0.0
	var now := Time.get_ticks_msec()
	if source_id != 0 and _last_stun_by_source.has(source_id) \
			and now - int(_last_stun_by_source[source_id]) < int(tuning.stun_cooldown * 1000.0):
		print("[Counterplay] stun from %d on cooldown" % source_id)
		return 0.0
	var log: Array = _stun_log.get(target.peer_id, [])
	log = log.filter(func(t: int) -> bool: return now - t < int(tuning.dr_window * 1000.0))
	var applied := seconds * pow(tuning.dr_factor, log.size())
	log.append(now)
	_stun_log[target.peer_id] = log
	if source_id != 0:
		_last_stun_by_source[source_id] = now
	target.stun(applied)
	print("[Counterplay] stunned %d for %.2fs (from %d, repeats %d)" % [target.peer_id, applied, source_id, log.size() - 1])
	return applied


## NET: server only. Slows `target` to `mult` for `seconds` (refreshing, not stacking).
func request_slow(target: Node, mult: float, seconds: float) -> void:
	if not Net.is_server(self) or target == null:
		return
	target.set_speed_modifier(&"net", mult)
	_slow_ends[target.peer_id] = Time.get_ticks_msec() + int(seconds * 1000.0)
	print("[Counterplay] slowed %d to %.2f for %.1fs" % [target.peer_id, mult, seconds])


## NET: server only. Applies the effect of `item` hitting `mage`.
func apply_item_hit(item: CounterItem, mage: Node) -> void:
	match item.kind:
		&"bucket":
			request_stun(mage, tuning.stun_duration, item.thrower_id)
			var abilities := mage.get_ability(&"MageAbilities") as Node
			if abilities and abilities.has_method(&"extinguish"):
				abilities.call(&"extinguish")
		&"pot":
			request_stun(mage, tuning.pot_stun, item.thrower_id)
		&"net":
			request_slow(mage, tuning.net_slow, tuning.net_slow_time)


## NET: server only. Spawns one item. Returns the node.
func spawn_item(kind: StringName, pos: Vector3, break_chance := 0.0) -> Node:
	if not Net.is_server(self):
		return null
	var item := spawner.spawn({"name": "Item%d" % _next_id, "pos": pos, "kind": kind, "break": break_chance})
	_next_id += 1
	return item


## NET: server only. Removes all items (round reset).
func clear_items() -> void:
	for c in items_root.get_children():
		c.queue_free()
	_respawn.clear()
	_generation += 1
	_ghost_held.clear()
	ghost_held_kind = &""
	if Net.is_online(self) and multiplayer.is_server():
		_rpc_ghost_reset.rpc()


func _spawn_all() -> void:
	if not Net.is_server(self):
		return
	for m in get_tree().get_nodes_in_group(&"item_spawn"):
		_spawn_at_marker(m, false)
	_build_dead_spots()
	for m in get_tree().get_nodes_in_group(&"dead_item_spawn"):
		_spawn_at_marker(m, true)


func _spawn_at_marker(marker: Node3D, dead: bool) -> void:
	var item := spawn_item(KINDS[randi() % KINDS.size()], marker.global_position + Vector3.UP * 0.1,
		tuning.dead_break_chance if dead else 0.0) as CounterItem
	if item == null:
		return
	var gen := _generation
	# Replace it after it is gone (taken items are re-spawned too: they are single use).
	item.tree_exited.connect(func() -> void:
		if is_inside_tree() and Net.is_server(self) and gen == _generation:
			_respawn.append({"at": Time.get_ticks_msec() + int(tuning.item_respawn_time * 1000.0),
				"marker": marker, "dead": dead}))


# WHY: the layer is a flat plane, so spots come from the town's extent instead of hand-placed map markers.
func _build_dead_spots() -> void:
	if _dead_spots_built:
		return
	var spots := get_tree().get_nodes_in_group(&"villager_spawn") + get_tree().get_nodes_in_group(&"item_spawn")
	if spots.is_empty():
		return
	_dead_spots_built = true
	var low := Vector2(INF, INF)
	var high := -low
	for s: Node3D in spots:
		var p := Vector2(s.global_position.x, s.global_position.z)
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	var spectator := GameEvents.system(&"spectator") as SpectatorManager
	var y := spectator.tuning.camera_height if spectator else 30.0
	for i in tuning.dead_item_count:
		var marker := Marker3D.new()
		add_child(marker)
		marker.global_position = Vector3(randf_range(low.x - 5.0, high.x + 5.0), y + 0.05, randf_range(low.y - 5.0, high.y + 5.0))
		marker.add_to_group(&"dead_item_spawn")


# ------------------------------------------------------------------ dead players' items

## Closest item the local ghost can grab from `focus`, or null.
func ghost_nearest_item(focus: Vector3) -> CounterItem:
	var best: CounterItem = null
	var best_distance := tuning.dead_pickup_range
	for c in items_root.get_children():
		var item := c as CounterItem
		if item == null or not item.in_dead_layer():
			continue
		var d := Vector2(item.global_position.x - focus.x, item.global_position.z - focus.z).length()
		if d <= best_distance:
			best = item
			best_distance = d
	return best


## Local ghost asks to grab `item`. The server validates.
func ghost_pickup(item: CounterItem, focus: Vector3) -> void:
	if Net.is_server(self):
		_rpc_ghost_pickup(item.name, focus)
	else:
		_rpc_ghost_pickup.rpc_id(1, item.name, focus)


## Local ghost asks to throw its held item along `aim`. The server validates.
func ghost_throw(focus: Vector3, aim: Vector3) -> void:
	if Net.is_server(self):
		_rpc_ghost_throw(focus, aim)
	else:
		_rpc_ghost_throw.rpc_id(1, focus, aim)


func _is_ghost(peer_id: int) -> bool:
	var p := Players.get_player(peer_id)
	return p != null and (not p.is_alive or p.role == Enums.Role.SPECTATOR)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ghost_pickup(item_name: StringName, focus: Vector3) -> void:
	# NET: server. The ghost's position is local-only, so `focus` is client-claimed; only the role is validated.
	var id := Net.sender_id(self)
	var item := items_root.get_node_or_null(NodePath(item_name)) as CounterItem
	if not Net.is_server(self) or not _is_ghost(id) or _ghost_held.has(id) or item == null or not item.in_dead_layer():
		return
	if Vector2(item.global_position.x - focus.x, item.global_position.z - focus.z).length() > tuning.dead_pickup_range + 1.0:
		return
	item.take_by_ghost(id)
	_ghost_held[id] = item
	_send_ghost_held(id, item.kind)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ghost_throw(focus: Vector3, aim: Vector3) -> void:
	var id := Net.sender_id(self)
	if not Net.is_server(self) or not _is_ghost(id) or not _ghost_held.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_ghost_throw_ms.get(id, -100000)) < int(tuning.dead_throw_cooldown * 1000.0):
		return
	var item := _ghost_held[id] as CounterItem
	_ghost_held.erase(id)
	_send_ghost_held(id, &"")
	if not is_instance_valid(item) or not aim.is_finite() or aim.is_zero_approx():
		return
	_ghost_throw_ms[id] = now
	var direction := aim.normalized()
	direction.y = minf(direction.y, -0.35) # A throw always goes down through the glass.
	item.throw_by_ghost(focus + Vector3.DOWN * 0.5, direction.normalized() * tuning.dead_throw_speed)
	print("[Counterplay] ghost %d threw %s" % [id, item.kind])


func _send_ghost_held(id: int, kind: StringName) -> void:
	if not Net.is_online(self) or id == multiplayer.get_unique_id():
		ghost_held_kind = kind
	else:
		_rpc_ghost_held.rpc_id(id, kind)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ghost_held(kind: StringName) -> void:
	if Net.from_server(self):
		ghost_held_kind = kind


@rpc("any_peer", "call_local", "reliable")
func _rpc_ghost_reset() -> void:
	if Net.from_server(self):
		ghost_held_kind = &""


func _spawn_item(data: Dictionary) -> Node: # every peer (spawner)
	var item := ITEM_SCENE.instantiate() as CounterItem
	item.name = data["name"]
	item.kind = data["kind"]
	item.break_chance = data["break"]
	item.position = data["pos"]
	return item


func _on_phase_changed(phase: int, _old: int) -> void: # every peer
	if phase == Enums.Phase.ROLE_REVEAL and Net.is_server(self):
		clear_items()
		_spawn_all()
