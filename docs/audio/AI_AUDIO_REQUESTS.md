# AI audio requests (S18)
Cues the free libraries didn't cover. Each has a working synthesised placeholder; generate the file, drop it in the
folder given, run `python3 tools/audio/build_bank.py` + the Godot import, and change the cue's row in
`CUE_SHEET.md` to `AI` / `final`.
**Steam requires disclosing AI-generated content**: every cue below is AI once you replace it. List them in the
Steamworks "AI Generated Content" survey (pre-generated audio).

Format for all: 44.1 kHz. SFX = mono WAV 16-bit (or OGG). Music / beds / stingers = stereo OGG ~q4. Loops must loop
seamlessly (no fade at the ends; the generator's "loop" option or cut on a bar line). Name exactly as shown.

## Music: dark layers under the main theme
`music_cheer` is now the user's own main theme (`assets/audio/music/music_cheer.mp3`, ~118 s, D-ish folk). These two fade
in under/instead of it as the match gets scarier. They loop on their own, so length doesn't have to match the theme,
but ideally use the theme's key and tempo. Folder: `assets/audio/music/`.

| File | Prompt |
|---|---|
| `music_dark.ogg` | Dark, slow re-interpretation of a cheerful seaside folk theme: detuned accordion and bowed fiddle pads, sparse, uneasy and haunted, minor key, no drums, no plucked or clicking percussion, seamless 60 s loop, no vocals. |
| `music_drone.ogg` | Low ominous drones, sub-bass swell, distant bowed metal, faint choir breathing, slow pulsing, horror ambience, seamless 30 s loop, no melody, no percussion. |

## Dread layers (heard only by a villager who can SEE the mage)
Same length for the three stems (8 or 16 s), loop, stereo. Folder: `assets/audio/dread/`.

| File | Prompt |
|---|---|
| `dread_drone.ogg` | Very low tense drone, dark cello cluster and sub rumble, slow beating, horror game "something is watching you", seamless 8 s loop. |
| `dread_strings.ogg` | Dissonant high string cluster tremolo, tritones and minor seconds, scraping col legno texture, rising panic, horror, seamless 8 s loop, no percussion. |
| `dread_chase.ogg` | Driving chase ostinato, low staccato strings and pounding taiko pulse at 120 BPM, frantic horror pursuit, seamless 8 s loop. |
| `dread_spotted.ogg` | One-shot horror stinger, 1.5 s: sudden orchestral cluster stab with a fiery whoosh and a sharp intake of breath, "you've been seen", not a cheap jumpscare scream. |
| `hunter_bed.ogg` | Predator's ambience for the fire mage, deep breathing furnace, low growl, embers crackling, menacing but calm, seamless 12 s loop. |
| `ghost_bed.ogg` | Ethereal afterlife bed, muffled distant town, airy pads, soft wind through an empty room, melancholic, seamless 16 s loop. |

## Stingers
Stereo OGG, one-shot. Folder: `assets/audio/stingers/`.

| File | Prompt |
|---|---|
| `stinger_round_start.ogg` | 2 s: low brass horn call and a rune-bell strike, ominous "the hunt begins", folk-fantasy. |
| `stinger_victory.ogg` | 3 s: triumphant folk flourish, fiddle and accordion rising to a D major chord, celebratory. |
| `stinger_defeat.ogg` | 3 s: deflated minor folk phrase, slow accordion sigh falling to D minor, a single bell toll. |

## Mage, storm, town
Folder in brackets.

| File | Loop | Prompt |
|---|---|---|
| `mage_aura_loop.wav` [mage] | yes, 3 s, mono | Low roaring fire aura around a sorcerer, breathing furnace, soft crackles, magical hum. |
| `storm_roar_loop.ogg` [storm] | yes, 6 s, mono | Wall of fire roaring, huge wildfire front, deep rumble with crackle, wind-driven flames, constant, no bursts. |
| `storm_warning_bell.wav` [storm] | no, 2.5 s, stereo | Deep magical rune bell, single strike with shimmering fire overtones, long ringing tail, fantasy warning. (Pitched up per stage in code: keep it around C4.) |
| `storm_stage_sweep.wav` [storm] | no, 2 s, mono | Downward magical sweep, a fire ring contracting, whooshing flames pulled inward, ending in a thump. |
| `storm_damage_tick.wav` [storm] | no, 0.2 s, mono | Short sizzle burn, skin touched by flame, quick hiss. |
| `amb_town_loop.ogg` [ambience] | yes, 30 s, stereo | Daytime seaside town ambience, distant chatter, cart wheels on cobblestones, harbour bells, no music, peaceful. |
| `amb_ocean_loop.ogg` [ambience] | yes, 20 s, stereo | Gentle waves on a pebble beach, close but calm, seamless loop. (Or use the CC0 file in MANUAL_DOWNLOADS.md.) |
| `chicken_squawk_01..04.wav` [interact] | no, mono | Startled chicken squawk and wing flap, short, panicked. |
| `locate_pulse.wav` [mage] | no, 1 s, mono | Magical sonar pulse, warm fire ping that echoes outward. |
| `villager_hurt_01..04.wav` [villager] | no, mono | Small cartoonish villager "oof"/yelp of pain, cute, non-gory, varied voices. |
| `villager_death_01..02.wav` [villager] | no, mono | Small cartoonish villager defeated cry, short, non-gory. |
