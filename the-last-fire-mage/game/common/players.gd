class_name Players
extends RefCounted
## Static lookups for player nodes (group "players"). Owner: S02. Works on every peer.

## Local server-side bots (S07) get peer ids from here upward, so they never collide with real peer ids
## in practice and are easy to spot in logs. CONTRACT.
const BOT_ID_BASE := 1_000_000


## All player nodes (alive and dead).
static func all() -> Array[Node]:
	return _tree().get_nodes_in_group(&"players") if _tree() else []


## Player node for a peer id, or null.
static func get_player(peer_id: int) -> Node:
	for p in all():
		if p.peer_id == peer_id:
			return p
	return null


## The local human's player node, or null (bots never count).
static func local_player() -> Node:
	for p in all():
		if p.is_local():
			return p
	return null


## Living players with the given role (Enums.Role). Pass -1 for any role.
static func alive_with_role(role: int) -> Array[Node]:
	var out: Array[Node] = []
	for p in all():
		if p.is_alive and (role < 0 or p.role == role):
			out.append(p)
	return out


static func is_bot_id(peer_id: int) -> bool:
	return peer_id >= BOT_ID_BASE


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
