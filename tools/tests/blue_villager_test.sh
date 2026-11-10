#!/usr/bin/env bash
# Blue villager: scene loads, shares the red rig and clips, and plays every clip without errors.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_blue_villager)"
"$GODOT" --headless --quit-after 100000 --path "$ROOT/the-last-fire-mage" res://game/player/tests/blue_villager_test.tscn \
    -- --no-steam >"$LOG" 2>&1
result=$?
grep '^\[TEST\]' "$LOG"
if grep -E '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load' "$LOG"; then
    echo "BLUE VILLAGER TEST FAILED (errors, log: $LOG)"; exit 1
fi
if [ "$result" -eq 0 ] && grep -q '^\[TEST\] BLUE VILLAGER TEST PASSED' "$LOG"; then
    echo 'BLUE VILLAGER TEST PASSED'; exit 0
fi
echo "BLUE VILLAGER TEST FAILED (log: $LOG)"; exit 1
