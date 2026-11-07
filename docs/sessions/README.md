# Session cards

One card = one session = one branch. A builder reads `AGENTS.md` + its card + the handoffs its card depends on.

Card fields:
- **Agent**: Either · Lean Claude · Lean Codex · Claude only · ChatGPT only (see `docs/workflow/WORKFLOW.md`)
- **Tier**: T1 hard … T4 chores (model + effort table in WORKFLOW.md)
- **Owns**: the only files/folders this card may create or edit (plus its own handoff and tests)
- **Read**: the only other files it should open. Section names in GDD/ARCHITECTURE mean "read just that part".

Folder ownership is fixed by S02 in `docs/ARCHITECTURE.md`. If a card here disagrees with ARCHITECTURE.md
after S02, ARCHITECTURE.md wins.
