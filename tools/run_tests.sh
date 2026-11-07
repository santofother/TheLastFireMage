#!/usr/bin/env bash
# Runs every tools/tests/*.sh, prints PASS/FAIL per test and a summary. Exit code != 0 if any test fails.
# Usage: tools/run_tests.sh [name-filter]     (env GODOT=/path/to/Godot to override the binary)
set -u
DIR="$(cd "$(dirname "$0")/tests" && pwd)"
LOGDIR="$(mktemp -d -t lastmage_tests)"
pass=0; fail=0; failed=()
for t in "$DIR"/*${1:-}*.sh; do
	[ -f "$t" ] || continue
	name="$(basename "$t" .sh)"
	if bash "$t" >"$LOGDIR/$name.log" 2>&1; then
		echo "PASS  $name"; pass=$((pass+1))
	else
		echo "FAIL  $name  (log: $LOGDIR/$name.log)"; fail=$((fail+1)); failed+=("$name")
	fi
done
echo "---- $pass passed, $fail failed"
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "FAILED: ${failed[*]}"
[ $fail -eq 0 ]
