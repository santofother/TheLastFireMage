#!/usr/bin/env bash
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/match/tests/multi_mage_test.tscn
launch_peer host
wait_peers 15
assert_clean_logs
assert_log host '^\[TEST\] MULTI MAGE PASSED'
echo "MULTI MAGE TEST PASSED ($OUT)"
