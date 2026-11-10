class_name AudioDirector
extends Node
## All global and event audio. Owner: S18. Root at `Systems/Audio`, `GameEvents.system(&"audio")`, log `[Audio]`.
## NET: LOCAL ONLY on every peer. No RPCs, no synced state: everything comes from GameEvents and from positions /
## replicated flags every peer already has. It attaches emitters to other systems' nodes at runtime.
##
## What it does (see docs/audio/CUE_SHEET.md for every cue):
## - room echo: 8 rays from the listener (~6 Hz) drive the `World` bus reverb; nearest 6 sources get occlusion.
## - movement noise: a FootstepEmitter on every player; chicken squawks when a mage gets close; hide-spot creaks.
## - mage cues: casts are detected from MageAbilities cooldowns (no edits to game/mage/), hits/kills from GameEvents.
## - dread (local alive villager, LINE OF SIGHT ONLY): DreadTracker layers + heartbeat; mage gets a hunter bed,
##   the dead get a ghost bed.
## - music arc: cheerful folk stems -> dark stems + drones by `match_dread` (firestorm stage, mage tier, hunt time).
## - firestorm: a roar emitter slides along the ring at the point nearest the listener; warning bells, stage hits,
##   wind + muffle inside the storm. Ocean on the coast side as a compass, gulls/town bed thin out with dread.
## - voice: routes every remote voice (plain or `Voice_<peer>` FX bus) into `World`; ducks music under speech.
##
## Public API: `tuning`, `dread` (DreadTracker), `match_dread` 0..1, `room_enclosure`, `reverb_wet`, `in_storm`,
## `storm_emitter`, `set_bus_volume_db(bus, db)`, static `storm_point(center, radius, from)`, `emitter_for(peer)`.
## Test hooks: `listener_override`, `mage_override`, `role_override`, `alive_override`.

const TUNING_PATH := "res://game/audio/tuning_audio.tres"
## Physics layers 1 (world) + 9 (furniture): what blocks sight and sound.
const WORLD_MASK := 1 | (1 << 8)
const BUSES: Array[StringName] = [&"World", &"SFX", &"Music", &"Ambience", &"Dread", &"Stingers", &"UI"]
const PROP_SCENES: Array[String] = ["res://game/props/torch.tscn", "res://game/props/candles.tscn",
	"res://game/props/lantern.tscn"]
const MAGE_HEAD := Vector3(0, 1.5, 0)
const SILENT_DB := -80.0

var tuning: AudioTuning
var dread: DreadTracker
## 0 = carefree seaside, 1 = full horror. Drives music stems, filters and ambience thinning.
var match_dread := 0.0
## 0..1 share of probe rays that hit something (1 = closed room).
var room_enclosure := 0.0
## Current (smoothed) wet level of the World reverb.
var reverb_wet := 0.0
## Target wet level from the last room probe.
var reverb_target_wet := 0.0
## The local listener is outside the safe zone.
var in_storm := false
## Wall-of-fire roar, placed at the ring point nearest the listener.
var storm_emitter: AudioStreamPlayer3D

## Tests: use this node as the listener (and dread source) instead of the camera / local player.
var listener_override: Node3D
## Tests: these nodes count as mages for dread.
var mage_override: Array = []
## Tests: local role (Enums.Role) when >= 0.
var role_override := -1
## Tests: local alive flag (used when role_override >= 0).
var alive_override := true

var _local: Node
var _phase: int = Enums.Phase.LOBBY
var _hunt_time := 0.0
var _stage := 0
var _tiers := {} # mage peer id -> tier
var _bus_base := {} # bus -> base dB
var _duck := 0.0
var _music: AudioStreamPlayer
var _music_stream: AudioStreamSynchronized
var _dread_player: AudioStreamPlayer
var _dread_stream: AudioStreamSynchronized
var _heartbeat: AudioStreamPlayer
var _hunter: AudioStreamPlayer
var _ghost: AudioStreamPlayer
var _hunter_level := 0.0
var _ghost_level := 0.0
var _wind: AudioStreamPlayer
var _wind_level := 0.0
var _town: AudioStreamPlayer
var _ocean: AudioStreamPlayer3D
var _storm_crackle: AudioStreamPlayer3D
var _storm_level := 0.0
var _storm_placed := false
var _edge_factor := 1.0
var _muffle := 0.0
var _reverb: AudioEffectReverb
var _lowpass := {} # bus -> AudioEffectLowPassFilter
var _probe_dirs := PackedVector3Array()
var _ray := PhysicsRayQueryParameters3D.new()
var _t_slow := 0.0
var _t_room := 0.0
var _t_props := 0.0
var _gull_left := 6.0
var _mage_state := {} # mage peer id -> {cd: Dictionary, ignited: bool, loop: Node}
var _ignite_spot := false
var _chicken_near := {}
var _hide_counts := {}
var _props: Array[Node3D] = []
var _props_dirty := true
var _prop_voices: Array[AudioStreamPlayer3D] = []
var _storm_tick_cd := 0.0
var _last_dread_names := "none"
var _last_music_bucket := -1
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	GameEvents.register_system(&"audio", self)


