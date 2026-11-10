"""Tiny WAV read/process/write helpers (stdlib only: no numpy/ffmpeg on the build machine). Owner: S18.

read_wav(path) -> (rate, [channel floats]) for PCM 8/16/24/32-bit and 32-bit float (incl. WAVE_FORMAT_EXTENSIBLE).
write_wav(path, rate, channels) writes 16-bit PCM. process(...) = mono/trim/normalise/fade for game SFX.
"""
import math
import struct


def read_wav(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a WAV: %s" % path)
    pos, fmt, raw = 12, None, None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = body
        elif cid == b"data":
            raw = body
        pos += 8 + size + (size & 1)
    tag, nch, rate = struct.unpack("<HHI", fmt[:8])
    bits = struct.unpack("<H", fmt[14:16])[0]
    if tag == 0xFFFE:  # WAVE_FORMAT_EXTENSIBLE: real format in the sub-format GUID
        tag = struct.unpack("<H", fmt[24:26])[0]
    width = bits // 8
    frames = len(raw) // (width * nch)
    chans = [[0.0] * frames for _ in range(nch)]
    for i in range(frames):
        for c in range(nch):
            o = (i * nch + c) * width
            b = raw[o:o + width]
            if tag == 3 and width == 4:
                v = struct.unpack("<f", b)[0]
            elif width == 1:
                v = (b[0] - 128) / 128.0
            elif width == 2:
                v = struct.unpack("<h", b)[0] / 32768.0
            elif width == 3:
                v = int.from_bytes(b, "little", signed=True) / 8388608.0
            elif width == 4:
                v = struct.unpack("<i", b)[0] / 2147483648.0
            else:
                raise ValueError("unsupported width %d" % width)
            chans[c][i] = v
    return rate, chans


def write_wav(path, rate, chans):
    nch, frames = len(chans), len(chans[0])
    out = bytearray()
    for i in range(frames):
        for c in range(nch):
            v = max(-1.0, min(1.0, chans[c][i]))
            out += struct.pack("<h", int(round(v * 32767)))
    hdr = b"RIFF" + struct.pack("<I", 36 + len(out)) + b"WAVE"
    hdr += b"fmt " + struct.pack("<IHHIIHH", 16, 1, nch, rate, rate * nch * 2, nch * 2, 16)
    hdr += b"data" + struct.pack("<I", len(out))
    with open(path, "wb") as f:
        f.write(hdr + bytes(out))


def process(chans, rate, mono=True, trim_db=-50.0, peak_db=-1.0, fade_ms=10.0, start=None, end=None, loop=False):
    """Slice [start,end) seconds, mix to mono, trim leading/trailing silence (not for loops), normalise the peak,
    fade in/out (loops get a short crossfade-safe 5 ms fade only)."""
    if start is not None or end is not None:
        a = int((start or 0.0) * rate)
        b = int(end * rate) if end is not None else len(chans[0])
        chans = [c[a:b] for c in chans]
    if mono and len(chans) > 1:
        n = len(chans)
        chans = [[sum(c[i] for c in chans) / n for i in range(len(chans[0]))]]
    if not loop:
        thr = 10 ** (trim_db / 20.0)
        frames = len(chans[0])
        first = next((i for i in range(frames) if any(abs(c[i]) > thr for c in chans)), 0)
        last = next((i for i in range(frames - 1, -1, -1) if any(abs(c[i]) > thr for c in chans)), frames - 1)
        chans = [c[first:last + 1] for c in chans]
    peak = max(max(abs(v) for v in c) for c in chans) or 1.0
    gain = (10 ** (peak_db / 20.0)) / peak
    chans = [[v * gain for v in c] for c in chans]
    fade = max(1, int(rate * (5.0 if loop else fade_ms) / 1000.0))
    frames = len(chans[0])
    for c in chans:
        for i in range(min(fade, frames)):
            k = i / fade
            c[i] *= k
            c[frames - 1 - i] *= k
    return chans


def peak_db(chans):
    p = max(max(abs(v) for v in c) for c in chans)
    return 20 * math.log10(p) if p > 0 else -120.0
