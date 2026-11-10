# Audio cue sheet (S18)
The living checklist of every sound cue. **Code plays cues by name only** (`Sfx.play_3d(&"step_villager", pos)`),
so any file can be swapped without touching code.

How a cue finds its file (`tools/audio/build_bank.py` writes `game/audio/sound_bank.tres`):
1. Any file under `the-last-fire-mage/assets/audio/` (not `placeholder/`) named `<cue>.ogg|wav|mp3` or
   `<cue>_01.ogg`, `<cue>_02.ogg`... Several numbered takes become one `AudioStreamRandomizer` (random pick + pitch).
2. Otherwise `assets/audio/placeholder/<cue>.wav` (synthesised by `tools/audio/gen_placeholders.py`).

To replace a cue: drop the new file(s) in `assets/audio/<folder>/`, delete the old takes of that cue, run
`python3 tools/audio/build_bank.py`, then the Godot import. Update **Source/Status** here and `CREDITS_AUDIO.md`.

Columns are parsed by the tools and the test: keep the first five columns' format (`cue` in backticks, Loop = yes/no).
Source: `placeholder` (synth), `library` (see CREDITS_AUDIO.md), `AI` (prompt in AI_AUDIO_REQUESTS.md; placeholder until
the file is dropped in). Status: `placeholder`, `library`, `needs AI`, `final`.

