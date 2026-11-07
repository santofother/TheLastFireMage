#!/usr/bin/env bash
# S03: two real ENet peers exercise owner flags and client -> server -> owner bump delivery.
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d -t lastmage_movement_net)"
COMMON=(--headless --quit-after 700 --path "$ROOT/the-last-fire-mage" res://game/player/tests/movement_net_test.tscn -- --no-steam --port=24696)
"$GODOT" "${COMMON[@]}" --host >"$OUT/host.log" 2>&1 &
host_pid=$!
"$GODOT" "${COMMON[@]}" >"$OUT/client.log" 2>&1 &
client_pid=$!
fail=0
wait "$host_pid" || fail=1
wait "$client_pid" || fail=1
for peer in host client; do
    grep '^\[TEST\]' "$OUT/$peer.log"
    if grep -E '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load' "$OUT/$peer.log"; then fail=1; fi
done
grep -q '^\[TEST\] MOVEMENT NETWORK PASSED' "$OUT/host.log" || fail=1
grep -q '^\[TEST\] MOVEMENT NETWORK CLIENT PASSED' "$OUT/client.log" || fail=1
if [ "$fail" -eq 0 ]; then echo 'MOVEMENT NETWORK TEST PASSED'; exit 0; fi
echo "MOVEMENT NETWORK TEST FAILED (logs: $OUT)"; exit 1
