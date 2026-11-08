class_name Interactor
extends Node3D
## Player-side interaction: finds the Interactable in front, shows the prompt, sends requests. Owner: S10.
## Added under Player/Abilities for villagers and the mage (see RoleScenes). Root name "Interactor".
## NET: authority = owning peer reads `player.input.interact_pressed` / `drop_pressed` / `primary_pressed`
## (villager primary = throw carried thing) and RPCs the server, which validates and acts.
## Emits GameEvents.interact_prompt_changed on the local peer.
## Public API: `find_target() -> Interactable`.

const PROMPT_INTERVAL := 0.1
## Targets further than this must be roughly in front of the player.
const ANY_ANGLE_DISTANCE := 1.0
const MIN_FACING_DOT := 0.2

var _player: Player
var _prompt_left := 0.0
var _prompt := ""


func _ready() -> void:
	_player = get_parent().get_parent() as Player


func _exit_tree() -> void:
	if _prompt != "":
		GameEvents.interact_prompt_changed.emit("")


func _physics_process(delta: float) -> void:
	if _player == null or not _player.is_multiplayer_authority() or _manager() == null:
		return
	if _player.is_local():
		_prompt_left -= delta
		if _prompt_left <= 0.0:
			_prompt_left = PROMPT_INTERVAL
			_refresh_prompt()
	if not _player.can_control():
		return
	if _player.input.interact_pressed:
		var target := find_target()
		if target:
			_send(&"_rpc_interact", [target.get_path()])
	var carrying := _manager().carried_kind(_player.peer_id) != &""
	if carrying and _player.input.drop_pressed:
		_send(&"_rpc_release", [false, Vector3.ZERO])
	elif carrying and _player.input.primary_pressed:
		_send(&"_rpc_release", [true, -_player.camera_rig.global_basis.z])


## Best usable Interactable near this player, or null. Nearest wins, facing it breaks ties.
func find_target() -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var forward := -_player.global_basis.z
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var target := node as Interactable
		var to: Vector3 = target.global_position - _player.global_position
		var distance := to.length()
		if distance > target.max_distance or not target.can_interact(_player):
			continue
		var facing := forward.dot(Vector3(to.x, 0.0, to.z).normalized())
		if distance > ANY_ANGLE_DISTANCE and facing < MIN_FACING_DOT:
			continue
		var score := distance - facing * 0.5
		if score < best_score:
			best_score = score
			best = target
	return best


func _refresh_prompt() -> void:
	var parts: PackedStringArray = []
	if _player.can_control():
		var target := find_target()
		if target:
			parts.append("E · %s" % target.prompt_for(_player))
		if _manager().carried_kind(_player.peer_id) != &"":
			parts.append("G · Drop")
			parts.append("LMB · Throw")
	var text := "   ".join(parts)
	if text != _prompt:
		_prompt = text
		GameEvents.interact_prompt_changed.emit(text)


func _manager() -> InteractManager:
	return GameEvents.system(&"interact") as InteractManager


func _send(method: StringName, args: Array) -> void:
	if Net.is_server(self):
		callv(method, args)
	else:
		callv(&"rpc_id", [1, method] + args)


# NET: requests carry intent only; the manager validates distance, ownership and state.
@rpc("any_peer", "call_local", "reliable")
func _rpc_interact(path: NodePath) -> void:
	if _authorized():
		_manager().server_interact(_player, get_node_or_null(path) as Interactable)


@rpc("any_peer", "call_local", "reliable")
func _rpc_release(throw: bool, aim: Vector3) -> void:
	if _authorized():
		_manager().server_release(_player, throw, aim)


func _authorized() -> bool:
	return Net.is_server(self) and _manager() != null \
		and Net.sender_id(self) == _player.get_multiplayer_authority()
