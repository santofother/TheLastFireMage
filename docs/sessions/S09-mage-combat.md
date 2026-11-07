# S09 — Mage combat
Agent: **Lean Claude** (server-authoritative hit detection is subtle) · Tier: **T2** (Opus 5.5 medium) · Wave 2 · Branch: `s09-mage`
Depends on: S03, S04 · Parallel with: S10 S11 S12

Owns: `game/mage/**`
Read: `docs/ARCHITECTURE.md` §Mage §Authority §Health §Player, `docs/design/GDD.md` §Mage combat,
handoffs S03 S04

## Goal
Knife, Ignite, Fire Wave, with the server deciding every hit.

## Steps (all done in this one session)
- Mage abilities scene added under the player's `Abilities` node when the role is assigned.
- Knife: short melee, low damage. Client sends "swing" with aim; server validates range/angle/cooldown and
  applies damage through the health component.
- Ignite (short cooldown): knife burns for N seconds, more damage, small fire VFX placeholder.
- Fire Wave (long cooldown): forward cone/expanding wave, damage + knockback, blocked by walls (raycasts).
- Damage/range/spread read a `power_multiplier` value (default 1.0) that S13 will drive. `# CONTRACT:`
- Feedback: hit flash, sound placeholder, camera shake on the victim.
- Chickens are valid targets (they use the same health component).

## Tests
Headless: host + bot villager standing at known distance; scripted mage swings in and out of range → damage
only in range; Fire Wave behind a wall does nothing; kill → `player_died` with killer id.
