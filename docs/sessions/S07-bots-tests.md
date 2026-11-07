# S07 — Headless bots + test runner v2
Agent: **Either** · Tier: **T3** · Codex: GPT-6.1 Sol, medium · Claude: Sonnet 5.5, medium · Wave 1 · Branch: `s07-bots`
Depends on: S02 · Parallel with: S03 S04 S05 S06 S08

Owns: `game/bots/**`, `tools/tests/**` (new files only; don't rewrite other cards' tests), `tools/run_tests.sh`
Read: `docs/ARCHITECTURE.md` §Player §Bots, `tools/run_tests.sh`, `tools/tests/*`, `core/network_manager.gd` (args part)

## Goal
Let any card test multiplayer with 2–5 fake players without the user. This saves the user's time and tokens
on every later card.

## Steps (all done in this one session)
- `--bot` CLI flag: the client joins and is driven by a bot brain instead of the keyboard (feeds the same
  input actions as a human: wander, random jumps, sprint, occasionally interact/primary).
- `--bots=N` on the host: spawn N local bot players (server-side) for quick local testing in one process.
- `tools/tests/lib.sh`: helpers for launching host + clients with args, waiting, grepping logs, asserting.
- `run_tests.sh`: `--quick` (fast subset) and full mode, timing per test.
- A soak test: host + 4 bots for 60 s → no errors in logs, all still connected.

## Tests
The soak test itself, plus all existing tests still pass.
