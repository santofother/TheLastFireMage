#!/usr/bin/env bash
# Old man villager: scene loads, shares the red rig and clips, and plays every clip without errors.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_old_man_villager)"
"$GODOT" --headless --quit-after 100000 --path "$ROOT/the-last-fire-mage" res://game/player/tests/old_man_villager_test.tscn \
    -- --no-steam >"$LOG" 2>&1
result=$?
grep '^\[TEST\]' "$LOG"
if grep -E '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load' "$LOG"; then
    echo "OLD MAN VILLAGER TEST FAILED (errors, log: $LOG)"; exit 1
fi
if [ "$result" -eq 0 ] && grep -q '^\[TEST\] OLD MAN VILLAGER TEST PASSED' "$LOG"; then
    echo 'OLD MAN VILLAGER TEST PASSED'; exit 0
fi
echo "OLD MAN VILLAGER TEST FAILED (log: $LOG)"; exit 1
