# S17 — Playtest triage + next plan
Agent: **Claude only** (head-engineer role, not capability) · Tier: **T2** · Claude: Opus 5.5, medium (Codex could do it equally well: GPT-6.1 Sol, high) · Branch: `s17-plan`
Depends on: P1 notes

Owns: `docs/sessions/**`, `docs/STATUS.md`, `docs/design/GDD.md`, `docs/ARCHITECTURE.md`
Read: `docs/playtests/P1.md`, `docs/STATUS.md`, `docs/design/GDD.md`, handoffs' "Known issues" sections only

## Goal
Turn the playtest into the next waves of cards.

## Steps (all done in this one session)
- Bugs → small fix cards (T3/T4, mostly Either/Codex mini).
- Tuning changes → edit tuning resources directly if trivial, otherwise a tuning card.
- Update GDD where the playtest changed the design.
- Write waves 4–6 cards (dead-player throwables, parkour v2 (no climbing), art pipeline, audio, release prep; see
  WORKFLOW.md "Later waves") with Agent/Tier/Owns/Depends and the concurrency table.
- Update STATUS.md.
