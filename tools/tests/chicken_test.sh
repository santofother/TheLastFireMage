#!/usr/bin/env bash
# S06: host + one client, 10 chickens on a flat navmesh: wander, flee, carry/drop, no falling, kill sync.
set -e
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OUT:-$(mktemp -d -t lastmage_chicken)}"
PORT="${PORT:-$(( 20000 + RANDOM % 20000 ))}"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
mkdir -p "$OUT"
echo "Logs: $OUT"
common=(--headless --path "$ROOT/the-last-fire-mage" res://game/chicken/tests/chicken_test.tscn -- --no-steam "--port=$PORT")
"$GODOT" "${common[@]}" --host --name=Host >"$OUT/host.log" 2>&1 & pids=("$!")
sleep 0.6
"$GODOT" "${common[@]}" --join=127.0.0.1 --name=C1 >"$OUT/c1.log" 2>&1 & pids+=("$!")
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
pids=()
for name in host c1; do
	log="$OUT/$name.log"
	if grep -E 'SCRIPT ERROR|Parse Error|ERROR:|\[TEST\] FAIL' "$log"; then failed=1; fi
	grep -q '^\[TEST\] CHICKEN PASSED' "$log" || failed=1
done
grep -q '^\[TEST\] chicken_killed' "$OUT/host.log" || failed=1
grep -q '^\[TEST\] chicken_killed' "$OUT/c1.log" || failed=1
if [ "$failed" != 0 ]; then echo "CHICKEN TEST FAILED ($OUT)"; exit 1; fi
echo "CHICKEN TEST PASSED"
