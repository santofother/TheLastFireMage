#!/usr/bin/env bash
# S07: full suite by default; --quick omits the 60-second soak. Optional name filter.
# Usage: tools/run_tests.sh [--quick] [name-filter]
set -u
DIR="$(cd "$(dirname "$0")/tests" && pwd)"
LOGDIR="$(mktemp -d -t lastmage_tests)"
quick=0; filter=""
for arg in "$@"; do
    case "$arg" in
        --quick) quick=1 ;;
        --*) echo "Unknown option: $arg"; exit 2 ;;
        *) filter="$arg" ;;
    esac
done
pass=0; fail=0; failed=()
for t in "$DIR"/*.sh; do
    name="$(basename "$t" .sh)"
    [ "$name" != lib ] || continue
    [[ "$name" == *"$filter"* ]] || continue
    if [ "$quick" -eq 1 ] && [ "$name" = bot_soak_test ]; then continue; fi
    started=$SECONDS
    if bash "$t" >"$LOGDIR/$name.log" 2>&1; then
        echo "PASS  $name  ($((SECONDS-started))s)"; pass=$((pass+1))
    else
        echo "FAIL  $name  ($((SECONDS-started))s; log: $LOGDIR/$name.log)"; fail=$((fail+1)); failed+=("$name")
    fi
done
if [ $((pass+fail)) -eq 0 ]; then echo "No tests matched: $filter"; exit 2; fi
echo "---- $pass passed, $fail failed (logs: $LOGDIR)"
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "FAILED: ${failed[*]}"
[ $fail -eq 0 ]
