extends RefCounted
## Per-speaker voice effect buses (distortion / pitch-down / reverb). Owner: S12. NET: local audio only.
## Public API (static): PRESETS, ensure_bus(peer_id), apply(bus_name, preset, strength), free_bus(bus_name).
## core/ knows nothing about mages: the game picks a preset name and a 0..1 strength.
# TUNE: preset values are the effect at strength 1.0; strength 0 = clean voice (effects bypassed).
## pitch: playback pitch factor (<1 = deeper), drive: distortion amount 0..1, reverb: wet 0..1, room: reverb size.

const PRESETS := {
	&"none": {"pitch": 1.0, "drive": 0.0, "reverb": 0.0, "room": 0.5},
	&"mage": {"pitch": 0.72, "drive": 0.45, "reverb": 0.35, "room": 0.7},
	&"deep": {"pitch": 0.7, "drive": 0.0, "reverb": 0.0, "room": 0.5},
	&"distort": {"pitch": 1.0, "drive": 0.7, "reverb": 0.0, "room": 0.5},
	&"cave": {"pitch": 1.0, "drive": 0.0, "reverb": 0.6, "room": 0.9},
}
const PITCH_IDX := 0
const DIST_IDX := 1
const REVERB_IDX := 2


static func bus_name_for(peer_id: int) -> StringName:
	return StringName("Voice_%d" % peer_id)


## Create (once) the effect bus for a speaker, routed to Master. Returns its name.
static func ensure_bus(peer_id: int) -> StringName:
	var name := bus_name_for(peer_id)
	if AudioServer.get_bus_index(name) >= 0:
		return name
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, &"Master")
	var pitch := AudioEffectPitchShift.new()
	pitch.fft_size = AudioEffectPitchShift.FFT_SIZE_1024 # WHY: smaller sizes warble on speech
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE # WHY: soft clip; CLIP mode is harsher and louder
	dist.post_gain = -3.0 # keep loudness about equal (voices were previously too quiet; never go quieter)
	var rev := AudioEffectReverb.new()
	rev.dry = 1.0
	AudioServer.add_bus_effect(idx, pitch, PITCH_IDX)
	AudioServer.add_bus_effect(idx, dist, DIST_IDX)
	AudioServer.add_bus_effect(idx, rev, REVERB_IDX)
	for e in 3:
		AudioServer.set_bus_effect_enabled(idx, e, false)
	return name


## Set the effect on an existing speaker bus. Unknown preset or strength <= 0 = clean voice.
static func apply(bus: StringName, preset: StringName, strength: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var s := clampf(strength, 0.0, 1.0)
	var p: Dictionary = PRESETS.get(preset, PRESETS[&"none"])
	var pitch_on := s > 0.0 and absf(float(p["pitch"]) - 1.0) > 0.001
	var drive_on := s > 0.0 and float(p["drive"]) > 0.0
	var reverb_on := s > 0.0 and float(p["reverb"]) > 0.0
	if pitch_on:
		(AudioServer.get_bus_effect(idx, PITCH_IDX) as AudioEffectPitchShift).pitch_scale = lerpf(1.0, float(p["pitch"]), s)
	if drive_on:
		var d := AudioServer.get_bus_effect(idx, DIST_IDX) as AudioEffectDistortion
		d.drive = float(p["drive"]) * s
		d.keep_hf_hz = 5000.0
	if reverb_on:
		var r := AudioServer.get_bus_effect(idx, REVERB_IDX) as AudioEffectReverb
		r.wet = float(p["reverb"]) * s
		r.room_size = float(p["room"])
	AudioServer.set_bus_effect_enabled(idx, PITCH_IDX, pitch_on)
	AudioServer.set_bus_effect_enabled(idx, DIST_IDX, drive_on)
	AudioServer.set_bus_effect_enabled(idx, REVERB_IDX, reverb_on)


static func free_bus(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.remove_bus(idx)
