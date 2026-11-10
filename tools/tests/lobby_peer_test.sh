#!/usr/bin/env bash
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/match/tests/lobby_peer_test.tscn
launch_peer host --host
sleep 0.5
launch_peer client --join=127.0.0.1
wait_peers 20
if grep -En "SCRIPT ERROR|Parse Error|ERROR:|\[TEST\] FAIL" "$OUT/host.log" "$OUT/client.log"; then exit 1; fi
assert_log host '^\[TEST\] CHARACTER SYNC PASSED'
assert_log client '^\[TEST\] GUEST LOBBY PASSED'
echo 'LOBBY PEER TEST PASSED'
