#!/usr/bin/env bash
# S15: thrown items stun/slow the mage with diminishing returns, ground breaking, cart and laundry line.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/counterplay/tests/counterplay_test.tscn
launch_peer solo
wait_peers 30
assert_log solo '\[TEST\] COUNTERPLAY PASSED'
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'COUNTERPLAY TEST PASSED'
