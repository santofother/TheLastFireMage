#!/usr/bin/env python3
"""Write game/audio/sound_bank.tres from docs/audio/CUE_SHEET.md + the files in assets/audio/. Owner: S18.

Usage: python3 tools/audio/build_bank.py        (then run the Godot --import once so new files get .import files)
For each cue in the sheet: real files `<cue>.ext` / `<cue>_NN.ext` anywhere under assets/audio/ (except placeholder/)
win over `placeholder/<cue>.wav`. Several takes -> AudioStreamRandomizer (random take, pitch and volume variation).
Loop cues use their first take; SoundBank turns looping on at load time, so no .import edits are needed.
Exit code 1 if a cue has no file at all (run gen_placeholders.py first).
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROJECT = os.path.join(ROOT, "the-last-fire-mage")
ASSETS = os.path.join(PROJECT, "assets", "audio")
SHEET = os.path.join(ROOT, "docs", "audio", "CUE_SHEET.md")
OUT = os.path.join(PROJECT, "game", "audio", "sound_bank.tres")
EXTS = (".ogg", ".wav", ".mp3")
# TUNE: variation per take group. random_pitch is Godot's multiplier (1.1 = up to +/-10 %).
PITCH = {"step_villager": 1.12, "step_mage": 1.1, "knife_swing": 1.12, "amb_gulls": 1.15}
DEFAULT_PITCH = 1.06
VOLUME_VARIATION_DB = 1.5


def sheet_cues():
    out = []
    for line in open(SHEET, encoding="utf-8"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        m = re.match(r"`([a-z0-9_]+)`$", cells[0]) if len(cells) >= 5 else None
        if m:
            out.append((m.group(1), cells[4].lower() == "yes"))
    return out


def scan():
    found = {}
    for dirpath, _dirs, files in os.walk(ASSETS):
        rel_dir = os.path.relpath(dirpath, ASSETS)
        if rel_dir.split(os.sep)[0] == "placeholder":
            continue
        for f in files:
            base, ext = os.path.splitext(f)
            if ext.lower() not in EXTS:
                continue
            m = re.match(r"^(.*?)(?:_(\d\d))?$", base)
            found.setdefault(m.group(1), []).append(os.path.join(dirpath, f))
    return {k: sorted(v) for k, v in found.items()}


def res_path(abs_path):
    return "res://" + os.path.relpath(abs_path, PROJECT).replace(os.sep, "/")


def main():
    cues = sheet_cues()
    files = scan()
    ext, subs, entries, loops, placeholders, missing = [], [], [], [], [], []
    ext_id = {}

    def ext_ref(path):
        if path not in ext_id:
            ext_id[path] = "a%d" % (len(ext_id) + 1)
            ext.append('[ext_resource type="AudioStream" path="%s" id="%s"]' % (res_path(path), ext_id[path]))
        return 'ExtResource("%s")' % ext_id[path]

    for cue, is_loop in cues:
        takes = files.get(cue, [])
        if not takes:
            ph = os.path.join(ASSETS, "placeholder", cue + ".wav")
            if not os.path.exists(ph):
                missing.append(cue)
                continue
            takes = [ph]
            placeholders.append(cue)
        if is_loop:
            loops.append(cue)
            entries.append('&"%s": %s' % (cue, ext_ref(takes[0])))
        elif len(takes) == 1:
            entries.append('&"%s": %s' % (cue, ext_ref(takes[0])))
        else:
            sid = "rand_" + cue
            lines = ['[sub_resource type="AudioStreamRandomizer" id="%s"]' % sid,
                     "random_pitch = %s" % PITCH.get(cue, DEFAULT_PITCH),
                     "random_volume_offset_db = %s" % VOLUME_VARIATION_DB,
                     "streams_count = %d" % len(takes)]
            for i, t in enumerate(takes):
                lines += ["stream_%d/stream = %s" % (i, ext_ref(t)), "stream_%d/weight = 1.0" % i]
            subs.append("\n".join(lines))
            entries.append('&"%s": SubResource("%s")' % (cue, sid))
    if missing:
        print("[audio] ERROR: no file for cues: %s (run gen_placeholders.py)" % ", ".join(missing))
        sys.exit(1)

    def psa(items):
        return "PackedStringArray(%s)" % ", ".join('"%s"' % i for i in items)

    text = ['[gd_resource type="Resource" script_class="SoundBank" format=3]', "",
            '[ext_resource type="Script" path="res://game/audio/sound_bank.gd" id="script"]']
    text += ext + [""] + [s + "\n" for s in subs]
    text += ["[resource]", 'script = ExtResource("script")',
             "streams = {\n" + ",\n".join(entries) + "\n}",
             "loops = " + psa(loops), "placeholder_cues = " + psa(placeholders), ""]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(text))
    print("[audio] sound_bank.tres: %d cues (%d placeholder, %d loops)" % (len(cues), len(placeholders), len(loops)))


if __name__ == "__main__":
    main()
