class_name Enums
extends RefCounted
## Shared game enums. Owner: S02 (head engineer). Use as `Enums.Role.MAGE`, `Enums.Phase.HUNT`.
## CONTRACT: values are sent over the network as ints. Only append new values at the end.

## A player's role for the current round. Dead players keep their role (check `Player.is_alive`).
enum Role {
	NONE, ## not in a round yet (lobby)
	VILLAGER,
	MAGE,
	SPECTATOR, ## joined mid-round; watches until the next round
}

## Round phases, driven by MatchManager (S04) on the server.
enum Phase {
	LOBBY, ## waiting for the host to start
	ROLE_REVEAL, ## roles shown, nobody moves
	HEAD_START, ## villagers move, mage blinded + frozen
	HUNT, ## main round timer runs
	RESULTS, ## winner shown, then back to LOBBY
}

## Who won a round.
enum Winner { NONE, VILLAGERS, MAGE }


static func role_name(r: int) -> String:
	return ["None", "Villager", "Mage", "Spectator"][r] if r >= 0 and r < 4 else "?"


static func phase_name(p: int) -> String:
	return ["Lobby", "RoleReveal", "HeadStart", "Hunt", "Results"][p] if p >= 0 and p < 5 else "?"
