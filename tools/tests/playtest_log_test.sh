#!/usr/bin/env bash
# Playtest logger: host writes a JSONL with phases/round_end; a client writes nothing.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/scoring/tests/scoring_test.tscn
LOGDIR="$OUT/playtests"
launch_peer host --host --bots=2 --map=res://game/map/test_arena.tscn "--playtest-dir=$LOGDIR" \
	"--tune=match.role_reveal_time=0.4,match.head_start_time=0.4,match.hunt_time=3,match.results_time=0.4,scoring.villager_per_10s=0,firestorm.start_time=100"
wait_peers 60
f="$(ls "$LOGDIR"/*.jsonl | head -1)"
for ev in '"ev":"phase"' '"ev":"role"' '"ev":"round_end"' '"ev":"sample"'; do
	grep -q "$ev" "$f" || { echo "missing $ev in $f"; exit 1; }
done
python3 -c "import json,sys; [json.loads(l) for l in open('$f')]"
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
echo "PLAYTEST LOG TEST PASSED ($OUT)"
