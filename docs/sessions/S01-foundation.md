# S01 — Foundation: merge spike, GDD, test runner
Agent: **Claude only** (head-engineer role, not capability) · Tier: **T3** · Claude: Sonnet 5.5, medium (Codex could do it equally well: GPT-6.1 Sol, medium) · Wave 0 · Branch: `s01-foundation`
Depends on: — · Parallel with: nothing (S02 needs this)

Owns: `main` merge of `feat/net-voice-spike`, `docs/design/GDD.md`, `tools/run_tests.sh`, `tools/tests/`,
`docs/STATUS.md`, `README.md`, `.gitignore`
Read: `docs/LastMageBrainstorming.md.txt`, `tools/net_test.sh`, `docs/STATUS.md`

## Goal
Get a clean `main` everyone branches from, a short design doc agents can read in parts, and one test command.

## Steps (all done in this one session)
1. Commit the workflow docs already on disk (`AGENTS.md`, `CLAUDE.md`, `docs/**`) on `feat/net-voice-spike`,
   then merge it into `main` (fast-forward if possible). Ask the user before pushing `main`.
2. `docs/design/GDD.md`: distill the brainstorm into ~2–3 pages with one `##` section per system (Match flow,
   Roles, Movement, Mage combat, Power, Chickens, Firestorm, Counterplay, Death/Spectator, Voice, Scoring, Map,
   Visual style). Each section: rules as bullets + a **starting numbers** table (e.g. head start 30 s, round
   6 min, villager height 1.0 m, mage 1.4 m, knife damage, cooldowns, chicken count). Mark guesses `(guess)`.
   Note open questions at the end instead of inventing answers.
3. `tools/run_tests.sh`: runs every `tools/tests/*.sh`, prints PASS/FAIL per test and a summary, exit code ≠ 0
   on any fail. Move `net_test.sh` into `tools/tests/` (leave a 1-line wrapper at the old path) and update
   the paths in `AGENTS.md`.
4. Ask the user whether to move Godot.app from Downloads to /Applications; if yes, update `AGENTS.md` + scripts.
5. Update `docs/STATUS.md` (S01 DONE, S02 READY) and the `README.md` (3 lines + link to WORKFLOW.md).

## Done when
`main` contains the spike + docs, `tools/run_tests.sh` passes, GDD exists, user approved the push.
