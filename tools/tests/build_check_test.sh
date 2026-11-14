#!/usr/bin/env bash
# Build check: a client on a different build is refused with a clear reason; a matching client joins.
set -u
source "$(dirname "$0")/lib.sh"
COMMON=(--map=res://game/map/test_arena.tscn --autotest=4 --quit-after=8)
launch_peer host --host --name=Host "${COMMON[@]}"
wait_log host "Hosting" 20 || exit 1
launch_peer good --join=127.0.0.1 --name=Good "${COMMON[@]}"
launch_peer bad --join=127.0.0.1 --name=Bad --build-id=0.0.0+bogus "${COMMON[@]}"
wait_peers 30 || exit 1
fail=0
assert_log host "^\[Net\] REGISTERED [0-9]+ Good" || fail=1
assert_log host "^\[Net\] REJECTED [0-9]+ build '0.0.0\+bogus'" || fail=1
assert_log bad "^\[Net\] Rejected by host: Can't join: the host is on game version" || fail=1
assert_log bad "^\[Net\] Session ended: Can't join" || fail=1
grep -q "Session ended: Can.t join" "$OUT/good.log" && { echo "  FAIL good client was dropped ($OUT)"; fail=1; }
grep -E "SCRIPT ERROR|Parse Error" "$OUT"/*.log && fail=1
if [ $fail -eq 0 ]; then echo "BUILD CHECK TEST PASSED"; else echo "BUILD CHECK TEST FAILED ($OUT)"; fi
exit $fail