func _ready() -> void:
	tuning = Tuning.load_tuning(TUNING_PATH, "audio") as AudioTuning
	dread = DreadTracker.new(tuning)
	Sfx.root = self
	_ensure_buses()
	for d in [Vector3(1, 0, 0), Vector3(0.5, 0, 0.866), Vector3(-0.5, 0, 0.866), Vector3(-1, 0, 0),
			Vector3(-0.5, 0, -0.866), Vector3(0.5, 0, -0.866), Vector3.UP, Vector3(0, 0.707, 0.707)]:
		_probe_dirs.append(d.normalized())
	_ray.collision_mask = WORLD_MASK
	_build_players()
	GameEvents.phase_changed.connect(_on_phase_changed)
	GameEvents.round_ended.connect(_on_round_ended)
	GameEvents.player_damaged.connect(_on_player_damaged)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.carry_changed.connect(_on_carry_changed)
	GameEvents.power_changed.connect(_on_power_changed)
	GameEvents.firestorm_stage.connect(_on_firestorm_stage)
	GameEvents.firestorm_warning.connect(_on_firestorm_warning)
	var bank := Sfx.bank()
	print("[Audio] director ready cues=%d placeholders=%d headless=%s" % [bank.cue_names().size(),
		bank.placeholder_cues.size(), Sfx.headless])


## Set a bus level (dB). Settings UI hook. Never lower voice: voice isn't on these buses' volume path.
func set_bus_volume_db(bus: StringName, db: float) -> void:
	_bus_base[bus] = db
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db + (_duck if bus == &"Music" or bus == &"Ambience" else 0.0))


## The FootstepEmitter attached to a player, or null.
func emitter_for(peer_id: int) -> FootstepEmitter:
	var p := Players.get_player(peer_id)
	return p.get_node_or_null(^"AudioEmitter") as FootstepEmitter if p else null


## Point on the safe-zone ring nearest to `from` (same height as `from`).
static func storm_point(center: Vector3, radius: float, from: Vector3) -> Vector3:
	var flat := Vector3(from.x - center.x, 0.0, from.z - center.z)
	var dir := flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var p := center + dir * radius
	p.y = from.y
	return p


# ---------------------------------------------------------------- setup

func _ensure_buses() -> void:
	# WHY: default_bus_layout.tres normally provides these; recreate them if a layout without them is loaded.
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"World" if bus == &"SFX" else &"Master")
	var w := AudioServer.get_bus_index(&"World")
	_reverb = _find_effect(w, "AudioEffectReverb") as AudioEffectReverb
	if _reverb == null:
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(w, _reverb)
	for bus in [&"SFX", &"Ambience", &"Music"]:
		var idx := AudioServer.get_bus_index(bus)
		var lp := _find_effect(idx, "AudioEffectLowPassFilter") as AudioEffectLowPassFilter
		if lp == null:
			lp = AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(idx, lp)
		_lowpass[bus] = lp
	set_bus_volume_db(&"Music", tuning.music_db)
	set_bus_volume_db(&"Ambience", tuning.ambience_db)
	set_bus_volume_db(&"SFX", tuning.sfx_db)
	set_bus_volume_db(&"Dread", tuning.dread_db)
	set_bus_volume_db(&"Stingers", tuning.stingers_db)
	set_bus_volume_db(&"UI", tuning.ui_db)


func _find_effect(bus_idx: int, cls: String) -> AudioEffect:
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var e := AudioServer.get_bus_effect(bus_idx, i)
		if e.is_class(cls):
			return e
	return null


