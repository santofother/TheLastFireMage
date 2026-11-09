#!/usr/bin/env bash
# Villager picker: the real menu sets the skin, and choices reach other peers, including late joiners.
# --villager is always passed so these runs leave the skin saved in the player's settings alone.
set -eu
source "$(dirname "$0")/lib.sh"

TEST_SCENE=res://game/player/tests/villager_picker_test.tscn
launch_peer menu --villager=red
wait_peers 15
assert_clean_logs
assert_log menu '^\[TEST\] VILLAGER PICKER PASSED'

unset TEST_SCENE
pids=(); logs=()
launch_peer host --host --name=Host --villager=blue --autotest=12
wait_log host 'Villager skin 1 -> Blue BV_' 8
sleep 2 # WHY: this client joins after the host's skin was set, so it proves late joiners receive it.
launch_peer blue --join=127.0.0.1 --name=BlueClient --villager=blue --autotest=8
launch_peer red --join=127.0.0.1 --name=RedClient --villager=red --autotest=8
wait_log blue 'Villager skin 1 -> Blue BV_' 8
wait_log red 'Villager skin 1 -> Blue BV_' 8
wait_peers 25
# WHY: not assert_clean_logs; clients quit before the host here, and it treats any disconnect as a failure.
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|\[TEST\] FAIL' "${logs[@]}"; then exit 1; fi
# Host's own body and BlueClient's; RedClient stays on the default body, so it logs no swap.
[ "$(grep -c 'Villager skin' "$OUT/host.log")" -eq 2 ] || { echo "Expected 2 skin swaps on host ($OUT)"; exit 1; }
echo "VILLAGER PICKER TEST PASSED ($OUT)"
