# Status board

Builders edit **only their own row** when they land on `main` (and may flip TODO→READY for cards whose
dependencies are all DONE). The merge log is written only by merge sessions. See AGENTS.md step 8.

Legend: TODO · READY (dependencies on main, can start) · IN PROGRESS (branch name) · REVIEW (needs merge
session: reason) · DONE (on main, date) · BLOCKED (reason)

## Done before the plan
- Net + voice spike (`feat/net-voice-spike`): LAN + Steam lobby join Mac↔Windows, position sync, proximity
  voice confirmed working by the user (2026-11-06). Merged to `main` in S01.

## Board
| Card | Title | Wave | Status | Branch / note |
|---|---|---|---|---|
| S01 | Foundation: merge spike, GDD, test runner | 0 | DONE | merged to main (push pending user OK) |
| S02 | Architecture + contracts + stubs | 0 | DONE | merged to main |
| S03 | Villager movement v2 | 1 | DONE (2026-11-07) | s03-movement |
| S04 | Match flow, roles, timer, win | 1 | DONE (2026-11-07) | s04-match |
| S05 | Greybox town map v1 | 1 | READY | |
| S06 | Chickens | 1 | DONE (2026-11-07) | s06-chickens |
| S07 | Headless bots + test runner v2 | 1 | DONE (2026-11-07) | s07-bots |
| S08 | HUD shell | 1 | DONE (2026-11-07) | s08-hud; fix-hud-voice (playtest HUD/voice fix) |
| S09 | Mage combat | 2 | DONE (2026-11-07) | s09-mage |
| S10 | Carry, hide, interact | 2 | DONE (2026-11-08) | s10-interact |
| S11 | Death + basic spectator | 2 | DONE (2026-11-08) | s11-death |
| S12 | Voice v2 (bandwidth, mage distortion, dead routing) | 2 | DONE (2026-11-08) | s12-voice |
| S13 | Mage power + decay | 3 | DONE (2026-11-08) | codex/fix-voice-health-power; kill rewards, tiers, decay + sync |
| S14 | Firestorm | 3 | READY | S13 power threshold now implemented |
| S15 | Villager stuns / counterplay | 3 | READY | |
| S16 | Scoring + Mage rotation | 3 | READY | |
| P1 | Playtest 1 (user + friends) | — | TODO | after wave 3 |
| S17 | Playtest triage + next plan | — | TODO | after P1 |

## Merge log
| Date | Card | Merged by | Notes |
|---|---|---|---|
| 2026-11-07 | S01 | Claude | spike + docs fast-forwarded into main; GDD, run_tests.sh added |
| 2026-11-07 | S02 | Claude | fast-forward; ARCHITECTURE.md, common/, stubs, InputMap; contract_test added |
| 2026-11-07 | S03 | Codex | merged s03-movement; all six test suites passed; no contract changes requested |
| 2026-11-07 | S07 | Codex | merged s07-bots; all 10 test suites passed; no conflicts or contract changes requested |
| 2026-11-07 | S07 | Codex | verified hosting-menu bot selector follow-up on main; all 11 test suites passed; no contract changes requested |
