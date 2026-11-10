#!/usr/bin/env python3
"""Copy the chosen library (CC0) files from downloaded packs into assets/audio/. Owner: S18.

Usage: python3 tools/audio/import_library.py PACKS_DIR
PACKS_DIR holds one sub-folder per downloaded pack (see LIBRARY below and docs/audio/CREDITS_AUDIO.md for URLs).
WAVs are converted to 16-bit, trimmed, peak-normalised to -1 dBFS and faded; OGGs are copied as-is (no encoder here).
Re-runnable: it only (re)writes the files listed below. Run tools/audio/build_bank.py afterwards.
"""
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wavio  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "the-last-fire-mage", "assets", "audio")

# "@kenney/..." = docs/kenneyaudio (user-supplied Kenney packs), "@human/..." = docs/humanmusic (user's own music).
SPECIAL = {"@kenney/": os.path.join(ROOT, "docs", "kenneyaudio"), "@human/": os.path.join(ROOT, "docs", "humanmusic")}
IMPACT = "@kenney/kenney_impact-sounds/Audio/%s_%03d.ogg"
UI = "@kenney/kenney_interface-sounds/Audio/%s_%03d.ogg"
# (cue, folder under assets/audio, [source paths relative to PACKS_DIR], options)
# options: mono (default True), start/end seconds, loop, peak (dBFS)
LIBRARY = [
    ("step_villager", "movement", [IMPACT % ("footstep_concrete", i) for i in range(5)], {}),
    ("step_mage", "movement", ["kenney_rpg/OGG/footstep0%d.ogg" % i for i in range(8)], {}),
    ("mage_ember", "movement", ["firecrackle/fire-1.wav"] * 3, {"slices": [(0.1, 0.45), (1.0, 1.35), (2.0, 2.35)]}),
    ("jump_takeoff", "movement", ["kenney_rpg/OGG/cloth%d.ogg" % i for i in (1, 2, 3, 4)], {}),
    ("land_soft", "movement", [IMPACT % ("impactSoft_medium", i) for i in range(5)], {}),
    ("land_hard", "movement", [IMPACT % ("impactSoft_heavy", i) for i in range(5)], {}),
    ("mantle", "movement", ["kenney_rpg/OGG/clothBelt.ogg", "kenney_rpg/OGG/clothBelt2.ogg",
                            "kenney_rpg/OGG/handleSmallLeather.ogg"], {}),
    ("fall_thud", "movement", [IMPACT % ("impactPunch_heavy", i) for i in range(5)], {}),
    ("hide_enter", "interact", ["kenney_rpg/OGG/creak1.ogg", "kenney_rpg/OGG/creak2.ogg"], {}),
    ("hide_exit", "interact", ["kenney_rpg/OGG/creak3.ogg", "kenney_rpg/OGG/doorOpen_1.ogg",
                               "kenney_rpg/OGG/doorOpen_2.ogg"], {}),
    ("carry_pickup", "interact", ["kenney_rpg/OGG/handleSmallLeather2.ogg", "kenney_rpg/OGG/cloth4.ogg"], {}),
    ("carry_drop", "interact", [IMPACT % ("impactWood_light", i) for i in range(5)], {}),
    ("knife_swing", "mage", ["swishes/swishes/swish-%d.wav" % i for i in range(1, 14)], {"peak": -3.0}),
    ("ignite_whoosh", "mage", ["flame/flame.ogg", "rd80/spell_fire_01.ogg"], {}),
    ("ignite_loop", "mage", ["firecrackle/fire-1.wav"], {"loop": True, "peak": -6.0}),
    ("fire_wave_cast", "mage", ["rd80/spell_fire_0%d.ogg" % i for i in (2, 3, 4, 5, 6)], {}),
    ("hit_flesh", "mage", [IMPACT % ("impactPunch_medium", i) for i in range(5)], {}),
    ("kill_sting", "mage", ["rd100/gong_01.ogg", "rd100/gong_02.ogg"], {}),
    ("wave_ready", "mage", ["rd100/bell_01.ogg"], {}),
    ("tier_up", "mage", ["rd80/item_gem_0%d.ogg" % i for i in (1, 2, 3, 4)], {}),
    ("villager_hurt", "villager", ["rd80/creature_hurt_01.ogg", "rd80/creature_hurt_02.ogg"], {}),
    ("villager_death", "villager", ["rd80/creature_die_01.ogg"], {}),
    ("dread_heartbeat", "dread", ["heartbeat/heartbeat_slow_0.wav"], {"loop": True, "peak": -2.0}),
    ("storm_crackle_loop", "storm", ["firecrackle/fire-1.wav"], {"loop": True, "peak": -3.0}),
    ("storm_wind_loop", "storm", ["wind/wind_woosh_loop.ogg"], {}),
    ("storm_warning_bell", "storm", [IMPACT % ("impactBell_heavy", 0)], {}),
    ("storm_rumble_hit", "storm", ["cannon/cannon_hit_wall_no_splash.ogg", "cannon/cannon_fire_1.ogg"], {}),
    ("amb_gulls", "ambience", ["gulls/Seagull_Ambient_%d.wav" % i for i in range(1, 8)], {"peak": -4.0}),
    ("flame_crackle_loop", "ambience", ["firecrackle/fire-1.wav"], {"loop": True, "peak": -6.0}),
    # Freesound CC0 HQ previews (mp3, converted with macOS afconvert), cut into single cluck phrases.
    ("chicken_cluck", "interact", ["chickens/Breviceps_456803.mp3",
                                   "chickens/chanyatenn_424076.mp3", "chickens/flumpytripod_830091.mp3",
                                   "chickens/MBPL_668803.mp3"],
     {"phrases": 3, "min": 0.35, "max": 1.6, "peak": -7.0}),
    ("chicken_squawk", "interact", ["chickens/roboroo_494613.mp3"], {"phrases": 5, "min": 0.3, "max": 1.2, "peak": -4.0}),
    ("ui_click", "ui", [UI % ("click", i) for i in range(1, 6)], {}),
    ("ui_confirm", "ui", [UI % ("confirmation", 1)], {}),
    ("locate_pulse", "mage", [UI % ("pluck", 1)], {}),
    ("music_cheer", "music", ["@human/maintheme.mp3"], {}),
]


