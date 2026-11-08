#!/usr/bin/env bash
# S08: deterministic fake-event HUD checks, including both target display sizes.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/ui/hud/tests/hud_test.tscn
launch_peer hud
wait_peers 20
assert_log hud '^\[TEST\] HUD PASSED'
assert_clean_logs
echo 'HUD TEST PASSED'
