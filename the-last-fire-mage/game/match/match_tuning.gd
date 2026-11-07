class_name MatchTuning
extends Tuning
## Match durations and lobby minimum. Owner: S04. Loaded on all peers by MatchManager.
## Public API: exported seconds/player counts. CLI override section: match.

## TUNE: seconds to show assigned roles before spawning.
@export var role_reveal_time := 3.0
## TUNE: seconds villagers hide while the mage is blind and frozen.
@export var head_start_time := 30.0
## TUNE: hunt duration in seconds (card starts at six minutes).
@export var hunt_time := 360.0
## TUNE: seconds to show results before returning to lobby.
@export var results_time := 10.0
## TUNE: lobby minimum; a round always requires at least one mage and one villager.
@export var min_players := 2
