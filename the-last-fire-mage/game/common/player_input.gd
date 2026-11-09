class_name PlayerInput
extends RefCounted
## One tick of player intent. Owner: S02. CONTRACT: the player and every ability read input ONLY from
## `player.input` (a PlayerInput), never from `Input` directly. Humans fill it from the InputMap
## (`fill_from_devices`), bots (S07) fill it themselves. That way bots drive exactly the human code path.
## Held fields stay true while held; `*_pressed` fields are true for one physics tick only.

## Movement stick, same convention as `Input.get_vector("move_left","move_right","move_forward","move_back")`:
## x = right, y = back (so forward is y < 0). Length <= 1.
var move := Vector2.ZERO
## Look change this tick in radians: x = yaw (right is positive), y = pitch (down is positive).
var look_delta := Vector2.ZERO
var jump := false
var sprint := false
var crouch := false
var primary := false
var jump_pressed := false
var interact_pressed := false
## E is currently down (hold-to-revive).
var interact_held := false
var drop_pressed := false
var primary_pressed := false
var ability_1_pressed := false
var ability_2_pressed := false
var ability_3_pressed := false


## Clears everything (used while input is locked or the menu is open).
func clear() -> void:
	move = Vector2.ZERO
	look_delta = Vector2.ZERO
	jump = false
	sprint = false
	crouch = false
	primary = false
	interact_held = false
	clear_edges()


## Clears the one-tick `*_pressed` fields and look_delta (called after each physics tick).
func clear_edges() -> void:
	look_delta = Vector2.ZERO
	jump_pressed = false
	interact_pressed = false
	drop_pressed = false
	primary_pressed = false
	ability_1_pressed = false
	ability_2_pressed = false
	ability_3_pressed = false


## Reads the InputMap actions (local human). Call once per physics tick. Mouse look is set separately
## by the player (it accumulates mouse motion between ticks).
func fill_from_devices() -> void:
	move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	jump = Input.is_action_pressed(&"jump")
	sprint = Input.is_action_pressed(&"sprint")
	crouch = Input.is_action_pressed(&"crouch")
	primary = Input.is_action_pressed(&"primary")
	jump_pressed = Input.is_action_just_pressed(&"jump")
	interact_pressed = Input.is_action_just_pressed(&"interact")
	interact_held = Input.is_action_pressed(&"interact")
	drop_pressed = Input.is_action_just_pressed(&"drop")
	primary_pressed = Input.is_action_just_pressed(&"primary")
	ability_1_pressed = Input.is_action_just_pressed(&"ability_1")
	ability_2_pressed = Input.is_action_just_pressed(&"ability_2")
	ability_3_pressed = Input.is_action_just_pressed(&"ability_3")
