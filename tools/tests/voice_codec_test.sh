#!/usr/bin/env bash
# S12: ADPCM codec round trip + >=50% bandwidth drop, voice groups, effect buses, jitter buffer.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://core/tests/voice_codec_test.tscn
launch_peer voice_codec
wait_peers 30
assert_log voice_codec '^\[TEST\] VOICE CODEC PASSED'
assert_clean_logs
grep '^\[TEST\] VOICE CODEC snr' "$OUT/voice_codec.log"
echo 'VOICE CODEC TEST PASSED'
