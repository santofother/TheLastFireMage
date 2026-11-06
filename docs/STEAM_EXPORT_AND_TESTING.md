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

### How this works (read once)
- You **don't install, buy, or launch "Spacewar"**. Spacewar is Valve's free test app, ID **480**.
  Every developer without their own app ID borrows that ID. Our game tells Steam "I am app 480" (that's what
  `steam_appid.txt` and the code do), and Steam lets it use lobbies, networking and voice.
- You start **our game** by double-clicking it, **not** through your Steam library. The Steam app just has to be
  open and logged in in the background. While our game runs, your Steam profile shows **"Playing Spacewar"**.
  That's expected.
- **Each machine needs its own Steam account.** Two copies of the game on the same account can't connect.

### Part A: one-time setup

**A1. Install Steam on both machines** (skip on any machine that already has it):
- Windows: download from <https://store.steampowered.com/about/>, run `SteamSetup.exe`, and follow the installer.
- Mac: download from the same page. Open the `.dmg`, drag **Steam** into **Applications**, then open it.
  On first launch it downloads updates for a minute or two.

**A2. Get a second Steam account** (if you only have one):
1. On either machine, open <https://store.steampowered.com/join> in a browser.
2. Use a different email address from your main account, confirm the email, and pick an account name and password.
3. A brand-new account is a "limited" account (no money spent). That's fine for this test: lobbies, voice and
   networking all work. The only restriction is that a limited account **can't send** friend requests, so friend
   requests have to come from your main account (A3).

**A3. Optional: make the two accounts friends.** You only need this for the *invite* method. The *lobby list*
method works without it.
1. On the machine logged into the **second** account: Steam → **Friends** (top menu) → **Add a Friend**. Copy the
   **Friend Code** shown there.
2. On the machine logged into your **main** account: **Friends → Add a Friend**, paste the code, then click **Send Invite**.
3. Back on the second account, accept the request in the Steam friends list (the bell/notifications icon).

**A4. Log each machine into a different account:**
- Mac: open Steam and log in with account 1 (for example, your main account).
- Windows: open Steam and log in with account 2. If Steam is already logged into account 1 there:
  **Steam** menu (top-left) → **Change Account…** → log in with account 2.
- One account can only be logged in on one computer at a time. If Steam on one machine says you logged in
  elsewhere, that's the problem.

**A5. Pick the microphone Steam should use** (Steam voice ignores the in-game Mic dropdown):
- Windows and Mac: in Steam, **Steam** menu (Mac: **Steam** in the top menu bar) → **Settings** → **Voice** →
  choose your mic under **Voice Input Device**. On that page you can click **Test microphone** to check it works.
- Mac only: if macOS asks whether Steam may use the microphone, click **Allow**.

### Part B: every test session

1. **Open Steam on both machines** and wait until it finishes logging in. You should see your friends list or
   library, not a login screen.
2. **Start the game:**
   - Windows: open the folder you extracted (the one with `TheLastFireMage.exe`, `steam_api64.dll`,
     `steam_appid.txt` …). Double-click **`TheLastFireMage.console.exe`**. A black log window opens next to the
     game, which helps if something goes wrong. If Windows shows "Windows protected your PC", click
     **More info → Run anyway**.
   - Mac: double-click `build/macos/TheLastFireMage.app`, or `TheLastFireMage.command` for a log window.
     Allow microphone access if asked.
3. **Check the menu** on both machines. Under the name field it should say
   **"Steam: Logged in as <your Steam name>"**, and the Steam buttons should be clickable.
   If it says "Steam not available …", close the game, make sure Steam is fully logged in, and start the game
   again. Then see section 8.
4. **Machine A (host):** type a player name and click **Host Steam lobby**. After a second or two the menu closes
   and you're standing on the map.
5. **Machine B (joiner):** type a player name, then:
   - **Lobby list (recommended):** click **Refresh lobby list**. Wait a couple of seconds; "<A's Steam name>'s
     game (1/6)" appears in the box. Select it and click **Join selected lobby** (or double-click it). If the list
     is empty, wait 5 seconds and refresh again. Only lobbies from *our* game are listed, never other
     people's Spacewar lobbies.
   - **Invite (needs A3):** on A, press **Esc → Invite Steam friends**. The Steam overlay should open with your
     friends list. Click **Invite** next to B. On B, accept the invite in the Steam chat window.
     Two caveats: **B must already have our game running**, otherwise Steam launches the real Spacewar instead;
     and the overlay often doesn't appear for games started by double-clicking. If nothing opens, use the lobby list.
6. **You're connected** when both of you see the other capsule with a name above it. Press **F3**: it shows
   `Mode: Steam`, `Peers: 1` and a ping.
7. **Talk:** walk close to each other, **hold V** and speak. The other machine should hear you, and "SPEAKING"
   appears above your head. Then run the checklist in section 6.
8. **Swap roles:** both press **Esc → Leave game**. Now B clicks **Host Steam lobby** and A joins. Doing this
   tests Windows-hosts and Mac-hosts.
9. Up to 6 players (6 machines, 6 accounts) can join the same lobby.

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
| Steam says the account logged in somewhere else | One account can only be logged in on one computer at a time. Use account 1 on the Mac and account 2 on the PC |
| Steam overlay / invite dialog doesn't open | Normal for games started by double-clicking with app 480. Use **Refresh lobby list** instead |
| Lobby list is empty | The host must be in a lobby first (Host Steam lobby). Click Refresh again after a few seconds. Both machines must run the same build |
| Invite accepted but Spacewar opened | The game wasn't running on the joiner. Start our game first, then accept, or use the lobby list |
| Connected, but no voice | On Mac: check the microphone permission (section 4). In Steam mode, check **Steam → Settings → Voice** uses the right mic (Steam voice ignores the in-game Mic picker). Make sure you're holding **V** with the game window focused. F3: does `sent` go up on the speaker's machine and `received` go up on the listener's? |
| Voice works close up but never gets quiet | Check F3 says `Falloff: full <= 3 m, silent >= 25 m`. Distance is measured between players, not cameras |
| Mic meter doesn't move | Pick another device in **Mic** (Esc menu). On Mac, check **Privacy & Security → Microphone** lists the game and it's on. On Windows, check **Settings → Privacy & security → Microphone**: "Microphone access" and **"Let desktop apps access your microphone"** must be on. The meter uses the in-game Mic choice, while Steam voice uses Steam's mic setting |
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
