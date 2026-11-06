# Exporting and testing The Last Fire Mage (Steam + LAN)

This guide covers how to build the game for Windows and Mac, move it to your other PC, and run a
two-machine test of connections and proximity voice. You don't need to be a Godot expert to follow it.

The current build is a **multiplayer + voice test only**. There's no gameplay yet: one greybox map,
capsule players, proximity voice chat, and a debug overlay.

---

## 1. One-time setup: install the export templates

Godot needs "export templates" (the prebuilt game engine for each platform) before it can export.
You only do this once per Godot version.

1. Open Godot (`~/Downloads/Godot.app`) and open the project in `the-last-fire-mage/`.
2. Go to **Editor → Manage Export Templates…**
3. Click **Download and Install**. The download is about 1 GB. Wait until it shows **4.7.2.stable — Installed**.
   - If the download fails, get the `.tpz` file for **4.7.2 stable** from
     <https://godotengine.org/download/archive/> ("Export templates"). Then click **Install from File…** in
     the same window and pick that file.

When it's done, this folder exists:
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`

---

## 2. Exporting the builds

Two export presets are already set up: **Windows Desktop** and **macOS** (universal, so it runs on both Intel and Apple Silicon Macs).
Builds go to `build/` at the top of the repo. That folder is ignored by git.

### From the Godot editor
1. **Project → Export…**
2. Select **Windows Desktop**, then click **Export Project…**. Keep the suggested path
   (`build/windows/TheLastFireMage.exe`).
   - Leave **Export With Debug** ticked while testing. You then also get `TheLastFireMage.console.exe`,
     which opens a window showing the logs. That's very useful when something goes wrong.
3. Select **macOS**, then **Export Project…** → `build/macos/TheLastFireMage.app`.

### From the terminal (same result)
```bash
cd ~/PersonalProjects/LastMage/the-last-fire-mage
```
```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug "Windows Desktop" ../build/windows/TheLastFireMage.exe
```
```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug "macOS" ../build/macos/TheLastFireMage.app
```

### What must be next to the game

**Windows** (`build/windows/`). Keep all of these files together in one folder:

| File | What it is |
|---|---|
| `TheLastFireMage.exe` | the game |
| `TheLastFireMage.console.exe` | same game, with a log window (debug exports only) |
| `TheLastFireMage.pck` | the game's data |
| `libgodotsteam.windows.template_*.x86_64.dll` | GodotSteam |
| `steam_api64.dll` | Valve's Steam library |
| `steam_appid.txt` | contains `480`. Tells Steam which app this is. Copied automatically by our export plugin |

**Mac** (`build/macos/TheLastFireMage.app`): everything is inside the `.app`. Debug exports also create
`TheLastFireMage.command`; double-click it to run the game with a Terminal window showing the logs. The Steam libraries are in
`Contents/Frameworks/`. The Mac build doesn't need `steam_appid.txt` because the game sets
app ID 480 in code. A copy is still placed next to the `.app`, and it does no harm.

If a Steam library is missing, the game still starts, but the Steam buttons are greyed out. The
menu then says "Steam not available".

---

## 3. Getting the build onto the Windows PC

1. In Finder, right-click `build/windows` → **Compress "windows"**.
2. Copy `windows.zip` to the PC using a USB stick, Google Drive/Dropbox/OneDrive, or a shared network folder.
3. On the PC: right-click the zip → **Extract All…** Don't run it from inside the zip.
4. Double-click `TheLastFireMage.console.exe` (or `TheLastFireMage.exe`).
   - If you see **"Windows protected your PC"**: click **More info → Run anyway**. This happens because the
     build isn't code-signed.
   - If Windows Firewall asks about network access, allow **Private networks**. LAN mode needs this.

Re-export and re-copy the whole folder each time you change the game.

---

## 4. Getting past the Mac "unidentified developer" warning

The Mac build is only "ad-hoc" signed, without a paid Apple Developer ID. The preset signs with Apple's own `codesign`
tool (setting "Xcode codesign", identity `-`). Godot's built-in signer produced a Mac app that macOS
killed instantly on launch, so don't switch it back.

- **A build you made on this Mac** normally opens with a double-click.
- **A build that was downloaded or AirDropped** (for example, to a friend's Mac) gets blocked the first time:
  1. Double-click it. You'll get a warning. Click **Done/Cancel**.
  2. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to
     "TheLastFireMage was blocked". Confirm with your password.
  3. Terminal alternative: `xattr -dr com.apple.quarantine /path/to/TheLastFireMage.app`
- **Microphone:** on first launch macOS asks "TheLastFireMage would like to access the microphone".
  Click **Allow**. If you clicked Don't Allow: **System Settings → Privacy & Security → Microphone**,
  turn TheLastFireMage on, then restart the game.
  (The project turns on audio input and includes the microphone permission text in the Mac export. Without
  these, macOS would silently block the mic.)

---

## 5. Running a two-machine Steam test

**Each machine must be logged into a different Steam account.** Steam won't connect an account to
itself. Make a free second account if you need one, and make the two accounts Steam friends so invites work.

We use Valve's public test app **480 ("Spacewar")** until you have your own app ID. Steam will show you as
"Playing Spacewar". That's expected.

1. Start Steam on both machines and log in. Steam must be running *before* you start the game.
2. Start the game on both machines. The menu should say **"Steam: Logged in as <name>"**.
   If it says "Steam not available", see Common failures (section 8).
3. **Machine A (host):** type a name → **Host Steam lobby**. You spawn on the map.
4. **Machine B (join)**, using either of these:
   - **Lobby list (most reliable):** click **Refresh lobby list**, select "<A's name>'s game", then click
     **Join selected lobby**. Only lobbies from *our* game show up. They're filtered out of all the
     other Spacewar lobbies.
   - **Invite:** on A, press **Esc → Invite Steam friends**, pick B. On B, accept the invite in Steam chat.
     **The game must already be running on B.** With app 480, accepting an invite while the game is closed would
     launch Valve's Spacewar instead of our game. The Steam overlay (needed for the invite dialog) sometimes doesn't
     appear for games not launched through Steam. If that happens, use the lobby list.
5. Up to 6 players can join the same lobby.

### LAN / direct-IP test (no Steam needed)
1. Host machine: **Host LAN** (port 24680).
2. Find the host's IP address. On Mac, run `ipconfig getifaddr en0` in Terminal. On Windows, run `ipconfig` and
   look for "IPv4 Address".
3. Other machine: type that IP → **Join IP**.
4. Both machines must be on the same network, and UDP port 24680 must be allowed through the firewall.
5. LAN mode sends voice as raw audio from the **Mic** picker in the menu. That's fine for a home network.

### Controls
WASD move · mouse look · Space jump · **hold V** to talk (or switch to open mic in the menu) ·
**Esc** menu (leave, invite, mic settings) · **F3** debug overlay.

---

## 6. Test checklist

Do every step **Mac-hosts / Windows-joins**, then swap: **Windows-hosts / Mac-joins**.

| # | Check | How |
|---|---|---|
| 1 | Connect | Joiner appears on the host's map with the right name above their head. F3 shows `Peers: 1` and a ping |
| 2 | Movement sync | Walk, jump, and turn on each machine. The other screen shows it smoothly |
| 3 | Voice heard | Stand close together. Hold V on one machine and talk. The other machine hears you, and "SPEAKING" shows above your head |
| 4 | Mic meter | Bottom-left bar moves when you talk. F3 `Voice packets sent` goes up while you hold V |
| 5 | Falloff | While one player talks, the other walks away. Full volume within about 3 m, quieter with distance, **silent past about 25 m** |
| 6 | Direction | Turn so the speaker is on your left, then on your right. The sound pans |
| 7 | Push-to-talk | With push-to-talk on, nothing is sent until you hold V (F3 sent count stays flat) |
| 8 | Open mic | Turn push-to-talk off. Talking sends; silence stops sending |
| 9 | Leave / rejoin | Joiner presses Esc → Leave game, then joins again. Host quits → joiner returns to the menu with "Host left the game" |
| 10 | Mac ↔ Windows | Steps 1–9 work in **both** directions |
| 11 | Optional: 3+ players | Add more machines or accounts. Everyone sees and hears everyone |

### Voice test plan (manual, about 10 minutes)
1. Use headphones on at least one machine. Otherwise the speakers feed back into the other mic.
2. Steam mode, Mac host + Windows joiner: do checklist rows 3–8.
3. Swap host and joiner, then repeat rows 3–5.
4. LAN mode (Host LAN / Join IP): repeat rows 3–5. This tests the raw-PCM voice path and the in-game Mic picker.
5. Note in F3: ping, `sent`/`received` counters, and whether audio crackles or lags. Tell Claude what you saw.

---

## 7. Automated check (no Steam, no audio hardware)

`tools/net_test.sh` starts a headless LAN host and 2 clients on this Mac. It checks that everyone connects,
that every player sees every other player at the right position, and that a synthetic voice tone from one
client reaches and plays on the other two.
```bash
tools/net_test.sh
```
It prints `NET TEST PASSED` or tells you which check failed.

---

## 8. Common failures and fixes

| Symptom | Fix |
|---|---|
| Menu says **"Steam not available"** | Start and log into Steam **before** the game. Check `steam_appid.txt` is next to the exe (Windows). If it still fails, open `steam://install/480` in a browser to add Spacewar to the account, then retry |
| Steam buttons greyed out on Windows, console says it can't load GodotSteam | The `.dll` files aren't next to the `.exe`. Re-copy the whole export folder |
| Both machines on the **same Steam account** | Won't work. Use two different accounts |
| Lobby list is empty | The host must be in a lobby first (Host Steam lobby). Click Refresh again after a few seconds. Both machines must run the same build |
| Invite accepted but Spacewar opened | The game wasn't running on the joiner. Start our game first, then accept, or use the lobby list |
| Connected, but no voice | On Mac: check the microphone permission (section 4). In Steam mode, check **Steam → Settings → Voice** uses the right mic (Steam voice ignores the in-game Mic picker). Make sure you're holding **V** with the game window focused. F3: does `sent` go up on the speaker's machine and `received` go up on the listener's? |
| Voice works close up but never gets quiet | Check F3 says `Falloff: full <= 3 m, silent >= 25 m`. Distance is measured between players, not cameras |
| Mic meter doesn't move | Pick another device in **Mic**. On Mac, check the microphone permission. The meter uses Godot's mic, while Steam voice uses Steam's mic setting |
| LAN join times out | Wrong IP, different networks, or firewall. Allow the game on **Private networks** in Windows Firewall. Try the host's IP from `ipconfig` |
| Mac says the app "is damaged and can't be opened" | It was quarantined in transit. Run `xattr -dr com.apple.quarantine TheLastFireMage.app` |
| Export fails with "No export template found" | Do section 1 |
| Mac app quits instantly with no window (Terminal shows exit 137 / "Killed") | Its code signature was rejected. Check the macOS preset still has **Codesign → Xcode codesign** with identity `-`, then re-export |
| Windows "Windows protected your PC" | More info → Run anyway (unsigned build) |