func _build_players() -> void:
	_music_stream = _sync_stream([&"music_cheer", &"music_dark", &"music_drone"])
	_music = _player_2d(_music_stream, &"Music", "Music")
	_dread_stream = _sync_stream([&"dread_drone", &"dread_strings", &"dread_chase"])
	_dread_player = _player_2d(_dread_stream, &"Dread", "DreadStems")
	_heartbeat = _player_2d(Sfx.stream(&"dread_heartbeat"), &"Dread", "Heartbeat")
	_hunter = _player_2d(Sfx.stream(&"hunter_bed"), &"Dread", "HunterBed")
	_ghost = _player_2d(Sfx.stream(&"ghost_bed"), &"Dread", "GhostBed")
	_wind = _player_2d(Sfx.stream(&"storm_wind_loop"), &"Ambience", "StormWind")
	_town = _player_2d(Sfx.stream(&"amb_town_loop"), &"Ambience", "TownBed")
	storm_emitter = Sfx.attach_loop(self, &"storm_roar_loop", &"SFX", tuning.storm_roar_range)
	_storm_crackle = Sfx.attach_loop(self, &"storm_crackle_loop", &"SFX", tuning.storm_crackle_range)
	_ocean = Sfx.attach_loop(self, &"amb_ocean_loop", &"Ambience", tuning.ocean_range)
	for p in [storm_emitter, _storm_crackle]:
		if p:
			p.set_meta(&"occl_lows", true)
			p.unit_size = 12.0 # TUNE: the roar is a wall, not a point: stays loud over a wide band
			Sfx.set_base_db(p, SILENT_DB)
	if _ocean:
		_ocean.set_meta(&"no_occlusion", true)
		_ocean.unit_size = 60.0 # TUNE: faint everywhere, but it pans: compass anchor
		_ocean.global_position = tuning.ocean_direction.normalized() * tuning.ocean_distance
	for i in tuning.prop_crackle_voices:
		var v := Sfx.attach_loop(self, &"flame_crackle_loop", &"SFX", tuning.prop_crackle_range)
		if v:
			v.stream_paused = true
			Sfx.set_base_db(v, -6.0)
			_prop_voices.append(v)


func _sync_stream(cues: Array) -> AudioStreamSynchronized:
	var s := AudioStreamSynchronized.new()
	s.stream_count = cues.size()
	for i in cues.size():
		s.set_sync_stream(i, Sfx.stream(cues[i]))
		s.set_sync_stream_volume(i, SILENT_DB)
	return s


