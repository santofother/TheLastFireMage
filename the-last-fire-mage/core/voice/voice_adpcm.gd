extends RefCounted
## IMA ADPCM (4 bits per sample) for voice packets. Owner: S12. NET: runs on every peer.
## Public API (all static): encode(samples) -> PackedByteArray, decode(bytes) -> PackedFloat32Array.
## 16 kHz mono 16-bit PCM is 256 kbit/s; this is ~66 kbit/s (-74%) at good speech quality.
# CONTRACT: every packet is self-contained (header = starting predictor + step index), so a lost or
# reordered unreliable packet never corrupts the packets after it. Do not carry codec state across packets.
## Packet layout: [predictor s16 LE][index u8 (bit 7 = "drop last decoded sample")][nibbles, low nibble first]
## The first sample is stored in the header; the remaining n-1 samples are 4-bit deltas.

const STEPS: PackedInt32Array = [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
	107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
	876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
	4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
	22385, 24623, 27086, 29794, 32767]
const INDEX_ADJUST: PackedInt32Array = [-1, -1, -1, -1, 2, 4, 6, 8]
const HEADER := 3


## Encode float samples (-1..1) to a self-contained packet. Empty input -> empty packet.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	var n := samples.size()
	if n == 0:
		return out
	var pcm := PackedInt32Array()
	pcm.resize(n)
	for i in n:
		pcm[i] = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
	var predictor := pcm[0]
	var index := _initial_index(pcm)
	var odd_tail := (n - 1) % 2 == 1 # an odd count of nibbles gets one padding nibble
	out.resize(HEADER + (n - 1 + 1) / 2)
	out.encode_s16(0, predictor)
	out[2] = index | (0x80 if odd_tail else 0)
	var nibble_hold := -1
	var o := HEADER
	for i in range(1, n):
		var step := STEPS[index]
		var diff := pcm[i] - predictor
		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		var delta := step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			delta += step
		if diff >= step >> 1:
			code |= 2
			diff -= step >> 1
			delta += step >> 1
		if diff >= step >> 2:
			code |= 1
			delta += step >> 2
		predictor = clampi(predictor + (-delta if code & 8 else delta), -32768, 32767)
		index = clampi(index + INDEX_ADJUST[code & 7], 0, 88)
		if nibble_hold < 0:
			nibble_hold = code
		else:
			out[o] = nibble_hold | (code << 4)
			o += 1
			nibble_hold = -1
	if nibble_hold >= 0:
		out[o] = nibble_hold # padding nibble is 0 and is dropped by the decoder
	return out


## Decode a packet made by encode(). Malformed input returns an empty array.
static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if data.size() < HEADER:
		return out
	var predictor := data.decode_s16(0)
	var index := clampi(data[2] & 0x7F, 0, 88)
	var drop_last := (data[2] & 0x80) != 0
	var nibble_count := (data.size() - HEADER) * 2 - (1 if drop_last else 0)
	out.resize(1 + nibble_count)
	out[0] = predictor / 32768.0
	var w := 1
	for b in range(HEADER, data.size()):
		var byte := data[b]
		for half in 2:
			if w > nibble_count:
				break
			var code := (byte >> (4 * half)) & 0xF
			var step := STEPS[index]
			var delta := step >> 3
			if code & 4:
				delta += step
			if code & 2:
				delta += step >> 1
			if code & 1:
				delta += step >> 2
			predictor = clampi(predictor + (-delta if code & 8 else delta), -32768, 32767)
			index = clampi(index + INDEX_ADJUST[code & 7], 0, 88)
			out[w] = predictor / 32768.0
			w += 1
	return out


## Pick a step index near the chunk's loudness so the first samples are not coarsely quantised.
static func _initial_index(pcm: PackedInt32Array) -> int:
	var span := 0
	for i in range(1, mini(pcm.size(), 16)):
		span = maxi(span, absi(pcm[i] - pcm[i - 1]))
	var index := 0
	while index < 88 and STEPS[index] < span / 2:
		index += 1
	return index
