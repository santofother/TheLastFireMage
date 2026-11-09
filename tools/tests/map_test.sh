#!/usr/bin/env bash
# S05: saved town contracts, physics clearance, inter-district paths and roof access.
set -eu
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_map)"
result=0
"$GODOT" --headless --fixed-fps 60 --quit-after 30000 --log-file "$LOG.engine" --path "$ROOT/the-last-fire-mage" res://game/map/tests/map_test.tscn -- --no-steam >"$LOG" 2>&1 || result=$?
cat "$LOG"
if [ "$result" -ne 0 ]; then exit "$result"; fi
if rg -q 'SCRIPT ERROR|Parse Error|Failed to load|\[TEST\] FAIL' "$LOG"; then exit 1; fi
rg -q '^\[TEST\] MAP PASSED' "$LOG"
echo "MAP TEST PASSED"
