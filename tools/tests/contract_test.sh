#!/usr/bin/env bash
# Headless S02 contract test: boots main.tscn in one process, hosts ENet, checks the shared contracts
# (systems, InputMap, map markers, player API, tuning overrides, Health events). Expects CONTRACT PASSED.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp -t lastmage_contract)"
PORT="${PORT:-$(( 20000 + RANDOM % 20000 ))}" # WHY: random so parallel sessions can test at the same time
"$GODOT" --headless --path "$ROOT/the-last-fire-mage" res://game/common/tests/contract_test.tscn \
	-- --no-steam --port=$PORT --tune=match.hunt_time=12 >"$LOG" 2>&1
grep "^\[TEST\]" "$LOG"
if grep -E "SCRIPT ERROR|Parse Error|Failed to load" "$LOG"; then echo "CONTRACT TEST FAILED (errors, log: $LOG)"; exit 1; fi
grep -q "^\[TEST\] CONTRACT PASSED" "$LOG" && { echo "CONTRACT TEST PASSED"; exit 0; }
echo "CONTRACT TEST FAILED (log: $LOG)"; exit 1
