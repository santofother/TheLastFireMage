class_name Net
extends RefCounted
## Small networking helpers shared by all game systems. Owner: S02.


## True on the server, and also when offline (so single-process tests and menus don't break).
static func is_server(node: Node) -> bool:
	return not node.multiplayer.has_multiplayer_peer() or node.multiplayer.is_server()


## Peer id that sent the RPC currently running. For a `call_local` RPC run on the caller itself this
## returns the local id (Godot may report 0 there).
static func sender_id(node: Node) -> int:
	var id := node.multiplayer.get_remote_sender_id()
	return id if id != 0 else node.multiplayer.get_unique_id()


## True if the RPC currently running came from the server (use in any_peer RPCs the server sends).
static func from_server(node: Node) -> bool:
	return sender_id(node) == 1


## True when a real session is connected (RPCs can be sent). False offline / after leaving.
static func is_online(node: Node) -> bool:
	var mp := node.multiplayer
	return mp.has_multiplayer_peer() and mp.multiplayer_peer.get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED


## Calls `method` with `args` as an RPC to everyone (needs `call_local` on the RPC) when online,
## or as a plain local call when offline. Use from the server for "server decided, tell everyone".
static func broadcast(node: Node, method: StringName, args: Array = []) -> void:
	if is_online(node):
		node.callv(&"rpc", [method] + args)
	else:
		node.callv(method, args)
