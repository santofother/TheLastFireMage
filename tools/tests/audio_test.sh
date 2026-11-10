#!/usr/bin/env bash
# S18 audio: sound bank vs cue sheet, buses/voice routing, LOS dread, noise ranges, storm emitter, room reverb.
# Single headless process (no network), but uses lib.sh so the port is random like every other test.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/audio/tests/audio_test.tscn
launch_peer audio
wait_peers 90
assert_log audio '\[TEST\] AUDIO PASSED'
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo 'AUDIO TEST PASSED'
