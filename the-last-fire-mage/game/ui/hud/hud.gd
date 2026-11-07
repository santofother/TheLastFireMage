class_name Hud
extends CanvasLayer
## In-round UI. Owner: S08. Registered as GameEvents.system(&"hud").
## Driven only by GameEvents signals and synced values read through GameEvents.system(...) (e.g.
## `(GameEvents.system(&"match") as MatchManager).time_left`). Never changes game state.
## NET: runs on every peer, local only.

func _enter_tree() -> void:
	GameEvents.register_system(&"hud", self)


func _ready() -> void:
	pass # TODO(S08): build widgets, connect GameEvents
