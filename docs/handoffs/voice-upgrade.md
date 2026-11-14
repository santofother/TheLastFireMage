# voice-upgrade — proximity chat v3, mage dread tweaks, smooth remote players
Agent: Claude Opus 5.5 (head engineer, user request) · branch `voice-upgrade`
Result: DONE (needs an online playtest to confirm the feel)

## What exists now
- `core/voice_manager.gd`: transport v3. RPC `_voice_packet(seq, data, codec, red, group)`, UNRELIABLE (was
  unreliable_ordered, which dropped every reordered packet). `red` = 8 kHz ADPCM copy of chunk seq-1 (FEC,
  ~100 kbit/s while talking). Receiver: reorder by seq, rebuild lost chunks from `red`, conceal the rest
  (mirrored repeat, fades out, max 80 ms), adaptive jitter buffer 60..250 ms from measured arrival jitter.
  F3 overlay shows recovered / late / concealed / buffer ms. `--voice-no-fec` turns redundancy off.
- `game/power/power_manager.gd`: mage voice effect removed (user: "weird audio bits"). VoiceFx API kept, unused.
- `game/audio/`: no dread layers or "spotted" stinger during ROLE_REVEAL / HEAD_START; no stinger for the first
  3 s of HUNT. `DreadTracker.settle`: after 8 s of continuous dread the layers fade to 60 % (-40 %), back to
  full after 10 s calm. Tunables `dread_settle_*`, `dread_release_grace` in AudioTuning.
- `game/player/player.gd` + `player.tscn`: Sync replicates `net_state` [time, pos, quat] instead of raw
  position/rotation. Remote peers render 100 ms in the past, interpolating (extrapolate ≤150 ms, snap on
  jumps > 6 m and on teleport). Visuals read speed from this smooth motion, so animations no longer stutter.

## How to test
- `tools/run_tests.sh`. New checks: voice_codec (reorder/FEC/PLC), audio (head start silence, settle).
- Manual (user, two machines over Steam): talk while moving apart; F3 → "Voice loss" line. Watch another
  player run/jump: animation should be smooth. Head start: villagers near the frozen mage hear no stinger.

## Contract change requested
- Done as head engineer: AGENTS.md / ARCHITECTURE.md voice RPC line, GDD mage-voice line updated.

## Known issues / next steps
- Remote bodies are drawn 100 ms in the past (also on the server). Bump validation uses `Player.net_position()`
  (newest snapshot); other server range checks are loose enough, but use net_position() if one feels off.
- Voice upload roughly 1.5x while talking (FEC). If bandwidth hurts on the host, try `--voice-no-fec`.
- Remote copies ignore in-flight snapshots far from a teleport target for 1 s (else they slid back to pre-teleport spots).
- Pre-existing flake (also on main): match_test sometimes finds a villager ~0.5 m off its spawn (owner drift on landing).
