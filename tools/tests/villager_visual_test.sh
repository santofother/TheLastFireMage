#!/usr/bin/env bash
# Red villager model: clip selection, facing, carry socket and role swap on the real Player scene.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_villager_visual)"
"$GODOT" --headless --quit-after 100000 --path "$ROOT/the-last-fire-mage" res://game/player/tests/villager_visual_test.tscn \
    -- --no-steam >"$LOG" 2>&1
result=$?
grep '^\[TEST\]' "$LOG"
if grep -E '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load' "$LOG"; then
    echo "VILLAGER VISUAL TEST FAILED (errors, log: $LOG)"; exit 1
fi
if [ "$result" -eq 0 ] && grep -q '^\[TEST\] VILLAGER VISUAL PASSED' "$LOG"; then
    echo 'VILLAGER VISUAL TEST PASSED'; exit 0
fi
echo "VILLAGER VISUAL TEST FAILED (log: $LOG)"; exit 1