Logs: on Windows run `TheLastFireMage.console.exe`. On Mac run
`build/macos/TheLastFireMage.app/Contents/MacOS/TheLastFireMage` from Terminal. Lines start with `[Net]`,
`[Steam]`, or `[Game]`.

---

## 9. What changes when you pay for your own Steam app ID

1. Pay the Steam Direct fee and create the app in Steamworks. You get an app ID (e.g. `1234560`).
2. In `the-last-fire-mage/core/steam_manager.gd`, change `APP_ID := 480` to your ID. You can also change
   `GAME_KEY`, which matters less once you're no longer sharing app 480 with everyone else.
3. Change `the-last-fire-mage/steam_appid.txt` to your ID. Keep it for local testing, but **don't ship it** in builds
   uploaded to Steam. Steam provides the ID when it launches the game.
4. Upload builds through Steamworks (SteamPipe) and install them via Steam on each test machine. Testers need a
   key or to be added to the app's beta.
5. What you gain:
   - Invites launch *your* game instead of Spacewar.
   - The Steam overlay works reliably because the game is launched by Steam.
   - Steam shows your game's name.
   - You can make lobbies **friends-only** instead of public (`Steam.LOBBY_TYPE_FRIENDS_ONLY` in `host_lobby()`).
   - Voice and networking code don't change at all.
6. Optional later: use Steamworks rich presence so friends can right-click → Join game. You'd also code-sign and
   notarize the Mac build (needs an Apple Developer account) so the "unidentified developer" warning goes away.
