#!/usr/bin/env bash
# lower-settings: presets switch shadows/lights/particles/scale and Default restores the original look.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://core/tests/graphics_settings_test.tscn
launch_peer gfx --gfx=default
wait_peers 20
assert_log gfx '^\[TEST\] GRAPHICS SETTINGS PASSED'
assert_clean_logs
echo 'GRAPHICS SETTINGS TEST PASSED'
