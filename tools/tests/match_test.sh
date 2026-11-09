#!/usr/bin/env bash
# S04: real host + two clients exercise outcomes, late snapshots, roles, hooks, timer and resets.
set -e
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OUT:-$(mktemp -d -t lastmage_match)}"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
mkdir -p "$OUT"
echo "Logs: $OUT"
for scenario in ${MATCH_CASES:-timeout all_dead mage_died mage_left late_join two_mages}; do
	port="${PORT:-$((20000 + RANDOM % 20000))}"
	common=(--headless --path "$ROOT/the-last-fire-mage" res://game/match/tests/match_test.tscn -- --no-steam "--port=$port" "--match-case=$scenario" --map=res://game/map/test_arena.tscn)
	tune="match.role_reveal_time=0.5,match.head_start_time=0.6,match.hunt_time=3,match.results_time=0.5"
	if [ "$scenario" = timeout ]; then tune="match.role_reveal_time=0.5,match.head_start_time=2,match.hunt_time=10,match.results_time=0.5"; fi
	auto=(--autostart --autostart-players=3 --mage-id=1)
	if [ "$scenario" = mage_left ]; then auto=(); fi
	if [ "$scenario" = all_dead ]; then auto=(--autostart --autostart-players=3); fi
	if [ "$scenario" = late_join ]; then auto=(--autostart --autostart-players=2 --mage-id=1); fi
	if [ "$scenario" = two_mages ]; then auto=(--autostart --autostart-players=3 --mage-id=1 --mage-count=2); fi
	"$GODOT" "${common[@]}" "--tune=$tune" --host --name=Host "${auto[@]}" >"$OUT/$scenario-host.log" 2>&1 & pids=("$!")
	sleep 0.6
	"$GODOT" "${common[@]}" --join=127.0.0.1 --name=C1 >"$OUT/$scenario-c1.log" 2>&1 & pids+=("$!")
	late=()
	if [ "$scenario" = late_join ]; then
		for ((i=0; i<100; i++)); do
			if rg -q '^\[Match\] Phase HUNT' "$OUT/$scenario-host.log"; then break; fi
			sleep 0.1
		done
		late=(--late-client)
	fi
	"$GODOT" "${common[@]}" --join=127.0.0.1 --name=C2 "${late[@]}" >"$OUT/$scenario-c2.log" 2>&1 & pids+=("$!")
	failed=0
	for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
	pids=()
	for name in host c1 c2; do
		log="$OUT/$scenario-$name.log"
		if rg 'SCRIPT ERROR|Parse Error|ERROR:|\[TEST\] FAIL' "$log"; then failed=1; fi
		if [ "$scenario-$name" = mage_left-c1 ]; then
			rg -q '^\[TEST\] MATCH CLIENT LEFT' "$log" || failed=1
		else
			rg -q '^\[TEST\] MATCH PASSED' "$log" || failed=1
		fi
	done
	if [ "$failed" != 0 ]; then echo "MATCH TEST FAILED ($scenario; $OUT)"; exit 1; fi
	echo "  ok $scenario (host + two clients)"
done
echo "MATCH TEST PASSED"
