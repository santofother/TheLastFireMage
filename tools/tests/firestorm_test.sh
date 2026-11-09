#!/usr/bin/env bash
# S14: use the actual match, test bots and real ENet stage/health replication including late join.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

TEST_SCENE=res://game/firestorm/tests/firestorm_test.tscn
MAP=--map=res://game/map/test_arena.tscn
TUNE=--tune=match.role_reveal_time=0.2,match.head_start_time=0.3,match.hunt_time=8.8,match.results_time=0.3,firestorm.start_time=0.8,firestorm.warning_time=1.1,firestorm.start_radius=12,firestorm.map_area=314.159265,firestorm.second_stage_delay=2,firestorm.final_hold_time=1.1,firestorm.mage_grace_time=1.35

launch_peer host --host --name=Host "$MAP" "$TUNE"
wait_log host '\[Net\] Hosting'
launch_peer client --join=127.0.0.1 --name=Early "$MAP" "$TUNE"
wait_log host '\[TEST\] FIRESTORM JOIN WINDOW'
launch_peer late --join=127.0.0.1 --name=Late --late-client "$MAP" "$TUNE"

if ! wait_peers 20; then
    echo "Firestorm peer failed (logs: $OUT)"
    exit 1
fi
for name in host client late; do
    assert_log "$name" '^\[TEST\] FIRESTORM PASSED'
done
if rg -n 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'FIRESTORM TEST PASSED'
