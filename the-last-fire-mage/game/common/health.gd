class_name Health
extends Node
## Health component for anything that can be hurt (players, chickens). Owner: S02.
## Instance `res://game/common/health.tscn` as a child named "Health" (it brings its own synchronizer).
##
## NET: server only decides. `apply_damage` / `kill` / `revive` do nothing on clients. The result reaches
## every peer through `_rpc_event` (reliable) and the child `Sync` (hp/is_alive, also for late joiners).
## CONTRACT: this node and its children always have multiplayer authority 1 (server), even inside a
## client-owned player. It resets that itself in `_enter_tree`, after the parent set its own authority.
##
## Local signals fire on ALL peers. The owner (Player, Chicken) re-emits them on GameEvents.

## Took damage (hp already lowered). Fires on all peers.
signal damaged(amount: float, source_id: int, cause: StringName)
## Reached 0 hp. Fires on all peers.
signal died(killer_id: int, cause: StringName)
## Back alive with full hp. Fires on all peers.
signal revived
## hp changed for any reason (damage, heal, revive, sync). Fires on all peers.
signal hp_changed(hp: float)

## Max hp; set by the owner from its tuning before the first damage.
@export var max_hp := 100.0
## Current hp (synced).
@export var hp := 100.0:
	set(v):
		if hp != v:
			hp = v
			hp_changed.emit(hp)
## False after death until `revive()` (synced).
@export var is_alive := true
## Server-side switch: when true, damage is ignored (e.g. lobby). Not synced.
var invulnerable := false


func _enter_tree() -> void:
	set_multiplayer_authority(1, true)


## NET: server only. Lowers hp; kills at 0. `source_id` = attacker peer id (0 = environment).
func apply_damage(amount: float, source_id: int, cause: StringName) -> void:
	if not Net.is_server(self) or not is_alive or invulnerable or amount <= 0.0:
		return
	var new_hp := maxf(0.0, hp - amount)
	_broadcast(new_hp, amount, source_id, cause, new_hp <= 0.0)


## NET: server only. Kills instantly regardless of hp or invulnerability (firestorm, test hooks).
func kill(source_id: int, cause: StringName) -> void:
	if not Net.is_server(self) or not is_alive:
		return
	_broadcast(0.0, hp, source_id, cause, true)


## NET: server only. Restores hp (does not revive the dead).
func heal(amount: float) -> void:
	if Net.is_server(self) and is_alive:
		_broadcast(minf(max_hp, hp + amount), 0.0, 0, &"heal", false)


## NET: server only. Full hp and alive again (round reset).
func revive() -> void:
	if not Net.is_server(self):
		return
	Net.broadcast(self, &"_rpc_revive")


## Walks up from `node` (e.g. a collider hit by a raycast) and returns the first Health found, or null.
static func find_on(node: Node) -> Health:
	while node != null:
		var h := node.get_node_or_null(^"Health") as Health
		if h:
			return h
		if node is Health:
			return node
		node = node.get_parent()
	return null


func _broadcast(new_hp: float, amount: float, source_id: int, cause: StringName, dead: bool) -> void:
	Net.broadcast(self, &"_rpc_event", [new_hp, amount, source_id, cause, dead])


@rpc("authority", "call_local", "reliable")
func _rpc_event(new_hp: float, amount: float, source_id: int, cause: StringName, dead: bool) -> void:
	hp = new_hp
	if amount > 0.0:
		damaged.emit(amount, source_id, cause)
	if dead and is_alive:
		is_alive = false
		died.emit(source_id, cause)


@rpc("authority", "call_local", "reliable")
func _rpc_revive() -> void:
	hp = max_hp
	if not is_alive:
		is_alive = true
		revived.emit()
