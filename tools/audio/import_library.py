#!/usr/bin/env python3
"""Copy the chosen library (CC0) files from downloaded packs into assets/audio/. Owner: S18.

Usage: python3 tools/audio/import_library.py PACKS_DIR
PACKS_DIR holds one sub-folder per downloaded pack (see LIBRARY below and docs/audio/CREDITS_AUDIO.md for URLs).
WAVs are converted to 16-bit, trimmed, peak-normalised to -1 dBFS and faded; OGGs are copied as-is (no encoder here).
Re-runnable: it only (re)writes the files listed below. Run tools/audio/build_bank.py afterwards.
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wavio  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "the-last-fire-mage", "assets", "audio")

# (cue, folder under assets/audio, [source paths relative to PACKS_DIR], options)
# options: mono (default True), start/end seconds, loop, peak (dBFS)
LIBRARY = [
    ("step_villager", "movement", ["fantozzi/Fantozzi-footsteps/ogg/Fantozzi-Stone%s%d.ogg" % (s, i) for s in "LR" for i in (1, 2, 3)], {}),
    ("step_mage", "movement", ["kenney_rpg/OGG/footstep0%d.ogg" % i for i in range(8)], {}),
    ("mage_ember", "movement", ["firecrackle/fire-1.wav"] * 3, {"slices": [(0.1, 0.45), (1.0, 1.35), (2.0, 2.35)]}),
    ("jump_takeoff", "movement", ["kenney_rpg/OGG/cloth%d.ogg" % i for i in (1, 2, 3, 4)], {}),
    ("land_soft", "movement", ["kenney_rpg/OGG/footstep08.ogg", "kenney_rpg/OGG/footstep09.ogg",
                               "kenney_rpg/OGG/dropLeather.ogg"], {}),
    ("land_hard", "movement", ["rd80/stones_0%d.ogg" % i for i in (1, 2, 3, 4)], {}),
    ("mantle", "movement", ["kenney_rpg/OGG/clothBelt.ogg", "kenney_rpg/OGG/clothBelt2.ogg",
                            "kenney_rpg/OGG/handleSmallLeather.ogg"], {}),
    ("fall_thud", "movement", ["rd100/hit_0%d.ogg" % i for i in (1, 2, 3, 4)], {}),
    ("hide_enter", "interact", ["kenney_rpg/OGG/creak1.ogg", "kenney_rpg/OGG/creak2.ogg"], {}),
    ("hide_exit", "interact", ["kenney_rpg/OGG/creak3.ogg", "kenney_rpg/OGG/doorOpen_1.ogg",
                               "kenney_rpg/OGG/doorOpen_2.ogg"], {}),
    ("carry_pickup", "interact", ["kenney_rpg/OGG/handleSmallLeather2.ogg", "kenney_rpg/OGG/cloth4.ogg"], {}),
    ("carry_drop", "interact", ["kenney_rpg/OGG/dropLeather.ogg"], {}),
    ("knife_swing", "mage", ["swishes/swishes/swish-%d.wav" % i for i in range(1, 14)], {"peak": -3.0}),
    ("ignite_whoosh", "mage", ["flame/flame.ogg", "rd80/spell_fire_01.ogg"], {}),
    ("ignite_loop", "mage", ["firecrackle/fire-1.wav"], {"loop": True, "peak": -6.0}),
    ("fire_wave_cast", "mage", ["rd80/spell_fire_0%d.ogg" % i for i in (2, 3, 4, 5, 6)], {}),
    ("hit_flesh", "mage", ["kenney_rpg/OGG/knifeSlice.ogg", "kenney_rpg/OGG/knifeSlice2.ogg",
                           "kenney_rpg/OGG/chop.ogg"], {}),
    ("kill_sting", "mage", ["rd100/gong_01.ogg", "rd100/gong_02.ogg"], {}),
    ("wave_ready", "mage", ["rd100/bell_01.ogg"], {}),
    ("tier_up", "mage", ["rd80/item_gem_0%d.ogg" % i for i in (1, 2, 3, 4)], {}),
    ("villager_hurt", "villager", ["rd80/creature_hurt_01.ogg", "rd80/creature_hurt_02.ogg"], {}),
    ("villager_death", "villager", ["rd80/creature_die_01.ogg"], {}),
    ("dread_heartbeat", "dread", ["heartbeat/heartbeat_slow_0.wav"], {"loop": True, "peak": -2.0}),
    ("storm_crackle_loop", "storm", ["firecrackle/fire-1.wav"], {"loop": True, "peak": -3.0}),
    ("storm_wind_loop", "storm", ["wind/wind_woosh_loop.ogg"], {}),
    ("storm_warning_bell", "storm", ["bell/bell_ding1.wav"], {"mono": False}),
    ("storm_rumble_hit", "storm", ["cannon/cannon_hit_wall_no_splash.ogg", "cannon/cannon_fire_1.ogg"], {}),
    ("amb_gulls", "ambience", ["gulls/Seagull_Ambient_%d.wav" % i for i in range(1, 8)], {"peak": -4.0}),
    ("flame_crackle_loop", "ambience", ["firecrackle/fire-1.wav"], {"loop": True, "peak": -6.0}),
    ("ui_click", "ui", ["kenney_rpg/OGG/metalClick.ogg"], {}),
    ("ui_confirm", "ui", ["rd100/switch_01.ogg"], {}),
]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    packs = sys.argv[1]
    for cue, folder, sources, opt in LIBRARY:
        dest_dir = os.path.join(ASSETS, folder)
        os.makedirs(dest_dir, exist_ok=True)
        slices = opt.get("slices")
        for n, rel in enumerate(sources, 1):
            src = os.path.join(packs, rel)
            name = cue if len(sources) == 1 else "%s_%02d" % (cue, n)
            if rel.endswith(".ogg"):
                shutil.copyfile(src, os.path.join(dest_dir, name + ".ogg"))
                continue
            rate, chans = wavio.read_wav(src)
            start, end = slices[n - 1] if slices else (None, None)
            chans = wavio.process(chans, rate, mono=opt.get("mono", True), peak_db=opt.get("peak", -1.0),
                                  start=start, end=end, loop=opt.get("loop", False))
            wavio.write_wav(os.path.join(dest_dir, name + ".wav"), rate, chans)
        print("[audio] %-20s %d file(s) -> assets/audio/%s" % (cue, len(sources), folder))


if __name__ == "__main__":
    main()
