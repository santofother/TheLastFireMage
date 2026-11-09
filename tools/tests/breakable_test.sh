#!/usr/bin/env bash
# Furniture: real sprint impact, walking, fire, wall protection, late-join snapshot and round reset.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/props/tests/breakable_test.tscn
launch_peer host --host
sleep 0.3
launch_peer client --join=127.0.0.1
wait_peers 40
assert_log host '\[TEST\] BREAKABLE PASSED'
assert_log client '\[TEST\] BREAKABLE CLIENT PASSED'
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'BREAKABLE TEST PASSED'
