#!/usr/bin/env bash
# Headless ENet test: 1 host + 2 clients on localhost. Each player teleports to a known x,z;
# at ~7 s (all 3 connected) every process prints what it sees and we check all 3 players are where expected.
# Usage: tools/tests/net_test.sh        (env GODOT=/path/to/Godot to override the binary)
set -u
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ="$ROOT/the-last-fire-mage"
OUT="${OUT:-$(mktemp -d -t lastmage_nettest)}"
PORT="${PORT:-$(( 20000 + RANDOM % 20000 ))}" # WHY: random so parallel sessions can test at the same time
# FIX(S05, Codex): Fixed teleport targets belong on the stable arena, independent of village walls.
COMMON=(--headless --path "$PROJ" -- --map=res://game/map/test_arena.tscn)

mkdir -p "$OUT"; echo "Logs: $OUT"
"$GODOT" "${COMMON[@]}" --no-steam --host --port=$PORT --name=Host --test-target=0,8 --autotest=7 --quit-after=10 >"$OUT/host.log" 2>&1 &
sleep 2
"$GODOT" "${COMMON[@]}" --no-steam --join=127.0.0.1 --port=$PORT --name=C1 --test-voice --test-target=6,-9 --autotest=5 --quit-after=9 >"$OUT/c1.log" 2>&1 &
"$GODOT" "${COMMON[@]}" --no-steam --join=127.0.0.1 --port=$PORT --name=C2 --test-target=-6,-9 --autotest=5 --quit-after=9 >"$OUT/c2.log" 2>&1 &
wait

fail=0
check_pos() { # log name x z
	local line
	line=$(grep "^\[TEST\] POS $2 " "$1" | tail -1)
	if [ -z "$line" ]; then echo "  FAIL $(basename "$1"): no position for $2"; fail=1; return; fi
	echo "$line" | awk -v x="$3" -v z="$4" -v f="$(basename "$1")" -v n="$2" '{
		dx=$4-x; dz=$5-z; if (dx<0) dx=-dx; if (dz<0) dz=-dz
		if (dx<0.5 && dz<0.5) { print "  ok   " f ": " n " at " $4 "," $5 }
		else { print "  FAIL " f ": " n " at " $4 "," $5 " expected " x "," z; exit 1 } }' || fail=1
}
for f in host c1 c2; do
	log="$OUT/$f.log"
	grep -E "SCRIPT ERROR|Parse Error" "$log" && { echo "  FAIL $f.log has script errors"; fail=1; }
	check_pos "$log" Host 0 8
	check_pos "$log" C1 6 -9
	check_pos "$log" C2 -6 -9
done
grep -q "^\[TEST\] PEERS 2" "$OUT/host.log" && echo "  ok   host sees 2 peers" || { echo "  FAIL host peer count: $(grep PEERS "$OUT/host.log")"; fail=1; }
grep -q "CONNECTED my_id" "$OUT/c1.log" && grep -q "CONNECTED my_id" "$OUT/c2.log" && echo "  ok   both clients connected" || { echo "  FAIL client connect"; fail=1; }

# Voice pipeline: C1 sends a synthetic tone (raw PCM over ENet); host and C2 must receive and play it.
for f in host c2; do
	v=$(grep "^\[TEST\] VOICE" "$OUT/$f.log")
	echo "$v" | awk -v f="$f" '{split($4,r,"="); split($5,p,"="); if (r[2]>0 && p[2]>0) print "  ok   " f " voice: " $0; else { print "  FAIL " f " voice: " $0; exit 1 } }' || fail=1
done
grep "^\[TEST\] VOICE" "$OUT/c1.log" | sed 's/^/  info c1 /'
# S12: with the ADPCM codec on, the sender must use <= 50% of raw PCM's 256 kbit/s.
kb=$(grep -o "tx=[0-9.]*" "$OUT/c1.log" | head -1 | cut -d= -f2)
awk -v k="$kb" 'BEGIN{exit !(k+0 > 0 && k+0 <= 128)}' && echo "  ok   c1 voice bandwidth ${kb} kbit/s (raw 256)" || { echo "  FAIL c1 voice bandwidth: '${kb}' kbit/s"; fail=1; }

if [ $fail -eq 0 ]; then echo "NET TEST PASSED"; else echo "NET TEST FAILED (see $OUT)"; fi
exit $fail
