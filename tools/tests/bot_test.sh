#!/usr/bin/env bash
# S07: client --bot + two server bots; verifies movement and authority on both peers.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/bots/tests/bot_test.tscn
launch_peer host --host --bots=2 --bot-test-count=2 --bot-test-seconds=4
wait_log host '\[Bot\] Spawned server bot 1000001'
launch_peer client --join=127.0.0.1 --bot --bot-test-count=2 --bot-test-seconds=3
wait_peers 20
assert_clean_logs
for name in host client; do assert_log "$name" '^\[TEST\] BOT PASSED'; done
echo "BOT TEST PASSED ($OUT)"
