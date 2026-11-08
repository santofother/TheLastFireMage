class_name HideSpot
extends Node3D
## A place to hide carried chickens (crate/barrel/shed). Owner: S10. The map (S05) instances
## `hide_spot.tscn` wherever it wants one; group `hide_spot`.
## Use (E): villager carrying → hides it; villager empty-handed → takes one out; mage → timed search that
## kicks every chicken out (handled by InteractManager).
## NET: server decides contents; hidden objects sync their own `is_hidden`, and the manager mirrors
## `hidden_count` / `searcher_id` to every peer.
## Public API: `capacity`, `search_time`, `accepted_kinds`, `hidden_count`, `searcher_id`, `hidden_objects()`.

## How many chickens fit.
@export var capacity := 2 # TUNE
## Seconds the mage needs to search it.
@export var search_time := 2.0 # TUNE
## Carried kinds that fit in here.
@export var accepted_kinds: Array[StringName] = [&"chicken"]

## How many objects are inside. Every peer.
var hidden_count := 0
## Peer id searching this right now, 0 = nobody. Every peer.
var searcher_id := 0

var _contents: Array[Node] = [] # NET: server only


func _ready() -> void:
	var area := $Interactable as Interactable
	area.condition = _can_use
	area.prompt_provider = _prompt_for
	area.interacted.connect(_on_interacted)


## Objects hidden here (server).
func hidden_objects() -> Array[Node]:
	return _contents.filter(func(o: Node) -> bool: return is_instance_valid(o))


## NET: server only, InteractManager. Bookkeeping for one object going in.
func store(obj: Node) -> void:
	_contents.append(obj)


## NET: server only, InteractManager. Removes and returns the newest object, or null.
func take_last() -> Node:
	return _contents.pop_back() if not _contents.is_empty() else null


## NET: server only, InteractManager. Removes `obj` (it left the game). No-op if it isn't here.
func forget(obj: Node) -> void:
	_contents.erase(obj)


func _can_use(player: Node) -> bool:
	var manager := GameEvents.system(&"interact") as InteractManager
	if manager == null:
		return false
	if player.role == Enums.Role.MAGE:
		return searcher_id == 0 or searcher_id == player.peer_id
	var carried := manager.carried_kind(player.peer_id)
	if carried != &"":
		return carried in accepted_kinds and hidden_count < capacity
	return hidden_count > 0


func _prompt_for(player: Node) -> String:
	var manager := GameEvents.system(&"interact") as InteractManager
	if player.role == Enums.Role.MAGE:
		return "Searching…" if searcher_id == player.peer_id else "Search"
	if manager != null and manager.carried_kind(player.peer_id) != &"":
		return "Hide chicken"
	return "Take chicken"


func _on_interacted(player: Node) -> void: # NET: server only
	var manager := GameEvents.system(&"interact") as InteractManager
	if player.role == Enums.Role.MAGE:
		manager.server_start_search(player, self)
	elif manager.carried_by(player.peer_id) != null:
		manager.server_hide(player, self)
	else:
		manager.server_take(player, self)
