# Workflow: how to run sessions

This is the user's guide. Agents don't need to read it (their rules are in `AGENTS.md`).

## The loop
1. Open `docs/STATUS.md` and pick a card marked **READY**. Cards in the same wave can run at the same time
   (see "What can run concurrently").
2. Start a session with the agent and model the card names (table below), in a **new worktree**.
3. Paste the **builder prompt** with the card number. Nothing else is needed: the card holds the details.
4. The session builds, tests, writes `docs/handoffs/Sxx.md`, commits, pushes its branch and opens a PR.
   It shouldn't need to ask you anything unless it's blocked.
5. When one or more cards are finished, run a **merge session** (Claude, cheap model). It merges the branches
   into `main`, runs the tests, updates `STATUS.md` and marks the next cards READY.
6. After each wave, export a build and play it (alone with 2 machines, or with friends at the checkpoints).
   Feed what you noticed into the next merge or triage session.

Why small sessions save tokens: every message in a session re-sends the whole conversation. A session that
starts from a 2-page card and ends after one feature stays cheap; a session that has built five features
re-reads all of them every turn. Handoff files carry what's needed from one session to the next.

## Prompts

**Builder prompt** (any agent, any card):
```text
You're a builder on The Last Fire Mage. Read AGENTS.md, then do card docs/sessions/S06-chickens.md. Follow the card's Owns list, run the tests, write the handoff, commit on branch s06-chickens, then push the branch and open a PR without asking me. Only stop to ask if you're blocked.
```
Change the card file and branch name. That's it.

**Merge prompt** (Claude Code, Sonnet 5.5, low effort, or Codex GPT-6 Luna, medium if Claude is out; normal session in the main folder, not a worktree):
```text
You're head engineer on The Last Fire Mage, doing a merge session. Read AGENTS.md and docs/STATUS.md. Merge these finished branches into main one at a time: s03-movement, s06-chickens. For each: read its handoff, merge, resolve conflicts (keep both sides' intent; ask me if unsure), run tools/run_tests.sh. Then update STATUS.md (status, merge log, mark newly READY cards), note any "Contract change requested" items for me, and ask before pushing main.
```

**Fix prompt** (when a playtest finds a bug; Codex GPT-6.1 Sol medium / Luna high, or Claude Sonnet 5.5 medium):
```text
Read AGENTS.md. Bug from playtest: <what happened, what you expected, which build>. Find the cause with the smallest read possible, fix it on branch fix-<short-name>, add a test if it's headless-testable, write a 5-line note in docs/handoffs/fix-<short-name>.md, commit, push the branch and open a PR without asking.
```

## Which agent and model
Each card says one of:
- **Either**: Claude or Codex will do it equally well. Use whichever has usage left (see pairing below).
- **Claude only**: head-engineer cards (S01, S02, S17, merges). That's a role choice so one agent keeps the
  architecture consistent, not a capability claim. If Claude usage runs out, Codex (Astra or Sol) can take
  these too.
- **ChatGPT only**: image generation (concept art, icons) in later waves.

Model tiers (pick the tier the card names):

| Tier | Codex (ChatGPT) | Claude Code | Use for |
|---|---|---|---|
| T1 hard | GPT-6 Astra, medium–high | Opus 5.5, high | architecture, voice codec, tricky netcode |
| T2 normal | GPT-6.1 Sol, high (or Astra, low) | Opus 5.5, medium | most gameplay features |
| T3 light | GPT-6.1 Sol, medium (or Luna, high) | Sonnet 5.5, medium | well-specified features, UI, bots |
| T4 chores | GPT-6 Luna, low–medium | Sonnet 5.5 low or Haiku 5.5 | merges, docs, small fixes, renames |

How the models compare (researched 2026-11-07; re-check when new models ship):
- **GPT-6 Astra** is OpenAI's top Codex model and a top-tier coder: clearly stronger than Sonnet 5.5 and in
  the same class as Opus 5.5. It's slow and uses the most quota. OpenAI recommends starting it at **low**
  effort; low/medium Astra is already very strong.
