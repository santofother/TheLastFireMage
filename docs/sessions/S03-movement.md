# S03 — Villager movement v2
Agent: **Either** · Tier: **T2** (Sonnet 5.5 high / top Codex medium) · Wave 1 · Branch: `s03-movement`
Depends on: S02 · Parallel with: S04 S05 S06 S07 S08

Owns: `game/player/**`
Read: `docs/ARCHITECTURE.md` §Player, `docs/design/GDD.md` §Movement, `game/player/*` (current code)

## Goal
Movement that feels responsive and a bit slapstick, for 1.0 m villagers and a 1.4 m mage (same controller,
different tuning resource).

## Steps (all done in this one session)
- Momentum-based run (accel/decel), sprint, jump with coyote time + jump buffer, air control, crouch.
- Ledge mantle onto ~1.2–2 m edges (no full climbing yet: that's wave 4).
- Fall consequences: stumble/ragdoll-lite tumble (short loss of control) from big falls. No fall damage yet.
- Third-person camera rig with collision; small FOV kick on sprint.
- Player-player bump (push each other a little on collision).
- Keep the S02 Player contract (ARCHITECTURE §Player) working: public vars/nodes/hooks, `set_role()`, the
  corpse look, and `can_control()` (stun/locks already freeze input in the stub; keep that).
- Read input only from `player.input` (PlayerInput), so bots (S07) drive the same code. Mouse look arrives
  as `input.look_delta`.
- All numbers in `game/player/tuning_villager.tres` and `tuning_mage.tres` (`PlayerTuning`, add fields freely).
- Keep the existing sync working (`MultiplayerSynchronizer`); add synced anim/state flags if needed.

## Tests
Keep `net_test` and `contract_test` green. Add a headless test that spawns a player, feeds scripted input
(e.g. `--test-input=` or a test hook), and checks it moved, jumped and mantled a test ledge.
Manual for the user: "Does running/jumping feel good? Is the mantle reliable?"
