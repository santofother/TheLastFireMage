# The Last Fire Mage — rules for every coding agent

Read this whole file at the start of every session. Both Claude Code and Codex read it, so it's the
single source of truth. `CLAUDE.md` only adds Claude-specific notes.

6-player Godot party game: a fire mage hunts small villagers through a seaside town while a firestorm
closes in. Proximity voice chat is central. Later the same lobby/voice layer will host more party games.

## Who's who
- **The user** owns the project and makes every final decision: they test builds, run playtests, approve
  pushing `main` and merges into it.
- **Head engineer = Claude Code** (under the user). It owns `docs/ARCHITECTURE.md`, the contracts, task
  cards and merges into `main`.
- **Builders = any agent** (Claude Code or Codex, any model) running one session card from
  `docs/sessions/`. Builders work on their card and nothing else.

## How a session works (every agent, every time)
1. Read `AGENTS.md` (this file) and your card `docs/sessions/Sxx-*.md`. Read only the other files your card
   lists, plus the handoffs (`docs/handoffs/`) of the cards yours depends on. Don't explore the whole repo.
2. Work on your own branch: `s<NN>-<short-name>` (e.g. `s06-chickens`). Prefer a separate git worktree so
   parallel sessions don't share a folder. In a fresh worktree run the import once (see Commands).
3. Touch only the files your card says you **own**. Reading other files is fine. If you need a change in a
   file you don't own, see "Cross-agent rules".
