# S07 — Headless bots + test runner v2
Agent: **Lean Codex** · Tier: **T3** · Wave 1 · Branch: `s07-bots`
Depends on: S02 · Parallel with: S03 S04 S05 S06 S08

Owns: `game/bots/**`, `tools/tests/**` (new files only; don't rewrite other cards' tests), `tools/run_tests.sh`
Read: `docs/ARCHITECTURE.md` §Player §Bots, `tools/run_tests.sh`, `tools/tests/*`, `core/network_manager.gd` (args part)

## Goal
Let any card test multiplayer with 2–5 fake players without the user. This saves the user's time and tokens
on every later card.

## Steps (all done in this one session)
- `--bot` CLI flag: the client joins and is driven by a `BotBrain` set as `player.input_driver` on
  `GameEvents.local_player_ready` (fills `PlayerInput` like a human: wander, random jumps, sprint,
  occasionally interact/primary).
- `--bots=N` on the host: spawn N server-side bot players with `GameEvents.system(&"main").spawn_player(id,
  name, true)`, ids from `Players.BOT_ID_BASE`, then set their `input_driver`.
- `tools/tests/lib.sh`: helpers for launching host + clients with args, waiting, grepping logs, asserting.
- `run_tests.sh`: `--quick` (fast subset) and full mode, timing per test.
- A soak test: host + 4 bots for 60 s → no errors in logs, all still connected.

## Tests
The soak test itself, plus all existing tests still pass.
