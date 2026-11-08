#!/usr/bin/env bash
# S09: real PlayerInput casts with host authority and client outcome replication.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/mage/tests/combat_test.tscn
launch_peer host --host
sleep 0.3
launch_peer client --join=127.0.0.1
wait_peers 20
assert_log host '\[TEST\] COMBAT PASSED'
assert_log client '\[TEST\] COMBAT CLIENT PASSED'
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'MAGE TEST PASSED'
