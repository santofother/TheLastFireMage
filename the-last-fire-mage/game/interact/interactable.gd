class_name Interactable
extends Area3D
## Marks something as interactable. Add as a child Area3D (collision layer 4 "interact", with a shape)
## of the object. Owner: S10. Chickens, hide spots, S15 items and future doors use this.
## NET: `interact()` runs on the server after S10 validated distance/ownership; it emits `interacted`
## there. The object's own script reacts (and replicates its state itself).

## Server only: a player used this.
signal interacted(player: Node)

## Prompt shown to the local player, e.g. "pick up chicken" (HUD shows "E: <prompt>").
@export var prompt := "use"
## What this is, e.g. &"chicken", &"hide_spot", &"item". Used for carry_changed and prompts.
@export var kind: StringName = &""
## Max use distance in metres (server checks it).
@export var max_distance := 2.0 # TUNE


func _ready() -> void:
	add_to_group(&"interactable")


## Can `player` use this now? Override in the owner by connecting your own check (S10 decides details).
func can_interact(_player: Node) -> bool:
	return true


## NET: server only. Called by the interact system after validation.
func interact(player: Node) -> void:
	interacted.emit(player)
