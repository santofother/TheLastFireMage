#!/usr/bin/env python3
"""Synthesise a placeholder WAV for EVERY cue in docs/audio/CUE_SHEET.md. Owner: S18.

Usage: python3 tools/audio/gen_placeholders.py [--only cue,cue]
Writes the-last-fire-mage/assets/audio/placeholder/<cue>.wav (22.05 kHz mono 16-bit). Deterministic (seeded).
Placeholders keep the bank complete so the game is never silent-broken; build_bank.py prefers real files.
Cues without a recipe below get a short beep (and a warning) so new cue-sheet rows never break the build.
Music/dread stems of one group share an exact length so AudioStreamSynchronized stays in step.
"""
import math
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wavio  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "the-last-fire-mage", "assets", "audio", "placeholder")
SHEET = os.path.join(ROOT, "docs", "audio", "CUE_SHEET.md")
SR = 22050
TAU = 2 * math.pi


def cues_from_sheet():
    rows = []
    for line in open(SHEET, encoding="utf-8"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        m = re.match(r"`([a-z0-9_]+)`$", cells[0]) if len(cells) >= 5 else None
        if m:
            rows.append((m.group(1), cells[4].lower() == "yes"))
    return rows


# ------------------------------------------------------------------ building blocks
def n(sec):
    return int(sec * SR)


def env_ad(i, total, attack, decay_pow=2.0):
    a = n(attack)
    if i < a:
        return i / max(1, a)
    return (1.0 - (i - a) / max(1, total - a)) ** decay_pow


def noise(rng):
    return rng.uniform(-1, 1)


def lowpass(sig, cutoff):
    """One-pole low-pass; cutoff may be a float or a per-sample list."""
    out, y = [], 0.0
    for i, x in enumerate(sig):
        c = cutoff[i] if isinstance(cutoff, list) else cutoff
        a = 1 - math.exp(-TAU * c / SR)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(sig, cutoff):
    lp = lowpass(sig, cutoff)
    return [x - y for x, y in zip(sig, lp)]


def mix(*sigs):
    length = max(len(s) for s in sigs)
    return [sum(s[i] for s in sigs if i < len(s)) for i in range(length)]


def gain(sig, g):
    return [x * g for x in sig]


def loopify(sig, xfade_sec=0.25):
    """Crossfade the tail into the head so the sample loops without a click. Returns len(sig) - xfade."""
    x = n(xfade_sec)
    body = sig[:len(sig) - x]
    for i in range(x):
        k = i / x
        body[i] = body[i] * k + sig[len(sig) - x + i] * (1 - k)
    return body


def tone(freq, sec, wave="sine", detune_cents=0.0, vib=0.0, vib_rate=5.0):
    out, ph = [], 0.0
    f0 = freq * 2 ** (detune_cents / 1200.0)
    for i in range(n(sec)):
        f = f0 * (1 + vib * math.sin(TAU * vib_rate * i / SR))
        ph += f / SR
        p = ph % 1.0
        if wave == "sine":
            v = math.sin(TAU * p)
        elif wave == "saw":
            v = 2 * p - 1
        elif wave == "square":
            v = 1.0 if p < 0.5 else -1.0
        else:  # triangle
            v = 4 * abs(p - 0.5) - 1
        out.append(v)
    return out


def pluck(freq, sec, rng, bright=0.5):
    """Karplus-Strong plucked string (folk guitar/mandolin-ish)."""
    period = max(2, int(SR / freq))
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(n(sec)):
        v = buf[i % period]
        nxt = buf[(i + 1) % period]
        buf[i % period] = (v * bright + nxt * (1 - bright)) * 0.996
        out.append(v)
    return out


def burst(sec, rng, cutoff=3000.0, attack=0.003, decay_pow=3.0):
    raw = [noise(rng) * env_ad(i, n(sec), attack, decay_pow) for i in range(n(sec))]
    return lowpass(raw, cutoff)


def sweep_noise(sec, rng, f_from, f_to, attack=0.05, decay_pow=1.5):
    total = n(sec)
    cut = [f_from * (f_to / f_from) ** (i / total) for i in range(total)]
    raw = [noise(rng) * env_ad(i, total, attack, decay_pow) for i in range(total)]
    return lowpass(raw, cut)


def chime(freqs, sec, decay_pow=2.5, partials=(1.0, 2.76, 5.4)):
    total = n(sec)
    out = [0.0] * total
    for f in freqs:
        for k, p in enumerate(partials):
            amp = 1.0 / (k + 1)
            for i in range(total):
                out[i] += amp * math.sin(TAU * f * p * i / SR) * env_ad(i, total, 0.004, decay_pow + k)
    return out


def brown(sec, rng, smooth=0.02):
    out, y = [], 0.0
    for _ in range(n(sec)):
        y = (y + smooth * noise(rng)) * 0.998
        out.append(y)
    return out


def crackle(sec, rng, density=25.0):
    out = [0.0] * n(sec)
    i = 0
    while i < len(out):
        i += int(rng.expovariate(density) * SR) + 1
        length = rng.randint(20, 120)
        amp = rng.uniform(0.3, 1.0)
        for j in range(length):
            if i + j < len(out):
                out[i + j] += amp * noise(rng) * (1 - j / length) ** 2
    return highpass(out, 900.0)


def seq(notes, beat_sec, voice, rng):
    """notes = [(midi or None, beats)]; voice(freq, sec, rng) -> samples."""
    out = []
    for midi, beats in notes:
        sec = beats * beat_sec
        if midi is None:
            out += [0.0] * n(sec)
            continue
        note = voice(440.0 * 2 ** ((midi - 69) / 12.0), sec, rng)
        out += note[:n(sec)] + [0.0] * (n(sec) - len(note))
    return out


def fit(sig, length):
    return sig[:length] + [0.0] * (length - len(sig))


# ------------------------------------------------------------------ music: one seaside-folk tune, three stems
BPM = 112.0
BEAT = 60.0 / BPM
BARS = 16
MUSIC_LEN = n(BARS * 2 * BEAT)  # 2/4 time
# Melody in D major as (scale degree offset from D4=62, beats). A-B-A-B' form, 16 bars of 2 beats.
_PHRASE_A = [(0, .5), (4, .5), (7, .5), (4, .5), (5, .5), (4, .5), (2, .5), (0, .5),
             (2, .5), (4, .5), (5, .5), (7, .5), (9, 1.0), (7, 1.0)]
_PHRASE_B = [(9, .5), (7, .5), (5, .5), (4, .5), (2, .5), (4, .5), (5, .5), (2, .5),
             (0, .5), (2, .5), (4, .5), (2, .5), (0, 1.5), (None, .5)]
MELODY = _PHRASE_A + _PHRASE_B + _PHRASE_A + _PHRASE_B
# Bass/chord roots per bar (semitones from D): I IV I V | I IV V I ...
ROOTS = [0, 5, 0, 7, 0, 5, 7, 0] * 2


def _to_midi(deg, minor):
    if deg is None:
        return None
    # semitone table for major scale degrees 0..9 written as semitones directly in the phrase (0,2,4,5,7,9)
    semi = deg
    if minor:  # D minor: flatten the 3rd (4->3) and 6th (9->8)
        semi = {4: 3, 9: 8, 11: 10}.get(deg, deg)
    return 62 + semi


def music_cheer(rng):
    mel = seq([(_to_midi(d, False) + 12 if d is not None else None, b) for d, b in MELODY], BEAT,
              lambda f, s, r: [x * env_ad(i, n(s), 0.002, 1.2) for i, x in enumerate(pluck(f, s, r, 0.55))], rng)
    bass, chords = [], []
    for root in ROOTS:
        f_bass = 440.0 * 2 ** ((38 + root - 69) / 12.0)
        for beat in range(2):  # oom-pah: bass on the beat, chord on the off-beat
            b = tone(f_bass, BEAT / 2, "triangle")
            bass += [x * env_ad(i, len(b), 0.005, 2.0) for i, x in enumerate(b)] + [0.0] * n(BEAT / 2)
            chord = mix(*[tone(440.0 * 2 ** ((62 + root + iv - 69) / 12.0), BEAT / 2, "triangle") for iv in (0, 4, 7)])
            chords += [0.0] * n(BEAT / 2) + [x * env_ad(i, len(chord), 0.01, 3.0) * 0.33 for i, x in enumerate(chord)]
    return mix(gain(fit(mel, MUSIC_LEN), 0.55), gain(fit(bass, MUSIC_LEN), 0.45), gain(fit(chords, MUSIC_LEN), 0.3))


def music_dark(rng):
    """Soft, slow D-minor pad (no melody, no plucks: those read as repetitive clicking under the real theme).
    Chords change every 4 bars: Dm - Bb - Gm - A, detuned saws through a low-pass, slow swells."""
    total = MUSIC_LEN
    out = [0.0] * total
    chords = [(50, 53, 57), (46, 50, 53), (43, 46, 50), (45, 49, 52)]
    seg = total // len(chords)
    for k, chord in enumerate(chords):
        for midi in chord:
            f = 440.0 * 2 ** ((midi - 69) / 12.0)
            for det in (-9.0, 8.0):
                ff = f * 2 ** (det / 1200.0)
                for i in range(seg):
                    p = (ff * i / SR) % 1.0
                    swell = math.sin(math.pi * i / seg) ** 1.5
                    out[k * seg + i] += (2 * p - 1) * swell * 0.12
    return lowpass(lowpass(out, 900.0), 1200.0)


def music_drone(rng):
    total = MUSIC_LEN
    # Whole cycles of each partial over the loop so it loops seamlessly.
    loop_sec = total / SR
    out = [0.0] * total
    for f, amp in ((36.71, 0.5), (55.0, 0.3), (73.42, 0.25), (77.78, 0.12)):
        f = round(f * loop_sec) / loop_sec
        for i in range(total):
            out[i] += amp * math.sin(TAU * f * i / SR)
    wash = lowpass([noise(rng) for _ in range(total)], 300.0)
    return mix(out, gain(wash, 0.6))


# ------------------------------------------------------------------ dread stems (8 s, shared length)
DREAD_LEN = n(8.0)


def _cycles(f, length):
    sec = length / SR
    return round(f * sec) / sec


def dread_drone(rng):
    out = [0.0] * DREAD_LEN
    for f, amp in ((41.2, 0.5), (43.65, 0.4), (61.74, 0.2)):
        f = _cycles(f, DREAD_LEN)
        for i in range(DREAD_LEN):
            out[i] += amp * math.sin(TAU * f * i / SR)
    return out


def dread_strings(rng):
    out = [0.0] * DREAD_LEN
    for f in (659.25, 698.46, 932.33, 987.77):  # E5 F5 Bb5 B5: tritones and seconds
        f = _cycles(f, DREAD_LEN)
        for i in range(DREAD_LEN):
            p = (f * i / SR) % 1.0
            trem = 0.6 + 0.4 * math.sin(TAU * 8.0 * i / SR)  # 8 Hz = 64 cycles in 8 s, loops cleanly
            out[i] += (2 * p - 1) * trem * 0.25
    return lowpass(out, 3500.0)


def dread_chase(rng):
    out = [0.0] * DREAD_LEN
    step = DREAD_LEN // 64  # 16ths at 120 BPM
    pattern = [0, 0, 12, 0, 1, 0, 13, 0]
    for k in range(64):
        f = 440.0 * 2 ** ((40 + pattern[k % 8] - 69) / 12.0)
        for j in range(step):
            out[k * step + j] += (1.0 if (f * j / SR) % 1.0 < 0.5 else -1.0) * (1 - j / step) ** 2 * 0.5
    return lowpass(out, 1800.0)


def dread_spotted(rng):
    total = n(1.6)
    out = mix(*[tone(f, 1.6, "saw") for f in (233.08, 246.94, 349.23, 369.99)])
    hit = burst(0.4, rng, 600.0)
    return mix([x * env_ad(i, total, 0.005, 2.5) * 0.3 for i, x in enumerate(out)], gain(hit, 0.8))


def hunter_bed(rng):
    b = brown(6.25, rng, 0.05)
    growl = [math.sin(TAU * _cycles(46.25, n(6.0)) * i / SR) * (0.6 + 0.4 * math.sin(TAU * 0.5 * i / SR))
             for i in range(n(6.25))]
    return loopify(mix(gain(lowpass(b, 200.0), 3.0), gain(growl, 0.4), gain(crackle(6.25, rng, 6.0), 0.3)))


def ghost_bed(rng):
    pad = mix(*[tone(_cycles(f, n(8.0)), 8.25, "sine", vib=0.004, vib_rate=0.25) for f in (293.66, 440.0, 523.25)])
    air = highpass(lowpass([noise(rng) for _ in range(n(8.25))], 4000.0), 1500.0)
    return loopify(mix(gain(pad, 0.25), gain(air, 0.25)))


# ------------------------------------------------------------------ recipes per cue
def recipes():
    return {
        "step_villager": lambda r: burst(0.12, r, 1800.0),
        "step_mage": lambda r: mix(burst(0.16, r, 700.0), gain(crackle(0.16, r, 60.0), 0.3)),
        "mage_ember": lambda r: gain(crackle(0.35, r, 40.0), 0.8),
        "jump_takeoff": lambda r: sweep_noise(0.15, r, 800.0, 3000.0),
        "land_soft": lambda r: burst(0.15, r, 900.0),
        "land_hard": lambda r: mix(burst(0.3, r, 500.0), gain(tone(55.0, 0.3), 0.5)),
        "mantle": lambda r: sweep_noise(0.25, r, 1500.0, 600.0),
        "fall_thud": lambda r: mix(burst(0.35, r, 300.0), [math.sin(TAU * 50 * i / SR) * env_ad(i, n(.35), .002)
                                                          for i in range(n(.35))]),
        "hide_enter": lambda r: [math.sin(TAU * (180 + 60 * math.sin(TAU * 3 * i / SR)) * i / SR) * env_ad(i, n(.5), .05)
                                 * 0.5 for i in range(n(0.5))],
        "hide_exit": lambda r: [math.sin(TAU * (240 - 80 * i / n(.4)) * i / SR) * env_ad(i, n(.4), .03) * 0.5
                                for i in range(n(0.4))],
        "carry_pickup": lambda r: sweep_noise(0.18, r, 1000.0, 4000.0),
        "carry_drop": lambda r: burst(0.2, r, 800.0),
        "chicken_squawk": lambda r: [math.sin(TAU * (900 + 500 * math.sin(TAU * 18 * i / SR)) * i / SR)
                                     * env_ad(i, n(.35), .01, 1.5) * 0.6 for i in range(n(0.35))],
        "knife_swing": lambda r: sweep_noise(0.2, r, 600.0, 6000.0, 0.08),
        "ignite_whoosh": lambda r: mix(sweep_noise(0.6, r, 300.0, 5000.0, 0.15), gain(crackle(0.6, r, 50.0), 0.4)),
        "ignite_loop": lambda r: loopify(mix(gain(lowpass(brown(2.25, r, 0.05), 900.0), 2.0),
                                             gain(crackle(2.25, r, 30.0), 0.5))),
        "fire_wave_cast": lambda r: mix(sweep_noise(1.0, r, 200.0, 6000.0, 0.1, 1.0), gain(crackle(1.0, r, 80.0), 0.5)),
        "locate_pulse": lambda r: chime([392.0], 1.2, 3.0, (1.0, 1.5)),
        "hit_flesh": lambda r: burst(0.1, r, 2500.0, 0.001, 4.0),
        "kill_sting": lambda r: chime([146.83, 155.56], 2.0, 1.5, (1.0, 2.4, 3.9)),
        "wave_ready": lambda r: chime([880.0, 1318.5], 0.8),
        "tier_up": lambda r: mix(chime([587.33], 1.2), [0.0] * n(.12) + chime([880.0], 1.1),
                                 [0.0] * n(.24) + chime([1174.7], 1.0)),
        "mage_aura_loop": lambda r: loopify(mix(gain(lowpass(brown(3.25, r, 0.06), 250.0), 3.0),
                                                gain(crackle(3.25, r, 12.0), 0.4))),
        "villager_hurt": lambda r: [math.sin(TAU * (420 - 150 * i / n(.3)) * i / SR) * env_ad(i, n(.3), .01)
                                    * 0.6 for i in range(n(0.3))],
        "villager_death": lambda r: [math.sin(TAU * (380 - 260 * i / n(.9)) * i / SR) * env_ad(i, n(.9), .02, 1.2)
                                     * 0.6 for i in range(n(0.9))],
        "dread_drone": dread_drone,
        "dread_heartbeat": lambda r: _heartbeat(),
        "dread_strings": dread_strings,
        "dread_chase": dread_chase,
        "dread_spotted": dread_spotted,
        "hunter_bed": hunter_bed,
        "ghost_bed": ghost_bed,
        "music_cheer": music_cheer,
        "music_dark": music_dark,
        "music_drone": music_drone,
        "stinger_round_start": lambda r: lowpass(seq([(50, 1.0), (57, 2.0)], 0.35,
                                                      lambda f, s, _r: [x * env_ad(i, n(s), .05, .8) for i, x in
                                                                        enumerate(tone(f, s, "saw"))], r), 1500.0),
        "stinger_victory": lambda r: seq([(62, .5), (66, .5), (69, .5), (74, 2.0)], 0.22,
                                         lambda f, s, _r: chime([f], s, 1.5), r),
        "stinger_defeat": lambda r: seq([(69, .7), (65, .7), (62, .7), (61, 2.0)], 0.3,
                                        lambda f, s, _r: chime([f], s, 1.2), r),
        "storm_roar_loop": lambda r: loopify(mix(gain(lowpass(brown(4.25, r, 0.08), 350.0), 3.5),
                                                 gain(lowpass([noise(r) for _ in range(n(4.25))], 1200.0), 0.35))),
        "storm_crackle_loop": lambda r: loopify(gain(crackle(3.25, r, 45.0), 0.9)),
        "storm_wind_loop": lambda r: loopify(gain(highpass(lowpass([noise(r) for _ in range(n(4.25))], 1600.0),
                                                           300.0), 1.2)),
        "storm_warning_bell": lambda r: chime([523.25], 2.5, 1.8, (1.0, 2.0, 3.0, 4.2)),
        "storm_stage_sweep": lambda r: sweep_noise(2.0, r, 4000.0, 150.0, 0.3, 1.0),
        "storm_rumble_hit": lambda r: mix(burst(1.5, r, 200.0, 0.01, 1.5), gain(tone(40.0, 1.5), 0.4)),
        "storm_damage_tick": lambda r: mix(burst(0.15, r, 5000.0), gain(crackle(0.15, r, 100.0), 0.6)),
        "amb_ocean_loop": lambda r: _ocean(r),
        "amb_town_loop": lambda r: loopify(gain(lowpass(brown(6.25, r, 0.03), 500.0), 2.0)),
        "amb_gulls": lambda r: [math.sin(TAU * (1500 + 700 * math.sin(TAU * 6 * i / SR)) * i / SR)
                                * env_ad(i, n(.6), .05, 1.2) * 0.4 for i in range(n(0.6))],
        "flame_crackle_loop": lambda r: loopify(mix(gain(crackle(2.25, r, 20.0), 0.7),
                                                    gain(lowpass(brown(2.25, r, 0.04), 600.0), 1.2))),
        "ui_click": lambda r: burst(0.03, r, 6000.0, 0.0005, 4.0),
        "ui_confirm": lambda r: chime([660.0, 990.0], 0.35),
    }


def _heartbeat():
    total = n(1.0)  # 60 BPM loop; the director speeds it up with pitch_scale
    out = [0.0] * total
    for start, amp in ((0.0, 1.0), (0.28, 0.7)):
        s = n(start)
        for i in range(n(0.18)):
            out[s + i] += amp * math.sin(TAU * 48.0 * i / SR) * env_ad(i, n(0.18), 0.01, 3.0)
    return out


def _ocean(r):
    sec = 12.25
    raw = lowpass([noise(r) for _ in range(n(sec))], 900.0)
    swell = [0.35 + 0.65 * (0.5 + 0.5 * math.sin(TAU * i / n(6.0))) ** 2 for i in range(n(sec))]
    return loopify([x * s * 2.0 for x, s in zip(raw, swell)])


def main():
    only = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only = set(sys.argv[2].split(","))
    os.makedirs(OUT, exist_ok=True)
    table = recipes()
    for cue, is_loop in cues_from_sheet():
        if only and cue not in only:
            continue
        rng = random.Random(cue)
        if cue in table:
            sig = table[cue](rng)
        else:
            print("[audio] WARNING: no recipe for %s, writing a beep" % cue)
            sig = [math.sin(TAU * 1000 * i / SR) * env_ad(i, n(.2), .005) for i in range(n(0.2))]
        chans = wavio.process([sig], SR, peak_db=-3.0, loop=is_loop)
        wavio.write_wav(os.path.join(OUT, cue + ".wav"), SR, chans)
        print("[audio] placeholder %-22s %.2fs" % (cue, len(chans[0]) / SR))


if __name__ == "__main__":
    main()
