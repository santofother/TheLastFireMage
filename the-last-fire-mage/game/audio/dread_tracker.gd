class_name DreadTracker
extends RefCounted
## Mage-proximity dread state for the LOCAL villager. Owner: S18. NET: local only, pure logic (no nodes),
## so tests can drive it. The AudioDirector feeds it distance + line of sight ~4 Hz and reads `levels`.
## CONTRACT (user decision): layers only with line of sight to the mage; no LOS = fade out (hiding keeps you quiet).
##
## Public API: `LAYERS`, `active` (layer -> bool), `levels` (layer -> 0..1, faded), `los` (debounced),
## `spotted_count`, `sense(has_mage, distance, raw_los, dt) -> bool` (true = play the "spotted" stinger),
## `fade(dt)`, `reset()`, `active_names()`, `settle` (0.6..1 volume for lingering dread), `mute_stinger(sec)`.

const LAYERS: Array[StringName] = [&"drone", &"heartbeat", &"strings", &"chase"]

var tuning: AudioTuning
## Layer is wanted right now (after hysteresis).
var active := {}
## Faded 0..1 level per layer (what the mix uses).
var levels := {}
## Debounced line of sight.
var los := false
## Distance to the nearest mage from the last sense() (INF = none).
var distance := INF
## Times the "spotted" stinger fired (tests/debug).
var spotted_count := 0
## Volume multiplier for the layers: 1.0 on a fresh approach, tuning.dread_settle_level once the mage lingers.
var settle := 1.0

var _los_timer := 0.0
var _chase_left := 0.0
var _spotted_cooldown := 0.0
var _engaged := 0.0 # seconds of continuous dread
var _calm := 0.0 # seconds with no dread layer active


func _init(t: AudioTuning) -> void:
	tuning = t
	reset()


func reset() -> void:
	for l in LAYERS:
		active[l] = false
		levels[l] = 0.0
	los = false
	distance = INF
	_los_timer = 0.0
	_chase_left = 0.0
	settle = 1.0
	_engaged = 0.0
	_calm = 0.0


## No "spotted" stinger for the next `seconds` (e.g. right after the mage is released).
func mute_stinger(seconds: float) -> void:
	_spotted_cooldown = maxf(_spotted_cooldown, seconds)


## One sensing tick. `force_spot` = the mage did something loud nearby (ignite). Returns true when the
## "spotted" stinger should play this tick.
func sense(has_mage: bool, dist: float, raw_los: bool, dt: float, force_spot: bool = false) -> bool:
	distance = dist if has_mage else INF
	raw_los = raw_los and has_mage
	var was_los := los
	# Debounce: LOS must hold a moment to start and be gone a moment to stop, so corners don't flicker.
	if raw_los != los:
		_los_timer += dt
		if _los_timer >= (tuning.dread_los_on_delay if raw_los else tuning.dread_los_off_delay):
			los = raw_los
			_los_timer = 0.0
	else:
		_los_timer = 0.0
	_spotted_cooldown = maxf(0.0, _spotted_cooldown - dt)
	_chase_left = maxf(0.0, _chase_left - dt)
	var spotted := false
	if los and distance <= tuning.dread_spotted_range and (not was_los or (force_spot and raw_los)):
		_chase_left = tuning.dread_chase_hold
		if _spotted_cooldown <= 0.0:
			spotted = true
			spotted_count += 1
			_spotted_cooldown = tuning.dread_spotted_cooldown
	_set_layer(&"drone", tuning.dread_drone_range)
	_set_layer(&"heartbeat", tuning.dread_heartbeat_range)
	_set_layer(&"strings", tuning.dread_strings_range)
	_set_layer(&"chase", tuning.dread_chase_range if _chase_left > 0.0 else -1.0)
	return spotted


## Move `levels` toward `active` (call every frame).
func fade(dt: float) -> void:
	for l in LAYERS:
		var target := 1.0 if active[l] else 0.0
		var rate := 1.0 / (tuning.dread_fade_in if target > levels[l] else tuning.dread_fade_out)
		levels[l] = move_toward(float(levels[l]), target, rate * dt)
	var any := false
	for l in LAYERS:
		any = any or bool(active[l])
	if any:
		_engaged += dt
		_calm = 0.0
	else:
		_calm += dt
		if _calm >= tuning.dread_settle_reset:
			_engaged = 0.0
	var want := tuning.dread_settle_level if _engaged >= tuning.dread_settle_after else 1.0
	settle = move_toward(settle, want, dt / maxf(tuning.dread_settle_fade, 0.01))


## Names of active layers, for log lines.
func active_names() -> String:
	var out := PackedStringArray()
	for l in LAYERS:
		if active[l]:
			out.append(String(l))
	return ",".join(out) if out.size() > 0 else "none"


## Heartbeat playback speed: slow at the edge of its range, fast up close.
func heartbeat_pitch() -> float:
	var k := clampf(1.0 - distance / tuning.dread_heartbeat_range, 0.0, 1.0)
	return lerpf(tuning.heartbeat_slow_pitch, tuning.heartbeat_fast_pitch, k * k)


func _set_layer(layer: StringName, range_m: float) -> void:
	if not los or range_m <= 0.0:
		active[layer] = false
	elif distance <= range_m:
		active[layer] = true
	elif distance > range_m * tuning.dread_hysteresis:
		active[layer] = false
