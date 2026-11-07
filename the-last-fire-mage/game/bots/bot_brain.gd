class_name BotBrain
extends RefCounted
## Bot "player" that fills PlayerInput like a human would. Owner: S07.
## CONTRACT: assign as `player.input_driver`; the player calls `fill_input` every physics tick on its
## authority peer.


## Fill `input` for this tick (held fields + one-tick *_pressed fields). Called by Player.
func fill_input(_player: Node, input: PlayerInput, _delta: float) -> void:
	input.move = Vector2.ZERO # TODO(S07): wander / jump / sprint / interact / primary
