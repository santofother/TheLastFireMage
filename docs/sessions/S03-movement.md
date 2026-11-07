# S03 — Villager movement v2
Agent: **Either** · Tier: **T2** · Codex: GPT-6.1 Sol, high · Claude: Opus 5.5, medium · Wave 1 · Branch: `s03-movement`
Depends on: S02 · Parallel with: S04 S05 S06 S07 S08

Owns: `game/player/**`
Read: `docs/ARCHITECTURE.md` §Player, `docs/design/GDD.md` §Movement, `game/player/*` (current code)

## Goal
Movement that feels responsive and a bit slapstick, for 1.0 m villagers and a 1.4 m mage (same controller,
different tuning resource).

## Steps (all done in this one session)
- Momentum-based run (accel/decel), sprint, jump with coyote time + jump buffer, air control, crouch.
- Ledge mantle: grab an edge you jump at (~1.2–2 m above your feet) and pull up in one quick move.
  **No climbing** (no wall scaling, no hanging/shimmying, no climbing walls or ladders). Vertical movement =
  jumps + mantles only.
- Parkour jumps: momentum carries into jumps so you can leap gaps between roofs/balconies and from crates up
  onto ledges; a running jump clears noticeably more than a standing one.
- Fall consequences: stumble/ragdoll-lite tumble (short loss of control) from big falls. No fall damage yet.
- Third-person camera rig with collision; small FOV kick on sprint.
- Player-player bump (push each other a little on collision).
- `stun(seconds)` from the contract actually freezes input.
- All numbers in `game/player/tuning_villager.tres` and `tuning_mage.tres`.
- Keep the existing sync working (`MultiplayerSynchronizer`); add synced anim/state flags if needed.

## Tests
Extend/keep `tools/tests/` net test green. Add a headless test that spawns a player, feeds scripted input
(e.g. `--test-input=` or a test hook), and checks it moved, jumped and mantled a test ledge.
Manual for the user: "Does running/jumping feel good? Is the mantle reliable?"
