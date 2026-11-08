#!/usr/bin/env bash
# S07 shared helpers. Source this file; it is not a test.
# launch_peer NAME ARGS..., wait_log NAME REGEX [SECONDS], wait_peers [SECONDS],
# assert_log NAME REGEX, assert_clean_logs. Logs remain in $OUT on success/failure.
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${OUT:-$(mktemp -d -t lastmage_bots)}"
PORT="${PORT:-$(( 20000 + RANDOM % 20000 ))}"
pids=()
logs=()
mkdir -p "$OUT"
cleanup_peers() { for pid in ${pids[@]+"${pids[@]}"}; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup_peers EXIT
launch_peer() {
    local name="$1"; shift
    "$GODOT" --headless --path "$ROOT/the-last-fire-mage" "${TEST_SCENE:-res://game/main.tscn}" -- --no-steam "--port=$PORT" "$@" >"$OUT/$name.log" 2>&1 &
    pids+=("$!"); logs+=("$OUT/$name.log")
}
wait_log() {
    local deadline=$((SECONDS + ${3:-10}))
    until grep -Eq "$2" "$OUT/$1.log"; do
        if [ "$SECONDS" -ge "$deadline" ]; then echo "Timed out: $1 / $2 ($OUT)"; return 1; fi
        sleep 0.1
    done
}
wait_peers() {
    local deadline=$((SECONDS + ${1:-20})) failed=0
    for pid in ${pids[@]+"${pids[@]}"}; do
        while kill -0 "$pid" 2>/dev/null; do
            if [ "$SECONDS" -ge "$deadline" ]; then echo "Peer timeout ($OUT)"; return 1; fi
            sleep 0.1
        done
        wait "$pid" || failed=1
    done
    pids=()
    [ "$failed" -eq 0 ]
}
assert_log() { grep -Eq "$2" "$OUT/$1.log" || { echo "Missing: $1 / $2 ($OUT)"; return 1; }; }
assert_clean_logs() {
    for log in "${logs[@]}"; do
        if awk '/\[TEST\] BOT PASSED/ {exit} /PEER_DISCONNECTED|Session ended/ {found=1} END {exit !found}' "$log"; then
            echo "Disconnected before passing ($log)"; return 1
        fi
    done
    if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then return 1; fi
}