4. Add or extend a headless test for what you built whenever it can be tested without a screen.
5. Run `tools/run_tests.sh` (runs every `tools/tests/*.sh`). All tests must pass.
6. Write your handoff `docs/handoffs/Sxx.md` (template: `docs/handoffs/README.md`), max ~25 lines.
7. Commit on your branch, then push your branch and open a PR **without asking** (it doesn't touch `main`).
   Don't merge into `main` and never push `main` yourself: only merge sessions do that, after the user's OK.
8. Don't edit `docs/STATUS.md` (the head engineer updates it at merge time, to avoid merge conflicts).

## Cross-agent rules
- You are **not** here to review, audit or "improve" other agents' code. Don't refactor, restyle or rename
  code outside your card. That wastes tokens and causes merge conflicts.
- You **may** look at and fix other code only when it blocks your card (a crash, a wrong contract, a test
  failing in your path). Keep the fix minimal, mark it in place with
  `# FIX(Sxx, <agent>): <why>` and list it under "Touched outside my card" in your handoff.
- If a contract in `docs/ARCHITECTURE.md` is wrong or missing something you need, don't silently change it.
  Implement the smallest workaround, and write the proposed contract change in your handoff under
  "Contract change requested". The head engineer decides.
- Never delete or rewrite another session's tests to make yours pass.

## Code comments (this is how agents talk to each other)
Comments are for the next agent who has never seen your file. Keep them short and useful, don't narrate the
obvious.
- **File header** (top of every `.gd`, `##` doc comments): what the file does, who owns it (`Owner: Sxx`),
  its public API (signals, public funcs/vars other modules use), and which peer runs it.
- **`##` doc comment on every public func, signal and exported var.** Private helpers start with `_` and only
  get a comment if the logic is non-obvious.
- Tags (greppable, use exactly these):
  - `# NET:` who runs this code and who has authority (e.g. `# NET: server only`, `# NET: owner peer`).
  - `# CONTRACT:` an invariant other modules rely on. Changing it needs the head engineer.
  - `# TUNE:` a gameplay number meant for balancing (prefer putting it in the tuning resources).
  - `# TODO(Sxx):` known gap, with the card that will handle it.
  - `# FIX(Sxx, agent):` a minimal fix made in a file you don't own.
  - `# WHY:` a non-obvious decision (e.g. "Steam getVoice() returned nothing, so we send raw PCM").

## Token-saving rules (usage is the user's main bottleneck)
- Edit `.gd`, `.tscn`, `.tres`, `.cfg` as text. Don't open the Godot editor GUI.
- Verify with headless runs and logs, not screenshots. Screenshots only when the card is visual (art, UI
  layout) and then few, small ones.
- Read files in parts when you only need a section. Don't re-read files you just edited.
- No subagent fan-outs, no repo-wide audits. Batch independent commands.
- If you're stuck for more than ~3 attempts on the same bug, stop and write what you tried in the handoff
  instead of looping.
- Things that need a human (talking into a mic, feel/fun, two machines): write a short manual test in the
  handoff and stop.

## Layout
- `the-last-fire-mage/`: Godot 4.7 project (Forward+, Jolt Physics, D3D12 on Windows)
  - `core/`: reusable party-game layer (autoloads, in this order). **`core/` never depends on `game/`.**
    - `network_manager.gd`: ENet/Steam-agnostic session; host/join, player names, ping, CLI args (`NetworkManager.args`)
    - `steam_manager.gd`: Steam init (app 480), lobbies, invites → `SteamMultiplayerPeer`
    - `voice_manager.gd`: proximity voice. Raw 16 kHz PCM from Godot's mic in both modes, sent via RPC.
      F4 / `--voice-loopback` = hear yourself (single-machine playback test)
    - `debug_overlay.gd`: F3 overlay + mic meter
  - `game/`: this game's scenes and logic (folders per system, see `docs/ARCHITECTURE.md`)
  - `addons/godotsteam/`: GodotSteam 4.23.2 GDExtension (includes SteamMultiplayerPeer). The macOS paths in
    `godotsteam.gdextension` were fixed to `*.universal.dylib`; re-check this if you update the addon
  - `addons/lastmage_export/`: export plugin that copies `steam_appid.txt` next to builds
  - `export_presets.cfg`: Windows Desktop + macOS (universal, mic usage text, audio-input entitlement)
- `tools/`: `run_tests.sh` runs every `tools/tests/*.sh` (e.g. `net_test.sh`; `tools/net_test.sh` is a wrapper)
- `docs/ARCHITECTURE.md`: module map, ownership, contracts (head engineer)
- `docs/design/GDD.md`: distilled game design with numbers. Read only the sections your card names.
  (The raw brainstorm `docs/LastMageBrainstorming.md.txt` is for the user; agents use the GDD.)
- `docs/sessions/`: one card per session. `docs/workflow/`: how the user runs sessions.
- `docs/handoffs/`: one short note per finished session. `docs/STATUS.md`: board (head engineer only).
- `docs/STEAM_EXPORT_AND_TESTING.md`: export + 2-machine test guide for the user
- `build/`: export output (gitignored)

## Commands
Godot binary: `$GODOT`, default `/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot`
(if the user moves it to `/Applications`, update this line and `tools/*.sh`).
- Import (first run in a new worktree, and after adding files): `$GODOT --headless --path the-last-fire-mage --import`
- Headless network test (host + 2 clients, position sync + synthetic voice): `tools/tests/net_test.sh` → `NET TEST PASSED`
- Export: `$GODOT --headless --path the-last-fire-mage --export-debug "Windows Desktop" ../build/windows/TheLastFireMage.exe`
  (and `"macOS" ../build/macos/TheLastFireMage.app`). Needs 4.7.2 export templates.
  macOS preset must keep `codesign/codesign=3` (Apple codesign, identity `-`): Godot's built-in ad-hoc signer
  produced an app macOS SIGKILLs at launch (exit 137).
- **After every export, publish a GitHub release** (user's standing instruction). In `build/`:
  `rm -f windows.zip macos.zip && zip -r -X windows.zip windows && ditto -c -k --keepParent macos macos.zip`, then
  `gh release create vX.Y.Z windows.zip macos.zip --title "Version X.Y.Z" --notes "<what changed>"`.
  Pick the next version after `gh release list`. Only export from `main` unless the user asks otherwise.
- CLI args (after `--`): `--host`, `--join=IP`, `--port=N`, `--name=X`, `--no-steam`, `--autotest=SEC`,
  `--quit-after=SEC`, `--test-target=x,z`, `--test-voice`, `--voice-loopback`

## Conventions
- Networking: the server spawns players via `MultiplayerSpawner` (spawn_function, data = {id,name,pos}).
  Each player node is named by peer id; its authority = owning peer (client-authoritative movement for now).
  Sync is `MultiplayerSynchronizer` (position/rotation, 20 Hz). **Gameplay outcomes (damage, deaths, power,
  timers, scores) are decided by the server only.**
- `core/` hooks: signals `player_registered`, `peer_left`, `session_ended`; `VoiceManager.register_speaker()`
  and `VoiceManager.listener`.
- Voice RPC: `VoiceManager._voice_packet`, unreliable_ordered, channel 2.
- Mic capture uses the Godot 4.5+ direct API (`AudioServer.set_input_device_active` / `get_input_frames`).
  Don't go back to AudioStreamMicrophone + capture bus: routed into a muted bus, it captured nothing.
- Log with prefixes `[Net]`, `[Steam]`, `[Game]`, `[TEST]` (new systems add their own, e.g. `[Match]`,
  `[Mage]`). Tests grep these.
- GDScript: static types, `snake_case` files and funcs, `PascalCase` classes/nodes, tabs. One system per folder.
