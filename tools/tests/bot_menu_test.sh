#!/usr/bin/env bash
# S07: choose three bots in the real menu and click Host LAN.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/bots/tests/bot_menu_test.tscn
launch_peer host
wait_peers 15
assert_clean_logs
assert_log host '^\[TEST\] BOT MENU PASSED'
echo "BOT MENU TEST PASSED ($OUT)"
