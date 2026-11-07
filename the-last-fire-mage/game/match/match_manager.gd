class_name MatchManager
extends Node
## Round flow: LOBBY -> ROLE_REVEAL -> HEAD_START -> HUNT -> RESULTS -> LOBBY. Owner: S04.
## Registered as GameEvents.system(&"match"). Instanced once in main.tscn at Systems/Match.
## NET: server runs the state machine; phase/roles reach clients via this node's RPCs (call_local, so the
## server's own GameEvents fire too) and a MultiplayerSynchronizer for `phase`/`time_left` (S04 adds it).
## Late joiners get role SPECTATOR and a state snapshot (S04).
## Public API: `phase`, `time_left`, `mage_id`, `roles`, `tuning`, `start_round(mage_id)`,
## `end_round(winner, reason)`, `get_role(peer_id)`, `is_round_active()`.
## Emits: GameEvents.phase_changed, role_assigned, round_ended. Calls Player.set_role() on every peer
## before emitting role_assigned.

## Current phase (Enums.Phase). Synced.
var phase: int = Enums.Phase.LOBBY
## Seconds left in the current timed phase. Synced (HUD shows it).
var time_left := 0.0
## Peer id of this round's mage (0 = none yet).
var mage_id := 0
## peer_id -> Enums.Role for the current round (same on all peers).
var roles: Dictionary = {}
var tuning: MatchTuning

func _enter_tree() -> void:
	GameEvents.register_system(&"match", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/match/tuning_match.tres", "match") as MatchTuning


## NET: server only. Starts a round. `mage_id` 0 = pick at random. Scoring (S16 party mode) and the
## host lobby UI call this.
func start_round(_mage_id: int = 0) -> void:
	pass # TODO(S04)


## NET: server only. Ends the round now (Enums.Winner + reason string, see GameEvents.round_ended).
func end_round(_winner: int, _reason: String) -> void:
	pass # TODO(S04)


## Role of a peer this round (Enums.Role.NONE if not in the round).
func get_role(peer_id: int) -> int:
	return roles.get(peer_id, Enums.Role.NONE)


## True during HEAD_START and HUNT.
func is_round_active() -> bool:
	return phase == Enums.Phase.HEAD_START or phase == Enums.Phase.HUNT