func _player_2d(stream: AudioStream, bus: StringName, node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = stream
	p.bus = bus
	p.volume_db = SILENT_DB
	add_child(p)
	if stream and not Sfx.headless:
		p.play()
	return p


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	_t_slow += delta
	_t_room += delta
	_t_props += delta
	_storm_tick_cd = maxf(0.0, _storm_tick_cd - delta)
	if _phase == Enums.Phase.HUNT:
		_hunt_time += delta
	var listener := _listener()
	if _t_slow >= 0.25:
		_tick_slow(_t_slow, listener)
		_t_slow = 0.0
	if _t_room >= 1.0 / 6.0:
		_t_room = 0.0
		if listener:
			_probe_room(_ear(listener))
			_occlude(_ear(listener))
	if _t_props >= 1.0:
		_t_props = 0.0
		_update_props(listener)
	_poll_mages()
	_update_storm(listener, delta)
	_update_reverb(delta)
	_update_dread_mix(delta)
	_update_music(delta)
	_update_ambience(listener, delta)


func _tick_slow(dt: float, listener: Node3D) -> void:
	_local = Players.local_player()
	_attach_emitters()
	_route_voices()
	_chickens()
	_hide_spots()
	_sense_dread(dt, listener)


func _listener() -> Node3D:
	if listener_override:
		return listener_override
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	return cam if cam else _local as Node3D


## Ear position: the camera / override as is, a player at head height.
func _ear(n: Node3D) -> Vector3:
	return n.global_position + (MAGE_HEAD if n is CharacterBody3D else Vector3.ZERO)


func _local_role() -> int:
	if role_override >= 0:
		return role_override
	return int(_local.get(&"role")) if _local else Enums.Role.NONE


func _local_alive() -> bool:
	if role_override >= 0:
		return alive_override
	return bool(_local.get(&"is_alive")) if _local else true


func _blocked(from: Vector3, to: Vector3) -> bool:
	var world := get_viewport().find_world_3d() if get_viewport() else null
	if world == null:
		return false
	_ray.from = from
	_ray.to = to
	return not world.direct_space_state.intersect_ray(_ray).is_empty()


# ---------------------------------------------------------------- a. room echo + occlusion

func _probe_room(ear: Vector3) -> void:
	var world := get_viewport().find_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	var hits := 0
	var dist_sum := 0.0
	var hit_sum := 0.0
	for d in _probe_dirs:
		_ray.from = ear
		_ray.to = ear + d * tuning.room_probe_range
		var r := space.intersect_ray(_ray)
		if r.is_empty():
			dist_sum += tuning.room_probe_range
		else:
			var dd := ear.distance_to(r["position"])
			hits += 1
			dist_sum += dd
			hit_sum += dd
	room_enclosure = float(hits) / float(_probe_dirs.size())
	var size_n := clampf(dist_sum / _probe_dirs.size() / tuning.room_probe_range, 0.0, 1.0)
	reverb_target_wet = lerpf(tuning.room_open_wet, tuning.room_closed_wet, room_enclosure)
	if _reverb:
		_reverb.room_size = lerpf(0.15, 0.85, size_n)
		_reverb.damping = lerpf(0.3, 0.7, 1.0 - room_enclosure)
		var avg_hit := hit_sum / hits if hits > 0 else tuning.room_probe_range
		_reverb.predelay_msec = clampf(avg_hit * 2.0 / 343.0 * 1000.0, 5.0, 100.0)


func _update_reverb(delta: float) -> void:
	reverb_wet = lerpf(reverb_wet, reverb_target_wet, 1.0 - exp(-tuning.room_smoothing * delta))
	if _reverb:
		_reverb.wet = reverb_wet


func _occlude(ear: Vector3) -> void:
	var live: Array[AudioStreamPlayer3D] = []
	for p in Sfx.tracked:
		if is_instance_valid(p) and p.is_inside_tree():
			live.append(p)
	Sfx.tracked = live
	var near: Array = []
	for p in live:
		if not p.has_meta(&"no_occlusion"):
			near.append([p.global_position.distance_squared_to(ear), p])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in near.size():
		var p: AudioStreamPlayer3D = near[i][1]
		var blocked := i < tuning.occlusion_sources and _blocked(p.global_position + Vector3.UP * 0.3, ear)
		var lows := p.has_meta(&"occl_lows")
		var occl_db := (tuning.occlusion_db * (0.4 if lows else 1.0)) if blocked else 0.0
		p.attenuation_filter_cutoff_hz = (tuning.occlusion_lows_cutoff_hz if lows else tuning.occlusion_cutoff_hz) \
			if blocked else 20500.0
		if not is_equal_approx(float(p.get_meta(&"occl_db", 0.0)), occl_db):
			p.set_meta(&"occl_db", occl_db)
			Sfx.set_base_db(p, float(p.get_meta(&"base_db", 0.0)))


# ---------------------------------------------------------------- b. movement noise, chickens, hide spots, voice

func _attach_emitters() -> void:
	for p in Players.all():
		var e := p.get_node_or_null(^"AudioEmitter") as FootstepEmitter
		if e == null:
			e = FootstepEmitter.new()
			e.name = "AudioEmitter"
			e.player = p
			e.tuning = tuning
			p.add_child(e)
			e.set_aura_tier(int(_tiers.get(p.get(&"peer_id"), 0)))
		e.is_self = p.has_method(&"is_local") and p.is_local()


func _route_voices() -> void:
	for p in Players.all():
		if p == _local:
			continue
		var v := p.get(&"voice") as AudioStreamPlayer3D
		if v == null:
			continue
		if v.bus == &"Master":
			v.bus = &"World"
		elif String(v.bus).begins_with("Voice_"):
			# Voice_<peer> FX buses are made by core (VoiceFx.ensure_bus) and send to Master: re-route by name.
			var idx := AudioServer.get_bus_index(v.bus)
			if idx >= 0 and AudioServer.get_bus_send(idx) != &"World":
				AudioServer.set_bus_send(idx, &"World")


func _mage_nodes() -> Array:
	return mage_override if not mage_override.is_empty() else Players.alive_with_role(Enums.Role.MAGE)


func _chickens() -> void:
	var mages := _mage_nodes()
	if _chicken_near.size() > 256:
		_chicken_near.clear()
	for c in get_tree().get_nodes_in_group(&"chickens"):
		var cluck := c.get_node_or_null(^"Cluck") as AudioStreamPlayer3D
		if cluck and cluck.bus != &"SFX":
			cluck.bus = &"SFX" # routes through World (room echo)
		var cpos: Vector3 = (c as Node3D).global_position
		var near := false
		for m in mages:
			if (m as Node3D).global_position.distance_to(cpos) < tuning.chicken_startle_range:
				near = true
				break
		var id := c.get_instance_id()
		if near and not _chicken_near.get(id, false) and c.get(&"is_hidden") != true:
			Sfx.play_3d(&"chicken_squawk", cpos, &"SFX", tuning.chicken_squawk_range, 0.0, _rng.randf_range(0.9, 1.2))
		_chicken_near[id] = near


func _hide_spots() -> void:
	for s in get_tree().get_nodes_in_group(&"hide_spot"):
		var count := int(s.get(&"hidden_count"))
		var id := s.get_instance_id()
		var prev := int(_hide_counts.get(id, count))
		if count != prev:
			Sfx.play_3d(&"hide_enter" if count > prev else &"hide_exit", (s as Node3D).global_position, &"SFX", 10.0)
		_hide_counts[id] = count


# ---------------------------------------------------------------- c. mage cues

func _poll_mages() -> void:
	var seen := {}
	var local_id := int(_local.get(&"peer_id")) if _local else 0
	for p in Players.all():
		if int(p.get(&"role")) != Enums.Role.MAGE or not p.has_method(&"get_ability"):
			continue
		var abil := p.get_ability(&"MageAbilities") as MageAbilities
		if abil == null:
			continue
		var id := int(p.get(&"peer_id"))
		seen[id] = true
		var st: Dictionary = _mage_state.get(id, {"cd": {}, "ignited": false, "loop": null})
		_mage_state[id] = st
		var pos: Vector3 = (p as Node3D).global_position
		for a: StringName in [&"knife", &"ignite", &"fire_wave", &"locate"]:
			var c := abil.cooldown_left(a)
			var prev := float(st["cd"].get(a, c))
			if c > prev + 0.05:
				_on_cast(a, pos, id == local_id)
			elif a == &"fire_wave" and prev > 0.0 and c <= 0.0 and id == local_id:
				Sfx.play_2d(&"wave_ready", &"UI")
			st["cd"][a] = c
		var ignited := abil.is_ignited() and bool(p.get(&"is_alive"))
		if ignited != st["ignited"]:
			st["ignited"] = ignited
			if ignited:
				st["loop"] = Sfx.attach_loop(p, &"ignite_loop", &"SFX", 12.0)
				_ignite_spot = true
			elif is_instance_valid(st["loop"]):
				st["loop"].queue_free()
	for id in _mage_state.keys():
		if not seen.has(id):
			if is_instance_valid(_mage_state[id]["loop"]):
				_mage_state[id]["loop"].queue_free()
			_mage_state.erase(id)


func _on_cast(ability: StringName, pos: Vector3, is_local_mage: bool) -> void:
	match ability:
		&"knife":
			Sfx.play_3d(&"knife_swing", pos + MAGE_HEAD * 0.8, &"SFX", 12.0)
		&"ignite":
			Sfx.play_3d(&"ignite_whoosh", pos + MAGE_HEAD * 0.8, &"SFX", 18.0)
		&"fire_wave":
			Sfx.play_3d(&"fire_wave_cast", pos + MAGE_HEAD * 0.6, &"SFX", 30.0, 2.0)
		&"locate":
			if is_local_mage:
				Sfx.play_2d(&"locate_pulse", &"UI")
	print("[Audio] cast %s" % ability)


func _on_power_changed(mage_id: int, _power: float, tier: int, _multiplier: float) -> void:
	var prev := int(_tiers.get(mage_id, 0))
	_tiers[mage_id] = tier
	var e := emitter_for(mage_id)
	if e:
		e.set_aura_tier(tier)
	if tier <= prev:
		return
	var mage := Players.get_player(mage_id) as Node3D
	if _local and mage == _local:
		Sfx.play_2d(&"tier_up", &"Stingers")
	elif mage:
		Sfx.play_3d(&"tier_up", mage.global_position + MAGE_HEAD, &"SFX", 30.0)
	print("[Audio] tier up mage=%d tier=%d" % [mage_id, tier])


func _on_player_damaged(peer_id: int, amount: float, _source_id: int, cause: StringName) -> void:
	var p := Players.get_player(peer_id) as Node3D
	if p == null or amount <= 0.0:
		return
	var pos := p.global_position + Vector3.UP
	match cause:
		&"fall":
			Sfx.play_3d(&"fall_thud", p.global_position, &"SFX", tuning.land_hard_range, 2.0)
		&"firestorm":
			if p == _local and _storm_tick_cd <= 0.0:
				_storm_tick_cd = 0.35
				Sfx.play_2d(&"storm_damage_tick", &"SFX")
			return
		&"knife", &"ignite", &"fire_wave":
			Sfx.play_3d(&"hit_flesh", pos, &"SFX", 15.0)
	if int(p.get(&"role")) == Enums.Role.VILLAGER:
		Sfx.play_3d(&"villager_hurt", pos, &"SFX", 18.0, 0.0, _rng.randf_range(0.95, 1.15))


func _on_player_died(peer_id: int, killer_id: int, _cause: StringName) -> void:
	var p := Players.get_player(peer_id) as Node3D
	if p and int(p.get(&"role")) == Enums.Role.VILLAGER:
		Sfx.play_3d(&"villager_death", p.global_position + Vector3.UP, &"SFX", 25.0)
	if _local and killer_id == int(_local.get(&"peer_id")) and _local_role() == Enums.Role.MAGE:
		Sfx.play_2d(&"kill_sting", &"Stingers")


func _on_carry_changed(peer_id: int, kind: StringName) -> void:
	var p := Players.get_player(peer_id) as Node3D
	if p:
		Sfx.play_3d(&"carry_drop" if kind == &"" else &"carry_pickup", p.global_position + Vector3.UP, &"SFX", 8.0)


# ---------------------------------------------------------------- d. mage-proximity dread

func _sense_dread(dt: float, listener: Node3D) -> void:
	var role := _local_role()
	var alive := _local_alive()
	var src: Node3D = listener_override if listener_override else _local as Node3D
	var has := false
	var best := INF
	var los := false
	if role == Enums.Role.VILLAGER and alive and src:
		var ear := _ear(listener if listener_override else src)
		if not listener_override and _local and _local.get(&"camera"):
			ear = (_local.get(&"camera") as Node3D).global_position
		var nearest: Node3D
		for m in _mage_nodes():
			var d := (m as Node3D).global_position.distance_to(src.global_position)
			if d < best:
				best = d
				nearest = m
		if nearest:
			has = true
			los = not _blocked(ear, nearest.global_position + MAGE_HEAD)
	var spotted := dread.sense(has, best, los, dt, _ignite_spot)
	_ignite_spot = false
	if spotted:
		Sfx.play_2d(&"dread_spotted", &"Stingers")
		print("[Audio] dread spotted dist=%.1f" % best)
	var names := dread.active_names()
	if names != _last_dread_names:
		_last_dread_names = names
		print("[Audio] dread layers=%s dist=%.1f los=%s" % [names, best, dread.los])
	_hunter_level = 0.0
	_ghost_level = 0.0
	if not alive or role == Enums.Role.SPECTATOR:
		_ghost_level = 1.0
	elif role == Enums.Role.MAGE:
		var tier := int(_tiers.get(int(_local.get(&"peer_id")) if _local else 0, 0))
		_hunter_level = 0.45 + 0.55 * tier / 3.0


func _update_dread_mix(delta: float) -> void:
	dread.fade(delta)
	if _dread_stream:
		_dread_stream.set_sync_stream_volume(0, _lin_db(dread.levels[&"drone"]))
		_dread_stream.set_sync_stream_volume(1, _lin_db(dread.levels[&"strings"]))
		_dread_stream.set_sync_stream_volume(2, _lin_db(dread.levels[&"chase"]))
		_dread_player.volume_db = 0.0
	_heartbeat.volume_db = _lin_db(dread.levels[&"heartbeat"])
	if dread.distance < INF:
		_heartbeat.pitch_scale = lerpf(_heartbeat.pitch_scale, dread.heartbeat_pitch(), 1.0 - exp(-2.0 * delta))
	_hunter.volume_db = move_toward(_hunter.volume_db, _lin_db(_hunter_level), 30.0 * delta)
	_ghost.volume_db = move_toward(_ghost.volume_db, _lin_db(_ghost_level), 30.0 * delta)


# ---------------------------------------------------------------- e. music arc

func _on_phase_changed(phase: int, _duration: float) -> void:
	_phase = phase
	if phase == Enums.Phase.ROLE_REVEAL:
		Sfx.play_2d(&"stinger_round_start", &"Stingers")
		_props_dirty = true
	if phase == Enums.Phase.HUNT:
		_hunt_time = 0.0
	if phase == Enums.Phase.LOBBY or phase == Enums.Phase.ROLE_REVEAL:
		_stage = 0
		_tiers.clear()
		dread.reset()
	print("[Audio] phase %d" % phase)


func _on_round_ended(winner: int, _reason: String) -> void:
	var role := _local_role()
	var won := winner == (Enums.Winner.MAGE if role == Enums.Role.MAGE else Enums.Winner.VILLAGERS)
	Sfx.play_2d(&"stinger_victory" if won else &"stinger_defeat", &"Stingers")
	print("[Audio] round end stinger=%s" % ("victory" if won else "defeat"))


## Target dread from match progress. Head start / lobby = full cheer.
func _target_match_dread() -> float:
	if _phase == Enums.Phase.RESULTS:
		return match_dread
	if _phase != Enums.Phase.HUNT:
		return 0.0
	var top_tier := 0
	for t in _tiers.values():
		top_tier = maxi(top_tier, int(t))
	return clampf(tuning.hunt_base_dread + tuning.hunt_time_dread * clampf(_hunt_time / tuning.hunt_time_ramp, 0, 1)
		+ tuning.stage_dread * clampf(_stage / 3.0, 0, 1) + tuning.tier_dread * top_tier / 3.0, 0.0, 1.0)


func _update_music(delta: float) -> void:
	match_dread = move_toward(match_dread, _target_match_dread(), tuning.dread_rate * delta)
	var d := match_dread
	if _music_stream:
		_music_stream.set_sync_stream_volume(0, _lin_db(1.0 - smoothstep(0.15, 0.7, d)))
		_music_stream.set_sync_stream_volume(1, _lin_db(smoothstep(0.2, 0.75, d)))
		_music_stream.set_sync_stream_volume(2, _lin_db(smoothstep(0.55, 1.0, d)))
		_music.volume_db = 0.0
		_music.pitch_scale = lerpf(1.0, tuning.music_pitch_min, smoothstep(0.5, 1.0, d))
	var music_cut := lerpf(20000.0, tuning.music_lowpass_min_hz, smoothstep(0.6, 1.0, d))
	var storm_cut := lerpf(20000.0, tuning.storm_muffle_hz, _muffle)
	_lowpass[&"Music"].cutoff_hz = minf(music_cut, storm_cut)
	_lowpass[&"SFX"].cutoff_hz = storm_cut
	_lowpass[&"Ambience"].cutoff_hz = storm_cut
	var bucket := int(d * 10.0)
	if bucket != _last_music_bucket:
		_last_music_bucket = bucket
		print("[Audio] music dread=%.2f" % d)
	# Manual duck under proximity voice (no sidechain in Godot).
	var target_duck := tuning.voice_duck_db if _voice_active() else 0.0
	var new_duck := move_toward(_duck, target_duck, absf(tuning.voice_duck_db) / tuning.voice_duck_fade * delta)
	if not is_equal_approx(new_duck, _duck):
		_duck = new_duck
		set_bus_volume_db(&"Music", float(_bus_base.get(&"Music", tuning.music_db)))
		set_bus_volume_db(&"Ambience", float(_bus_base.get(&"Ambience", tuning.ambience_db)))


func _voice_active() -> bool:
	# WHY: core exposes no "is anyone talking" getter; read its speaker table (read-only), as the HUD does.
	var speakers: Variant = VoiceManager.get(&"_speakers")
	if not (speakers is Dictionary):
		return false
	var now := Time.get_ticks_msec() / 1000.0
	for sp: Dictionary in (speakers as Dictionary).values():
		if now - float(sp.get("last", -10.0)) < 0.3:
			return true
	return false


# ---------------------------------------------------------------- f. firestorm + g. ambience

func _on_firestorm_warning(next_stage: int, _seconds_until: float) -> void:
	var pitch := pow(2.0, 2.0 * next_stage / 12.0) # one whole step higher per stage
	Sfx.play_2d(&"storm_warning_bell", &"Stingers", 0.0, pitch)
	print("[Audio] storm warning stage=%d pitch=%.2f" % [next_stage, pitch])


func _on_firestorm_stage(stage: int, _center: Vector3, _radius: float, _required: float, _next: float) -> void:
	_stage = stage
	Sfx.play_2d(&"storm_stage_sweep", &"Stingers")
	Sfx.play_2d(&"storm_rumble_hit", &"Stingers", -2.0)
	print("[Audio] storm stage=%d" % stage)


func _update_storm(listener: Node3D, delta: float) -> void:
	var fs := GameEvents.system(&"firestorm")
	var active := false
	var target_inside := false
	_edge_factor = 1.0
	if fs and listener:
		var center: Vector3 = fs.get(&"zone_center")
		var radius := float(fs.get(&"zone_radius"))
		active = radius < 900.0 # FirestormManager parks the zone at 1000 m when inactive
		if active:
			var ear := _ear(listener)
			var target := storm_point(center, radius, ear)
			if not _storm_placed:
				storm_emitter.global_position = target
				_storm_placed = true
			else:
				storm_emitter.global_position = storm_emitter.global_position.lerp(target,
					1.0 - exp(-tuning.storm_smoothing * delta))
			_storm_crackle.global_position = storm_emitter.global_position
			var flat := Vector2(ear.x - center.x, ear.z - center.z).length()
			target_inside = flat > radius
			_edge_factor = clampf((radius - flat) / tuning.storm_edge_duck_range, 0.0, 1.0)
	if not active:
		_storm_placed = false
	in_storm = target_inside
	_storm_level = move_toward(_storm_level, 1.0 if active else 0.0, delta / 2.0)
	if storm_emitter:
		Sfx.set_base_db(storm_emitter, _lin_db(_storm_level) + 2.0)
		Sfx.set_base_db(_storm_crackle, _lin_db(_storm_level) - 2.0)
	_wind_level = move_toward(_wind_level, 1.0 if in_storm else 0.0, delta / 1.5)
	_wind.volume_db = _lin_db(_wind_level)
	_muffle = move_toward(_muffle, 1.0 if in_storm else 0.0, delta / 1.0)


func _update_ambience(listener: Node3D, delta: float) -> void:
	var life := (1.0 - 0.8 * match_dread) * _edge_factor
	_town.volume_db = move_toward(_town.volume_db, _lin_db(life * 0.8), 20.0 * delta)
	_gull_left -= delta
	if _gull_left <= 0.0:
		_gull_left = _rng.randf_range(tuning.gull_interval_min, tuning.gull_interval_max)
		if listener and life > 0.35 and _rng.randf() < life:
			var a := _rng.randf() * TAU
			var off := Vector3(cos(a), 0, sin(a)) * _rng.randf_range(25.0, 45.0) + Vector3.UP * _rng.randf_range(12, 20)
			var g := Sfx.play_3d(&"amb_gulls", _ear(listener) + off, &"Ambience", 90.0, linear_to_db(life) - 4.0)
			if g:
				g.set_meta(&"no_occlusion", true)


func _update_props(listener: Node3D) -> void:
	if _props_dirty:
		_props_dirty = false
		_props.clear()
		var scene := get_tree().current_scene
		var map := scene.get_node_or_null(^"Map") if scene else null
		if map:
			_collect_props(map)
			print("[Audio] flame props=%d" % _props.size())
	if listener == null or _prop_voices.is_empty():
		return
	var ear := _ear(listener)
	var ranked: Array = []
	for p in _props:
		if is_instance_valid(p):
			ranked.append([p.global_position.distance_squared_to(ear), p])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _prop_voices.size():
		var v := _prop_voices[i]
		var on := i < ranked.size() and float(ranked[i][0]) < pow(tuning.prop_crackle_range * 2.0, 2.0)
		if on:
			v.global_position = (ranked[i][1] as Node3D).global_position + Vector3.UP * 0.5
		v.stream_paused = not on


func _collect_props(n: Node) -> void:
	for c in n.get_children():
		if c is Node3D and PROP_SCENES.has(c.scene_file_path):
			_props.append(c)
		elif c.get_child_count() > 0:
			_collect_props(c)


static func _lin_db(level: float) -> float:
	return linear_to_db(level) if level > 0.001 else SILENT_DB
