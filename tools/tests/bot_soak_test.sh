#!/usr/bin/env bash
# S07: 60 seconds of server bots plus a real client observing replicated movement.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/bots/tests/bot_test.tscn
launch_peer host --host --bots=4 --bot-test-seconds=61
wait_log host '\[Bot\] Spawned server bot 1000003'
launch_peer client --join=127.0.0.1 --bot --bot-test-seconds=60
wait_peers 80
assert_clean_logs
for name in host client; do assert_log "$name" '^\[TEST\] BOT PASSED'; done
echo "BOT SOAK TEST PASSED ($OUT)"
