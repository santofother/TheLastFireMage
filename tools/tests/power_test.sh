#!/usr/bin/env bash
# S13 power: rewards, decay, final kill, resets, replication and late join snapshot.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/power/tests/power_test.tscn
launch_peer host --host
sleep 0.3
launch_peer client --join=127.0.0.1
wait_peers 20
assert_log host '\[TEST\] POWER PASSED'
assert_log client '\[TEST\] POWER CLIENT PASSED'
# Both peers deliberately exit after their success marker.
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'POWER TEST PASSED'