| Cue | Trigger | Who hears | Bus | Loop | Source | Status |
|---|---|---|---|---|---|---|
| `step_villager` | villager footfall (stride by distance; sprint 14 m, walk 7 m, crouch/still 0) | everyone in range (3D) | SFX | no | library: Fantozzi stone x6 | library |
| `step_mage` | mage footfall (heavier, range x1.3) | everyone in range (3D) | SFX | no | library: Kenney RPG footsteps x8 | library |
| `mage_ember` | every 3rd mage step, ember crackle | everyone in range (3D) | SFX | no | library: OGA fire crackling slices x3 | library |
| `jump_takeoff` | player leaves the ground (10 m) | in range (3D) | SFX | no | library: Kenney cloth x4 | library |
| `land_soft` | landing after a short air time (10 m) | in range (3D) | SFX | no | library: Kenney footstep/leather x3 | library |
| `land_hard` | landing after a long fall (12 m, louder) | in range (3D) | SFX | no | library: rubberduck stones x4 | library |
| `mantle` | mantle starts (8 m) | in range (3D) | SFX | no | library: Kenney belt/leather x3 | library |
| `fall_thud` | `player_damaged` cause `fall` | in range (3D) | SFX | no | library: rubberduck hits x4 | library |
| `hide_enter` | a hide spot's `hidden_count` goes up | in range (3D) | SFX | no | library: Kenney creak x2 | library |
| `hide_exit` | a hide spot's `hidden_count` goes down | in range (3D) | SFX | no | library: Kenney creak/door x3 | library |
| `carry_pickup` | `carry_changed` to something | in range (3D) | SFX | no | library: Kenney leather/cloth x2 | library |
| `carry_drop` | `carry_changed` to nothing | in range (3D) | SFX | no | library: Kenney drop leather x1 | library |
| `chicken_squawk` | a mage comes within 8 m of a chicken | in range (3D, 12 m) | SFX | no | placeholder | placeholder |
| `knife_swing` | mage knife cast (cooldown starts) | in range (3D) | SFX | no | library: artisticdude swishes x13 | library |
| `ignite_whoosh` | mage Ignite starts | in range (3D) | SFX | no | library: themightyglider flame + rubberduck fire spell | library |
| `ignite_loop` | while the knife burns | in range (3D, on the mage) | SFX | yes | library: OGA fire crackling | library |
| `fire_wave_cast` | mage Fire Wave cast | in range (3D) | SFX | no | library: rubberduck fire spells x5 | library |
| `locate_pulse` | mage Locate cast | local mage only (2D) | UI | no | placeholder | placeholder |
| `hit_flesh` | `player_damaged` by knife/ignite/fire wave | in range (3D, victim) | SFX | no | library: Kenney knife slice/chop x3 | library |
| `kill_sting` | local mage killed someone | local mage only (2D) | Stingers | no | library: rubberduck gong x2 | library |
| `wave_ready` | Fire Wave cooldown reached 0 | local mage only (2D) | UI | no | library: rubberduck bell | library |
| `tier_up` | `power_changed` tier went up | mage 2D, others 3D at mage (30 m) | Stingers | no | library: rubberduck gem x4 | library |
| `mage_aura_loop` | always on a mage, louder/farther per power tier | in range (3D, on the mage) | SFX | yes | AI | needs AI |
| `villager_hurt` | villager damaged (not fall/storm) | in range (3D) | SFX | no | library: rubberduck creature hurt x2 (AI voice later) | library |
| `villager_death` | villager died | in range (3D) | SFX | no | library: rubberduck creature die x1 (AI voice later) | library |
| `dread_drone` | dread stem: mage in LOS within 40 m | local alive villager (2D) | Dread | yes | AI | needs AI |
| `dread_heartbeat` | mage in LOS within 25 m, faster when nearer | local alive villager (2D) | Dread | yes | library: bart heartbeat slow | library |
| `dread_strings` | dread stem: mage in LOS within 15 m | local alive villager (2D) | Dread | yes | AI | needs AI |
| `dread_chase` | dread stem: after being spotted, mage close in LOS | local alive villager (2D) | Dread | yes | AI | needs AI |
| `dread_spotted` | LOS starts inside 20 m, or the mage ignites nearby | local alive villager (2D) | Stingers | no | AI | needs AI |
| `hunter_bed` | local mage's power-scaled bed | local mage (2D) | Dread | yes | AI | needs AI |
| `ghost_bed` | local player is dead / spectating | local dead (2D) | Dread | yes | AI | needs AI |
| `music_cheer` | music stem: cheerful seaside folk (fades out as dread rises) | everyone (2D) | Music | yes | AI | needs AI |
| `music_dark` | music stem: same tune, minor/detuned (fades in) | everyone (2D) | Music | yes | AI | needs AI |
| `music_drone` | music stem: low drones (high dread) | everyone (2D) | Music | yes | AI | needs AI |
| `stinger_round_start` | phase ROLE_REVEAL | everyone (2D) | Stingers | no | AI | needs AI |
| `stinger_victory` | `round_ended`, my team won | local (2D) | Stingers | no | AI | needs AI |
| `stinger_defeat` | `round_ended`, my team lost | local (2D) | Stingers | no | AI | needs AI |
| `storm_roar_loop` | wall of fire at the nearest ring point | everyone (3D, little occlusion) | SFX | yes | AI | needs AI |
| `storm_crackle_loop` | crackle layer at the ring point (25 m) | everyone (3D) | SFX | yes | library: OGA fire crackling | library |
| `storm_wind_loop` | listener is outside the safe zone | local (2D) | Ambience | yes | library: sketchman3 wind woosh loop | library |
| `storm_warning_bell` | `firestorm_warning`, pitched a whole step up per stage | everyone (2D) | Stingers | no | library: pwl bell ding (AI rune bell later) | library |
| `storm_stage_sweep` | `firestorm_stage` ring contraction | everyone (2D) | Stingers | no | placeholder | placeholder |
| `storm_rumble_hit` | `firestorm_stage` | everyone (2D) | Stingers | no | library: thimras cannon hits x2 | library |
| `storm_damage_tick` | local `player_damaged` cause `firestorm` | local (2D) | SFX | no | placeholder | placeholder |
| `amb_ocean_loop` | always, placed on the coast side (compass) | everyone (3D, far) | Ambience | yes | placeholder (OGA flac in MANUAL_DOWNLOADS) | placeholder |
| `amb_town_loop` | daytime town bed, thins with dread | everyone (2D) | Ambience | yes | AI | needs AI |
| `amb_gulls` | random gull calls around the listener, thin with dread / near storm | local (3D) | Ambience | no | library: rango-mango seagulls x7 | library |
| `flame_crackle_loop` | torch / candles / lantern props (nearest 8) | in range (3D, 6 m) | SFX | yes | library: OGA fire crackling | library |
| `ui_click` | menu button (for the menu card) | local (2D) | UI | no | library: Kenney metal click | library |
| `ui_confirm` | menu confirm (for the menu card) | local (2D) | UI | no | library: rubberduck switch | library |
