# Status board

Only the head engineer (Claude, during S01 / merge sessions) edits this file. Builders write handoffs instead.

Legend: TODO · READY (dependencies merged, can start) · IN PROGRESS (branch name) · REVIEW (handoff written,
waiting for merge) · DONE · BLOCKED (reason)

## Done before the plan
- Net + voice spike (`feat/net-voice-spike`): LAN + Steam lobby join Mac↔Windows, position sync, proximity
  voice confirmed working by the user (2026-11-06). Merged to `main` in S01.

## Board
| Card | Title | Wave | Status | Branch / note |
|---|---|---|---|---|
| S01 | Foundation: merge spike, GDD, test runner | 0 | DONE | merged to main (push pending user OK) |
| S02 | Architecture + contracts + stubs | 0 | READY | |
| S03 | Villager movement v2 | 1 | TODO | |
| S04 | Match flow, roles, timer, win | 1 | TODO | |
| S05 | Greybox town map v1 | 1 | TODO | |
| S06 | Chickens | 1 | TODO | |
| S07 | Headless bots + test runner v2 | 1 | TODO | |
| S08 | HUD shell | 1 | TODO | |
| S09 | Mage combat | 2 | TODO | |
| S10 | Carry, hide, interact | 2 | TODO | |
| S11 | Death + basic spectator | 2 | TODO | |
| S12 | Voice v2 (bandwidth, mage distortion, dead routing) | 2 | TODO | |
| S13 | Mage power + decay | 3 | TODO | |
| S14 | Firestorm | 3 | TODO | |
| S15 | Villager stuns / counterplay | 3 | TODO | |
| S16 | Scoring + Mage rotation | 3 | TODO | |
| P1 | Playtest 1 (user + friends) | — | TODO | after wave 3 |
| S17 | Playtest triage + next plan | — | TODO | after P1 |

## Merge log
| Date | Card | Merged by | Notes |
|---|---|---|---|
| 2026-11-07 | S01 | Claude | spike + docs fast-forwarded into main; GDD, run_tests.sh added |