- **GPT-6.1 Sol** is "near-Astra at lower cost". It's the workhorse for most cards.
- **GPT-6 Luna** is the efficient model for focused, high-volume work. OpenAI recommends **high** effort for it.
- **GPT-6.1 Terra** is fast, good at writing and screenshots/visuals: fine for docs and UI checks.
- **Sonnet 5.5** is a step below Sol, so on the Claude side T2 work uses Opus, not Sonnet.
- **Fable 5.1** (Claude's top model) is very strong but very usage-heavy; save it for a T1 card that failed
  on Opus, if your plan includes it.

Rule of thumb: start one tier lower than you think. If the handoff says "PARTIAL" because it was too hard,
rerun the remainder one tier higher. Sources: OpenAI model docs (learn.chatgpt.com/docs/models), Endor Labs
Codex/Astra benchmark (endorlabs.com).

## How to start a session
**Claude Code (desktop app):** New session → folder `LastMage` → turn on the worktree option → pick model and
effort in the model picker → paste the builder prompt. For merge sessions, don't use a worktree.

**Codex (ChatGPT desktop app or CLI):** open the `LastMage` repo → start a new task/thread in worktree mode (or
in the CLI, create a worktree first: `git worktree add ../lm-s06 -b s06-chickens` and run `codex` inside it) →
pick the model and reasoning level → paste the builder prompt. Codex reads `AGENTS.md` automatically.

First time in a new worktree, the session runs Godot's import once (it's in `AGENTS.md`); that's normal.

## What can run concurrently
Cards in the same wave don't share files (each card has an Owns list), so they can run at the same time.
Practical limit: **3 builder sessions at once**. More than that and you become the bottleneck (approving,
pushing, testing), and merges get messy.

| Wave | Cards | Can run together | Needs before starting |
|---|---|---|---|
| 0 | S01 → S02 | no, one after another | — |
| 1 | S03, S04, S05, S06, S07, S08 | all of them | S02 merged |
| 2 | S09, S10, S11, S12 | all of them | S09: S03+S04 · S10: S03+S06 · S11: S04 · S12: none (can even start in wave 1) |
| 3 | S13, S14, S15, S16 | all of them | S13: S06+S09 · S14: S04 (hooks to S13 later) · S15: S03 · S16: S04+S11 |
| P1 | Playtest with friends | — | wave 3 merged, build exported |
| — | S17 triage → writes the next waves | — | P1 notes |

Suggested pairing per wave, while you have ChatGPT Pro (Codex has the bigger quota, so it takes about
two-thirds of the builder cards; Claude keeps head-engineer work and merges). Run 2 Codex + 1 Claude at a time:
- Wave 1: Codex: S03 movement, S04 match flow, S06 chickens, S07 bots · Claude: S05 map, then S08 HUD
- Wave 2: Codex: S09 combat (Astra), S10 carry/hide, S11 death · Claude: S12 voice
- Wave 3: Codex: S13 power, S14 firestorm, S16 scoring · Claude: S15 counterplay
Swap freely: every builder card is "Either". If one tool hits its limit, give its cards to the other.

## Checkpoints for you
- After S02: read `docs/ARCHITECTURE.md` (2 pages). This is the last cheap moment to change direction.
- After each wave: export + quick 2-machine test (`docs/STEAM_EXPORT_AND_TESTING.md`).
- P1: real playtest with friends. Write down what was fun, boring, broken. Start S17 with those notes.

## Later waves (planned in S17, after the first playtest)
Not detailed yet on purpose: the playtest will change them.
- Wave 4, gameplay depth: dead-player overhead layer + throwables, parkour v2 (jump routes, mantle polish; no climbing), tuning pass.
- Wave 5, art: concept art + style sheet (**ChatGPT only**, image generation), style test scene in the Salmara
  palette (Lean Claude), modular house kit (Claude only via Blender MCP, or CC0 kits like Kenney/Quaternius:
  Either), characters + chicken, rune fire VFX, sound pass with CC0 sounds.
- Wave 6, release prep: own Steam app ID, store page, signing.
