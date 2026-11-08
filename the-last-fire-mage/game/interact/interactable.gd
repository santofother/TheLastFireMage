class_name Interactable
extends Area3D
## Marks something as interactable. Add as a child Area3D (collision layer 4 "interact", with a shape)
## named "Interactable" of the object. Owner: S10. Chickens, hide spots, S15 items and future doors use this.
## NET: `can_interact`/`prompt_for` run on every peer from synced state (client for the prompt, server to
## validate). `interact()` runs on the server after InteractManager validated it; it emits `interacted`
## there. The object's own script reacts (and replicates its state itself).
## Plugging in: a parent implementing Carryable (ARCHITECTURE §Interact) is carried automatically; anything
## else connects `interacted` (door: toggle). Optional: set `condition` and `prompt_provider` in the owner.

## Server only: a player used this.
signal interacted(player: Node)

## Prompt shown to the local player, e.g. "Pick up chicken" (the Interactor adds "E · ").
@export var prompt := "Use"
## What this is, e.g. &"chicken", &"hide_spot", &"item". Used for carry_changed and prompts.
@export var kind: StringName = &""
## Max use distance in metres (server checks it, plus `InteractTuning.range_slack`).
@export var max_distance := 2.0 # TUNE

## Seconds E must be held before `interacted` fires (0 = instant). Server counts it in Interactor.
@export var hold_time := 0.0

## Optional `func(player: Node) -> bool` replacing the default usability check.
var condition := Callable()
## Optional `func(player: Node) -> String` replacing `prompt`, for prompts that depend on who is looking.
var prompt_provider := Callable()


func _ready() -> void:
	add_to_group(&"interactable")


## Can `player` use this now? Hidden objects never can. NET: every peer.
func can_interact(player: Node) -> bool:
	if not is_visible_in_tree():
		return false
	if condition.is_valid():
		return bool(condition.call(player))
	var root := get_parent()
	if root.has_method(&"can_be_carried"):
		var manager := GameEvents.system(&"interact") as InteractManager
		return manager != null and manager.may_carry(player) and bool(root.call(&"can_be_carried"))
	return true


## The prompt text for `player`. NET: every peer.
func prompt_for(player: Node) -> String:
	return str(prompt_provider.call(player)) if prompt_provider.is_valid() else prompt


## NET: server only. Called by the interact system after validation.
func interact(player: Node) -> void:
	interacted.emit(player)
