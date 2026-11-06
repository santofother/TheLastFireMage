# The Last Fire Mage

6-player Godot party game (a fire mage hunts villagers; proximity voice chat is central).
Current state: multiplayer + proximity voice **test build**, no gameplay yet.
Design doc: `LastMageBrainstorming.md.txt` (untracked; read only the sections you need).

## Layout
- `the-last-fire-mage/`: Godot 4.7 project (Forward+, Jolt Physics, D3D12 on Windows)
  - `core/`: reusable network/voice layer (autoloads, in this order):
    - `network_manager.gd`: ENet/Steam-agnostic session; host/join, player names, ping, CLI args (`NetworkManager.args`)
    - `steam_manager.gd`: Steam init (app 480), lobbies, invites → `SteamMultiplayerPeer`
    - `voice_manager.gd`: proximity voice. Steam voice in Steam mode, raw 16 kHz PCM in ENet mode, sent via RPC
    - `debug_overlay.gd`: F3 overlay + mic meter
  - `game/`: this game's scenes. `main.tscn` = greybox map + `PlayerSpawner` + menu; `player.tscn` = capsule
  - `addons/godotsteam/`: GodotSteam 4.23.2 GDExtension (includes SteamMultiplayerPeer). The macOS paths in
    `godotsteam.gdextension` were fixed to `*.universal.dylib`; re-check this if you update the addon
  - `addons/lastmage_export/`: export plugin that copies `steam_appid.txt` next to builds
  - `export_presets.cfg`: Windows Desktop + macOS (universal, mic usage text, audio-input entitlement)
- `tools/net_test.sh`: headless ENet integration test
- `docs/STEAM_EXPORT_AND_TESTING.md`: export + 2-machine test guide for the user
- `build/`: export output (gitignored)

## Commands
Godot binary: `/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot` (not in /Applications).
- Headless test (host + 2 clients, position sync + synthetic voice): `tools/net_test.sh` → `NET TEST PASSED`
- Re-import after adding files: `$GODOT --headless --path the-last-fire-mage --import`
- Export: `$GODOT --headless --path the-last-fire-mage --export-debug "Windows Desktop" ../build/windows/TheLastFireMage.exe`
  (and `"macOS" ../build/macos/TheLastFireMage.app`). Needs 4.7.2 export templates installed.
  macOS preset must keep `codesign/codesign=3` (Apple codesign, identity `-`): Godot's built-in ad-hoc signer
  produced an app macOS SIGKILLs at launch (exit 137). Running exported binaries from the Claude sandbox
  also needs the sandbox disabled.
- CLI args (after `--`): `--host`, `--join=IP`, `--port=N`, `--name=X`, `--no-steam`, `--autotest=SEC`,
  `--quit-after=SEC`, `--test-target=x,z`, `--test-voice`

## Conventions
- Networking: the server spawns players via `MultiplayerSpawner` (spawn_function, data = {id,name,pos}).
  Each player node is named by peer id, and its authority = owning peer (client-authoritative movement for now).
  Sync is `MultiplayerSynchronizer` (position/rotation, 20 Hz).
- `core/` must not depend on `game/`. Games hook in via signals (`player_registered`, `peer_left`,
  `session_ended`) and `VoiceManager.register_speaker()` / `VoiceManager.listener`.
- Voice RPC: `VoiceManager._voice_packet`, unreliable_ordered, channel 2.
- Mic capture uses Godot 4.5+ direct API (`AudioServer.set_input_device_active` / `get_input_frames`).
  Don't go back to AudioStreamMicrophone + capture bus: routed into a muted bus, it captured nothing.
  Real-mic check: run non-headless with `--autotest=6` and read `mic_peak` in the `[TEST] VOICE` line.
- Use physical-key checks for input (no InputMap entries yet). UI is built in code.
- Log with prefixes `[Net]`, `[Steam]`, `[Game]`, `[TEST]`. Tests grep these.

## Usage-saving rules (user's limits are the bottleneck)
- Edit `.tscn`/`.gd`/`.cfg` as text. Don't open the editor GUI.
- Verify with headless runs and logs (`tools/net_test.sh`). Take screenshots only when truly needed.
- Don't spawn many subagents. Keep tool calls batched.
- Voice/Steam can't be tested headless. Ask the user to run the manual plan in the docs.
- Commit at working milestones on a feature branch. Ask before pushing or opening PRs.
