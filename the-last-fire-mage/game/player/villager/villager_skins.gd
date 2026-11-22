class_name VillagerSkins
extends RefCounted
## List of selectable villager bodies and this machine's choice. Owner: villager picker.
## NET: local data. Each owner replicates its choice through `Player.villager_skin`.
##
## Public API:
## - `NAMES`: display names; the index is the skin id.
## - `local`: skin id chosen on this machine.
## - `scene(id)`, `clamp_id(id)`, `id_from_name(text)`.

# CONTRACT: ids go over the network, so only append new skins. Every scene must use the red villager's skeleton.

## Display names, indexed by skin id.
const NAMES: Array[String] = ["Red", "Blue", "Old Man", "Auntie"]
const _SCENES: Array[PackedScene] = [
	preload("res://game/player/villager/red-villager-animations.glb"),
	preload("res://game/player/villager/blue/blue-villager-mesh.glb"),
	preload("res://game/player/villager/elderly/elderly-villager.glb"),
	preload("res://game/player/villager/auntie/auntie-purple.glb"),
]

## Skin id chosen in this machine's menu.
static var local := 0


## Scene holding the skinned meshes for a skin id.
static func scene(id: int) -> PackedScene:
	return _SCENES[clamp_id(id)]


## Limits a skin id to a valid one. Ids can come from other peers.
static func clamp_id(id: int) -> int:
	return clampi(id, 0, NAMES.size() - 1)


## Skin id for a name such as "blue" or "old man" (also "old_man"), or 0 if the name is unknown.
static func id_from_name(text: String) -> int:
	for id: int in NAMES.size():
		if NAMES[id].to_lower() == text.to_lower().replace("_", " "):
			return id
	return 0
