#!/usr/bin/env bash
# Scripted Space presses exercise the shipped player against physics fixtures.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_mantle)"
"$GODOT" --headless --quit-after 2400 --path "$ROOT/the-last-fire-mage" res://game/player/tests/mantle_test.tscn -- --no-steam >"$LOG" 2>&1
result=$?
grep '^\[TEST\]' "$LOG"
if grep -E '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load' "$LOG"; then
    echo "MANTLE TEST FAILED (errors, log: $LOG)"; exit 1
fi
if [ "$result" -eq 0 ] && grep -q '^\[TEST\] MANTLE PASSED' "$LOG"; then
    echo 'MANTLE TEST PASSED'; exit 0
fi
echo "MANTLE TEST FAILED (log: $LOG)"; exit 1
