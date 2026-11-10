class_name FootstepEmitter
extends Node3D
## Movement noise for one player: footfalls by distance travelled, jump/land/mantle, and the mage's fire aura.
## Owner: S18. Attached at runtime by AudioDirector as a child of each Player (never edit game/player/).
## NET: local audio on every peer. Reads only replicated Player state (position, is_sprinting, is_crouching,
## is_airborne, is_mantling, is_tumbling, role, is_alive), so remote players sound right too.
## Villager noise is information for the mage: sprint 14 m, walk 7 m, crouch / standing still = silent.
##
## Public API: `player`, `is_self`, `noise_range` (current audible metres, 0 = silent), `steps_played`,
## `last_cue`, `set_aura_tier(tier)`, static `noise_range_for(...)`.

## The Player (or any Node3D with the same vars, e.g. a test stub).
var player: Node3D
## The local player's own emitter: quieter, never occluded.
var is_self := false
var tuning: AudioTuning
## Audible range of the CURRENT movement, metres. 0 = makes no footstep noise.
var noise_range := 0.0
## Footfalls played so far (tests/debug).
var steps_played := 0
## Last cue this emitter played (tests/debug).
var last_cue := &""

var _step: AudioStreamPlayer3D
var _aura: AudioStreamPlayer3D
var _aura_tier := 0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _stride := 0.0
var _was_air := false
var _air_time := 0.0
var _was_mantle := false
var _step_count := 0
var _step_cue := &""


func _ready() -> void:
	if player == null:
		player = get_parent() as Node3D
	_last_pos = player.global_position
	_was_air = bool(player.get(&"is_airborne"))


## Mage power tier 0..3: the aura loop gets louder and carries farther.
func set_aura_tier(tier: int) -> void:
	_aura_tier = tier
	_apply_aura()


## Footstep range for a movement state. Pure, so tests can check sprint > walk > crouch = 0.
static func noise_range_for(t: AudioTuning, sprinting: bool, crouching: bool, speed: float, airborne: bool,
		alive: bool, quiet: bool, mage: bool) -> float:
	if not alive or quiet or crouching or airborne or speed < t.moving_speed:
		return 0.0
	var r := t.sprint_range if sprinting else t.walk_range
	return r * (t.mage_range_mult if mage else 1.0)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or delta <= 0.0:
		return
	var pos := player.global_position
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	if moved > 4.0: # WHY: teleports/respawns must not count as a huge stride
		moved = 0.0
	_speed = lerpf(_speed, moved / delta, 1.0 - exp(-delta * 8.0))
	var mage := int(player.get(&"role")) == Enums.Role.MAGE
	var alive := bool(player.get(&"is_alive"))
	var air := bool(player.get(&"is_airborne"))
	var mantling := bool(player.get(&"is_mantling"))
	var sprinting := bool(player.get(&"is_sprinting"))
	var crouching := bool(player.get(&"is_crouching"))
	var quiet := bool(player.get(&"is_tumbling")) or (player.has_method(&"stun_time_left")
		and float(player.call(&"stun_time_left")) > 0.0)
	noise_range = noise_range_for(tuning, sprinting, crouching, _speed, air, alive, quiet, mage)
	var mult := tuning.mage_range_mult if mage else 1.0
	if alive:
		if mantling and not _was_mantle:
			_event(&"mantle", tuning.mantle_range * mult, 0.0)
		elif air and not _was_air and not mantling:
			_event(&"jump_takeoff", tuning.jump_range * mult, -2.0)
		elif not air and _was_air and not mantling:
			var hard := _air_time >= tuning.hard_landing_air_time
			_event(&"land_hard" if hard else &"land_soft",
				(tuning.land_hard_range if hard else tuning.jump_range) * mult, 3.0 if hard else 0.0)
			_stride = 0.0
	_air_time = _air_time + delta if air else 0.0
	_was_air = air
	_was_mantle = mantling
	if noise_range > 0.0:
		_stride += moved
		if _stride >= (tuning.sprint_stride if sprinting else tuning.walk_stride) * (1.15 if mage else 1.0):
			_stride = 0.0
			_footfall(mage, sprinting)
	else:
		_stride = 0.0
	var want_aura := mage and alive
	if want_aura != (_aura != null):
		if want_aura:
			_aura = Sfx.attach_loop(self, &"mage_aura_loop", &"SFX")
			_mark(_aura)
			_apply_aura()
		else:
			_aura.queue_free()
			_aura = null


func _footfall(mage: bool, sprinting: bool) -> void:
	var cue := &"step_mage" if mage else &"step_villager"
	if _step == null or _step_cue != cue:
		if _step:
			_step.queue_free()
		_step = Sfx.make_3d(cue, &"SFX")
		if _step == null:
			return
		_mark(_step)
		add_child(_step)
		_step_cue = cue
	_step.max_distance = noise_range
	_step.unit_size = maxf(1.0, noise_range * 0.25)
	var db := tuning.sprint_step_db if sprinting else tuning.walk_step_db
	Sfx.set_base_db(_step, (tuning.self_step_db if is_self else db) + (2.0 if mage else 0.0))
	_step.pitch_scale = 0.85 if mage else 1.0
	if not Sfx.headless:
		_step.play()
	steps_played += 1
	last_cue = cue
	_step_count += 1
	if mage and _step_count % 3 == 0:
		_event(&"mage_ember", noise_range, -6.0)


func _event(cue: StringName, range_m: float, db: float) -> void:
	var p := Sfx.play_3d(cue, player.global_position, &"SFX", range_m,
		db + (tuning.self_step_db if is_self else 0.0))
	_mark(p)
	last_cue = cue


func _apply_aura() -> void:
	if _aura == null:
		return
	Sfx.set_base_db(_aura, tuning.mage_aura_base_db + tuning.mage_aura_db_per_tier * _aura_tier)
	_aura.max_distance = tuning.mage_aura_range + tuning.mage_aura_range_per_tier * _aura_tier
	_aura.unit_size = maxf(1.0, _aura.max_distance * 0.25)


func _mark(p: AudioStreamPlayer3D) -> void:
	if p and is_self:
		p.set_meta(&"no_occlusion", true)
