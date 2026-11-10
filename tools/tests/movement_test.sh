#!/usr/bin/env bash
# S03: scripted PlayerInput drives the real controller against physics fixtures.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_movement)"
# FIX(S14, Codex): Leave enough process frames for the added roof landings.
"$GODOT" --headless --quit-after 18000 --path "$ROOT/the-last-fire-mage" res://game/player/tests/movement_test.tscn \
    -- --no-steam >"$LOG" 2>&1
result=$?
grep '^\[TEST\]' "$LOG"
if grep -E '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load' "$LOG"; then
    echo "MOVEMENT TEST FAILED (errors, log: $LOG)"; exit 1
fi
if [ "$result" -eq 0 ] && grep -q '^\[TEST\] MOVEMENT PASSED' "$LOG"; then
    echo 'MOVEMENT TEST PASSED'; exit 0
fi
echo "MOVEMENT TEST FAILED (log: $LOG)"; exit 1
