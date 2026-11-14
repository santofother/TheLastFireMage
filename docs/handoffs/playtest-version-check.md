# playtest-version-check — frozen players / no chat / quiet dread
Agent: Claude Opus 5.5 · effort low · branch `main` (head engineer fix)
Result: DONE

## Root cause (playtest 2026-11-14, Steam, santo hosting + Joe)
- Host ran stale local code (20ad566, editor run) while Joe ran v0.1.24. v0.1.24 replaced position/rotation sync
  with `net_state` and added args to `VoiceManager._voice_packet`. Host log: 13k `Invalid packet received. Size too
  small` (on_sync_receive) + 9.8k `_voice_packet expected 3 args, called with 5`. So: players frozen at spawn,
  `[Interact] rejected ... too far from Chicken`, no prox chat, ghost ping pointing at spawn positions.

## What exists now
- `core/network_manager.gd`: `GAME_VERSION` + `build_id` ("0.1.25+<commit>"). Client sends it in `_register`; host
  refuses mismatches (`[Net] REJECTED`, client gets the reason via `session_ended`, shown in the menu). Client gives up
  after 15 s if an old host never accepts it. `--build-id=X` overrides (tests).
- `addons/lastmage_export/plugin.gd`: stamps `res://build_commit.txt` (git short hash) into every export.
- Dread: settles after 2.5 s (was 8) to 20 % (was 60 %), Dread bus -13.9 dB (was -9.9). Stinger unchanged.
- Tests: `tools/tests/build_check_test.sh`; bot_test now checks the host sees a walking client move;
  spectator_test checks the ghost ping marks a living villager.

## Touched outside my card
- `game/bots/tests/bot_test.gd`, `game/spectator/tests/spectator_test.gd` (added checks only), `game/audio/*` tuning.

## Contract change requested
- none (AGENTS.md: bump `GAME_VERSION` before each export).

## Known issues / next steps
- Not verified on two machines with matching builds yet: needs the next playtest (both on v0.1.25).
