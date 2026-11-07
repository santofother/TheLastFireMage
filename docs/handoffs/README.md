# Handoffs

Each finished session writes `Sxx.md` here (max ~25 lines). The next sessions read only the handoffs of the
cards they depend on, so put everything they need here and nothing else.

## Template

```markdown
# Sxx — <title>
Agent: <Claude Opus 5.5 / Codex top model / ...> · effort <low/medium/high> · branch `sNN-name`
Result: DONE | PARTIAL (what's missing) | BLOCKED (why)

## What exists now
- <files/scenes added, one line each>

## Public API (what other cards can use)
- `ClassName.func(args) -> type`: <one line>
- signal `name(args)`: <when it fires, on which peer>

## How to test
- Headless: `<command>` → expect `<log line>`
- Manual (needs the user): <steps, only if needed>

## Touched outside my card
- <file>: <minimal fix, tagged FIX(Sxx, agent)> (or "none")

## Contract change requested
- <proposal> (or "none")

## Known issues / next steps
- <short list>
```
