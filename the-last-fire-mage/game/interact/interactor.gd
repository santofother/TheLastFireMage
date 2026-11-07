class_name Interactor
extends Node3D
## Player-side interaction: finds the Interactable in front, shows the prompt, sends requests. Owner: S10.
## Added under Player/Abilities for villagers and the mage (see RoleScenes). Root name "Interactor".
## NET: authority = owning peer reads `player.input.interact_pressed` / `drop_pressed` / `primary_pressed`
## (villager primary = throw carried thing) and RPCs the server, which validates and acts.
## Emits GameEvents.interact_prompt_changed on the local peer.


func _physics_process(_delta: float) -> void:
	pass # TODO(S10)
