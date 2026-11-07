# S16 — Scoring + Mage rotation
Agent: **Lean Codex** · Tier: **T3** · Wave 3 · Branch: `s16-scoring`
Depends on: S04, S11 · Parallel with: S13 S14 S15

Owns: `game/scoring/**`
Read: `docs/ARCHITECTURE.md` §Scoring §Match §GameEvents, `docs/design/GDD.md` §Scoring, handoffs S04 S11

## Goal
A full party night: everyone is mage once, points decide the winner.

## Steps (all done in this one session)
- Server tracks points per round from `GameEvents` (mage: per villager killed + win bonus; villagers:
  survival time + win bonus). Values in a tuning resource.
- "Party" mode: rounds = number of players, each player mage once (order random or host-set), totals synced,
  final podium screen data for the HUD (`score_changed`, `party_ended`).
- Players leaving mid-party: keep their score, skip their mage turn.

## Tests
Headless: 3 peers, short rounds with scripted outcomes → each was mage once, totals match expected numbers.
