class_name ScoringManager
extends Node
## Points per round + party mode (everyone is mage once). Owner: S16. Registered as
## GameEvents.system(&"scoring").
## NET: server counts from GameEvents (player_died, round_ended, phase_changed); fires score_changed /
## party_ended on all peers. In party mode it starts each round with MatchManager.start_round(mage_id).
## Public API: `party_active`, `get_total(peer_id)`, `start_party()`.

## True while a party (multi-round session) runs.
var party_active := false
## peer_id -> total points (synced through score_changed).
var totals: Dictionary = {}
var tuning: ScoringTuning

func _enter_tree() -> void:
	GameEvents.register_system(&"scoring", self)


func _ready() -> void:
	tuning = Tuning.load_tuning("res://game/scoring/tuning_scoring.tres", "scoring") as ScoringTuning


## Party total for a peer. Any peer.
func get_total(peer_id: int) -> int:
	return totals.get(peer_id, 0)


## NET: server only. Starts a party: one round per player, each player mage once.
func start_party() -> void:
	pass # TODO(S16)
