#!/usr/bin/env bash
# S16: 3-player party (host + 2 server bots), scripted outcomes -> each was mage once, totals match.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/scoring/tests/scoring_test.tscn
launch_peer host --host --bots=2 --map=res://game/map/test_arena.tscn \
	"--tune=match.role_reveal_time=0.4,match.head_start_time=0.4,match.hunt_time=3,match.results_time=0.4,scoring.villager_per_10s=0,firestorm.start_time=100"
wait_peers 60
assert_log host '^\[TEST\] SCORING PASSED'
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo "SCORING TEST PASSED ($OUT)"
