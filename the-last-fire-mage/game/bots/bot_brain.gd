class_name BotBrain
extends RefCounted
## Wandering input driver; assign to Player.input_driver. Owner: S07.
## NET: runs only on the player's authority, through fill_input(player, input, delta).

var _rng := RandomNumberGenerator.new()
var _turn_in := 0.0
var _action_in := 0.0
var _move := Vector2.ZERO
var _sprint := false
var _turn := 0.0


## Fill held intent and one-tick actions without moving the player directly.
func fill_input(_player: Node, input: PlayerInput, delta: float) -> void:
	input.clear()
	_turn_in -= delta
	_action_in -= delta
	if _turn_in <= 0.0:
		_turn_in = _rng.randf_range(0.6, 2.0)
		_move = Vector2.from_angle(_rng.randf_range(-PI, PI))
		_sprint = _rng.randf() < 0.5
		_turn = _rng.randf_range(-1.5, 1.5)
	input.move = _move
	input.sprint = _sprint
	input.look_delta = Vector2(_turn * delta, 0.0)
	if _action_in <= 0.0:
		_action_in = _rng.randf_range(0.5, 1.8)
		match _rng.randi_range(0, 2):
			0:
				input.jump = true
				input.jump_pressed = true
			1:
				input.interact_pressed = true
			2:
				input.primary = true
				input.primary_pressed = true