def _remove_old_takes(cue):
    """Delete earlier takes of a cue (any folder except placeholder/) so a smaller new set leaves no strays."""
    for dirpath, _dirs, files in os.walk(ASSETS):
        if os.path.relpath(dirpath, ASSETS).split(os.sep)[0] == "placeholder":
            continue
        for f in files:
            base, ext = os.path.splitext(f)
            if ext in (".ogg", ".wav", ".mp3") and re.match(r"^%s(_\d\d)?$" % re.escape(cue), base):
                os.remove(os.path.join(dirpath, f))
                if os.path.exists(os.path.join(dirpath, f + ".import")):
                    os.remove(os.path.join(dirpath, f + ".import"))


def _import_phrases(cue, dest_dir, sources, opt):
    """Cut up to opt["phrases"] sound phrases (events joined across gaps < 0.3 s, length min..max s) from each
    source and write them as numbered takes. mp3 sources are decoded with macOS `afconvert`."""
    n = 0
    for src in sources:
        if src.endswith(".mp3"):
            wav = src[:-4] + ".wav"
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", src, wav], check=True)
            src = wav
        rate, chans = wavio.read_wav(src)
        for start, end in wavio.phrases(chans[0], rate, opt["min"], opt["max"])[:opt["phrases"]]:
            take = wavio.process(chans, rate, peak_db=opt.get("peak", -1.0), start=max(0.0, start - 0.03),
                                 end=min(len(chans[0]) / rate, end + 0.08), fade_ms=15.0)
            n += 1
            wavio.write_wav(os.path.join(dest_dir, "%s_%02d.wav" % (cue, n)), rate, take)
    return n


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    packs = sys.argv[1]
    for cue, folder, sources, opt in LIBRARY:
        dest_dir = os.path.join(ASSETS, folder)
        os.makedirs(dest_dir, exist_ok=True)
        slices = opt.get("slices")
        _remove_old_takes(cue)
        if "phrases" in opt:
            _import_phrases(cue, dest_dir, [os.path.join(packs, r) for r in sources], opt)
            continue
        for n, rel in enumerate(sources, 1):
            src = os.path.join(packs, rel)
            for prefix, base in SPECIAL.items():
                if rel.startswith(prefix):
                    src = os.path.join(base, rel[len(prefix):])
            name = cue if len(sources) == 1 else "%s_%02d" % (cue, n)
            if rel.endswith((".ogg", ".mp3")):
                shutil.copyfile(src, os.path.join(dest_dir, name + os.path.splitext(rel)[1]))
                continue
            rate, chans = wavio.read_wav(src)
            start, end = slices[n - 1] if slices else (None, None)
            chans = wavio.process(chans, rate, mono=opt.get("mono", True), peak_db=opt.get("peak", -1.0),
                                  start=start, end=end, loop=opt.get("loop", False))
            wavio.write_wav(os.path.join(dest_dir, name + ".wav"), rate, chans)
        print("[audio] %-20s %d file(s) -> assets/audio/%s" % (cue, len(sources), folder))


if __name__ == "__main__":
    main()
