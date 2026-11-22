#!/usr/bin/env bash
# Auntie villager: scene loads, shares the red rig and clips, and plays every clip without errors.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_auntie_villager)"
"$GODOT" --headless --quit-after 100000 --path "$ROOT/the-last-fire-mage" res://game/player/tests/auntie_villager_test.tscn \
    -- --no-steam >"$LOG" 2>&1
result=$?
grep '^\[TEST\]' "$LOG"
if grep -E '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load' "$LOG"; then
    echo "AUNTIE VILLAGER TEST FAILED (errors, log: $LOG)"; exit 1
fi
if [ "$result" -eq 0 ] && grep -q '^\[TEST\] AUNTIE VILLAGER TEST PASSED' "$LOG"; then
    echo 'AUNTIE VILLAGER TEST PASSED'; exit 0
fi
echo "AUNTIE VILLAGER TEST FAILED (log: $LOG)"; exit 1
