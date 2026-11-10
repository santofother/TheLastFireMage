class_name AudioTuning
extends Tuning
## Audio ranges, thresholds, fades and bus levels. Owner: S18. Section name for `--tune=`: `audio`
## (e.g. `--tune=audio.dread_heartbeat_range=30`). Load with `Tuning.load_tuning(PATH, "audio")`.

# ---------------------------------------------------------------- bus levels (dB). Voice must stay loudest.
@export var music_db := -12.0 # TUNE
@export var ambience_db := -10.0 # TUNE
@export var sfx_db := -3.0 # TUNE
@export var dread_db := -8.0 # TUNE
@export var stingers_db := -6.0 # TUNE
@export var ui_db := -8.0 # TUNE
## Music/ambience duck while someone nearby is talking (manual duck: Godot has no sidechain).
@export var voice_duck_db := -7.0 # TUNE
@export var voice_duck_fade := 0.25 # TUNE seconds

# ---------------------------------------------------------------- villager / mage noise (audible metres)
@export var sprint_range := 14.0 # TUNE
@export var walk_range := 7.0 # TUNE
@export var jump_range := 10.0 # TUNE
@export var land_hard_range := 12.0 # TUNE
@export var mantle_range := 8.0 # TUNE
@export var mage_range_mult := 1.3 # TUNE: mage footsteps carry farther
@export var walk_stride := 1.25 # TUNE metres per footfall
@export var sprint_stride := 1.75 # TUNE
@export var moving_speed := 0.6 # TUNE m/s: slower counts as standing still (silent)
@export var hard_landing_air_time := 0.7 # TUNE seconds airborne for the loud landing
@export var walk_step_db := -5.0 # TUNE
@export var sprint_step_db := 0.0 # TUNE
@export var self_step_db := -9.0 # TUNE: your own footsteps (quieter, never the "mage hearing" version)
@export var mage_aura_base_db := -16.0 # TUNE
@export var mage_aura_db_per_tier := 4.0 # TUNE
@export var mage_aura_range := 8.0 # TUNE
@export var mage_aura_range_per_tier := 4.0 # TUNE
@export var chicken_startle_range := 8.0 # TUNE: mage this close makes a chicken squawk
@export var chicken_squawk_range := 12.0 # TUNE (= chicken_tuning.noise_radius)

# ---------------------------------------------------------------- mage-proximity dread (villagers, LOS only)
@export var dread_drone_range := 40.0 # TUNE
@export var dread_heartbeat_range := 25.0 # TUNE
@export var dread_strings_range := 15.0 # TUNE
@export var dread_chase_range := 12.0 # TUNE
@export var dread_spotted_range := 20.0 # TUNE: LOS starting inside this = stinger + chase
@export var dread_chase_hold := 6.0 # TUNE seconds the chase layer stays armed after being spotted
@export var dread_hysteresis := 1.15 # TUNE: a layer turns off only beyond range * this
@export var dread_los_on_delay := 0.2 # TUNE seconds of LOS before layers start
@export var dread_los_off_delay := 0.5 # TUNE seconds without LOS before layers stop
@export var dread_fade_in := 1.5 # TUNE seconds 0 -> 1
@export var dread_fade_out := 3.0 # TUNE seconds 1 -> 0
@export var dread_spotted_cooldown := 12.0 # TUNE seconds between "spotted" stingers
@export var heartbeat_slow_pitch := 0.85 # TUNE at the edge of the heartbeat range
@export var heartbeat_fast_pitch := 1.9 # TUNE with the mage on top of you

# ---------------------------------------------------------------- music arc (cheer -> dread)
@export var hunt_base_dread := 0.1 # TUNE
@export var hunt_time_dread := 0.15 # TUNE added over the first `hunt_time_ramp` seconds of HUNT
@export var hunt_time_ramp := 120.0 # TUNE
@export var stage_dread := 0.5 # TUNE at the final firestorm stage
@export var tier_dread := 0.25 # TUNE at the top mage tier
@export var dread_rate := 0.05 # TUNE: match_dread moves at most this much per second
@export var music_lowpass_min_hz := 2200.0 # TUNE at full dread
@export var music_pitch_min := 0.94 # TUNE at full dread (slower, lower)

# ---------------------------------------------------------------- room echo / occlusion
@export var room_probe_range := 25.0 # TUNE metres per ray
@export var room_open_wet := 0.04 # TUNE plaza / rooftop
@export var room_closed_wet := 0.38 # TUNE cellar / alley
@export var room_smoothing := 2.5 # TUNE 1/s
@export var occlusion_sources := 6 # TUNE nearest spatial sources checked
@export var occlusion_db := -5.0 # TUNE
@export var occlusion_cutoff_hz := 1500.0 # TUNE
@export var occlusion_lows_cutoff_hz := 5000.0 # TUNE for low-heavy cues (storm roar)

# ---------------------------------------------------------------- firestorm / ambience
@export var storm_roar_range := 120.0 # TUNE
@export var storm_crackle_range := 25.0 # TUNE
@export var storm_smoothing := 4.0 # TUNE 1/s for the roar emitter sliding along the ring
@export var storm_edge_duck_range := 25.0 # TUNE: gulls/town bed fade out this close to the storm
@export var storm_muffle_hz := 900.0 # TUNE low-pass on SFX/ambience/music while inside the storm
## Sea direction from the map centre (no sea node in the map yet), so the ocean is a compass anchor.
@export var ocean_direction := Vector3(0, 0, 1) # TUNE # TODO(S18): set from the map once it has a coast marker
@export var ocean_distance := 130.0 # TUNE
@export var ocean_range := 400.0 # TUNE
@export var gull_interval_min := 4.0 # TUNE
@export var gull_interval_max := 12.0 # TUNE
@export var prop_crackle_range := 6.0 # TUNE
@export var prop_crackle_voices := 8 # TUNE nearest torch/candle/lantern props that crackle
