#!/usr/bin/env bash
# S11: death switches to spectator camera, corpse collision off, revive/new role restores the view.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/spectator/tests/spectator_test.tscn
launch_peer solo
wait_peers 30
assert_log solo '\[TEST\] SPECTATOR PASSED'
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'SPECTATOR TEST PASSED'
