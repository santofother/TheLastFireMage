#!/usr/bin/env bash
# S10: bots carry, hide, search and contest chickens through the real Interactor; client checks replication.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/interact/tests/interact_test.tscn
TUNE=--tune=chicken.flee_radius=0,chicken.idle_time_min=999,chicken.idle_time_max=999
launch_peer host --host "$TUNE"
sleep 0.3
launch_peer client --join=127.0.0.1 "$TUNE"
wait_peers 40
assert_log host '\[TEST\] INTERACT PASSED'
assert_log client '\[TEST\] INTERACT CLIENT PASSED'
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'INTERACT TEST PASSED'
