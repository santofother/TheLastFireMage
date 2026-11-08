class_name TippableCart
extends Node3D
## Reusable map piece: a cart a villager can tip over onto the mage. Owner: S15.
## Place `tippable_cart.tscn` on the map. Interact (E) tips it away from the player; the mage standing
## within `tuning.cart_reach` in the fall direction is stunned (through CounterplayManager, source = tipper).
## The tipped cart stays as an obstacle until the next round (`ROLE_REVEAL`).
## NET: server decides on `interacted`, every peer plays the fall via `_rpc_tip` (same node path everywhere).

var tipped := false
var _fall_dir := Vector3.ZERO


func _ready() -> void:
	($Interactable as Interactable).interacted.connect(_on_interacted)
	($Interactable as Interactable).condition = func(_p: Node) -> bool: return not tipped
	GameEvents.phase_changed.connect(func(phase: int, _old: int) -> void:
		if phase == Enums.Phase.ROLE_REVEAL and Net.is_server(self):
			Net.broadcast(self, &"_rpc_reset"))


func _on_interacted(player: Node) -> void: # NET: server only
	if tipped:
		return
	var away: Vector3 = global_position - (player as Node3D).global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else global_basis.x
	var manager := GameEvents.system(&"counterplay") as CounterplayManager
	if manager:
		var reach := manager.tuning.cart_reach
		for m in Players.alive_with_role(Enums.Role.MAGE):
			var to_m: Vector3 = m.global_position - global_position
			to_m.y = 0.0
			if to_m.length() <= reach and to_m.normalized().dot(away) > 0.5:
				manager.request_stun(m, manager.tuning.cart_stun, player.peer_id)
	print("[Counterplay] %s tipped by %d" % [name, player.peer_id])
	Net.broadcast(self, &"_rpc_tip", [away])


@rpc("authority", "call_local", "reliable")
func _rpc_tip(dir: Vector3) -> void:
	tipped = true
	_fall_dir = dir
	var axis := Vector3.UP.cross(dir).normalized()
	var tween := create_tween()
	tween.tween_property($Body, "basis", Basis(axis, deg_to_rad(80.0)), 0.5).set_trans(Tween.TRANS_BOUNCE)


@rpc("authority", "call_local", "reliable")
func _rpc_reset() -> void:
	tipped = false
	$Body.basis = Basis.IDENTITY
