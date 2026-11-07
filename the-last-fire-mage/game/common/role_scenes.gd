class_name RoleScenes
extends RefCounted
## Which ability scenes a player gets for each role. Owner: S02. CONTRACT.
## `Player.set_role()` instantiates these (in order) under the player's `Abilities` node on every peer,
## and gives them the player's multiplayer authority (the owning peer). Each scene's root node name must be
## unique among them, because RPC paths depend on it.

const BY_ROLE := {
	Enums.Role.NONE: [],
	Enums.Role.VILLAGER: ["res://game/interact/interactor.tscn"],
	Enums.Role.MAGE: ["res://game/mage/mage_abilities.tscn", "res://game/interact/interactor.tscn"],
	Enums.Role.SPECTATOR: [],
}


## Scene paths for a role (empty array if none).
static func for_role(role: int) -> Array:
	return BY_ROLE.get(role, [])
