class_name PlayerTuning
extends Tuning
## Shared controller tuning for villagers and mages. Owner: S03. Runs on every peer.
## Public API: exported fields; role resources support --tune=villager.FIELD=VALUE / mage.FIELD.

## TUNE: Standing height, metres.
@export var height := 1.0

## TUNE: Capsule radius, metres.
@export var radius := 0.3

## TUNE: Ground running speed, m/s.
@export var walk_speed := 4.0

## TUNE: Sprint speed, m/s.
@export var sprint_speed := 6.5

## TUNE: Ground acceleration, m/s squared.
@export var ground_acceleration := 24.0

## TUNE: Ground braking, m/s squared.
@export var ground_deceleration := 30.0

## TUNE: Air steering acceleration; preserves takeoff momentum.
@export var air_acceleration := 5.0

## TUNE: Air braking without input, m/s squared.
@export var air_deceleration := 0.0

## TUNE: Jump takeoff velocity, m/s.
@export var jump_velocity := 4.85

## TUNE: Grace time after walking off a ledge, seconds.
@export var coyote_time := 0.12

## TUNE: Jump press remembered before landing, seconds.
@export var jump_buffer := 0.14

## TUNE: Crouched capsule height, metres.
@export var crouch_height := 0.65

## TUNE: Crouched speed, m/s.
@export var crouch_speed := 2.0

## TUNE: Minimum ledge height above takeoff feet, metres.
@export var mantle_min_height := 1.2

## TUNE: Maximum ledge height above takeoff feet; prevents wall scaling.
@export var mantle_max_height := 2.0

## TUNE: Forward reach beyond capsule radius, metres.
@export var mantle_reach := 0.55

## TUNE: Extra landing inset beyond radius, metres.
@export var mantle_inset := 0.08

## TUNE: Quick pull-up duration, seconds.
@export var mantle_duration := 0.28

## TUNE: Portion of mantle spent rising before moving onto ledge.
@export var mantle_lift_fraction := 0.65

## TUNE: Wall probe height above current feet, metres.
@export var mantle_probe_height := 0.2

## TUNE: Clearance for stance and mantle shape queries, metres.
@export var collision_clearance := 0.025

## TUNE: Fall distance that triggers a tumble, metres; no damage.
@export var fall_tumble_height := 4.0

## TUNE: Drops shorter than this (metres) never hurt, however you leave the ledge.
@export var fall_story_height := 3.1

## TUNE: Multiplier on every fall damage value below.
@export var fall_damage_scale := 2.7

## TUNE: Damage (before scale) for walking/sprinting off (no jump) a drop of one story; less than a jump.
@export var fall_damage_walk_off := 4.0

## TUNE: Damage for a standing/walking jump off exactly one story; scales linearly with height.
@export var fall_damage_jump := 5.0

## TUNE: Damage for a sprinting jump off exactly one story; scales linearly with height.
@export var fall_damage_sprint_jump := 8.0

## TUNE: How many times per round a lethal fall leaves a player downed (revivable) instead of dead. 0 = falls kill.
@export var fall_downs_allowed := 1

## TUNE: hp fraction of max a player gets back when a villager revives them.
@export var revive_hp_fraction := 0.8

## TUNE: hp while downed (any damage kills).
@export var downed_hp := 1.0

## TUNE: Loss of control after a big landing, seconds.
@export var tumble_duration := 0.65

## TUNE: Visual tumble rotation, radians per second.
@export var tumble_roll_speed := 12.0

## TUNE: Player bump impulse, m/s.
@export var bump_speed := 1.8

## TUNE: Bumper recoil, m/s.
@export var bump_recoil := 0.45

## TUNE: Minimum approach speed to bump, m/s.
@export var bump_min_speed := 0.5

## TUNE: Seconds between accepted bumps from one player.
@export var bump_cooldown := 0.25

## TUNE: Server contact validation allowance, metres.
@export var bump_contact_slack := 0.25

## TUNE: Maximum health.
@export var max_hp := 100.0

## TUNE: Standing camera pivot height, metres.
@export var camera_height := 0.9

## TUNE: Third-person spring arm length, metres.
@export var camera_distance := 3.5

## TUNE: Camera shoulder offset, metres.
@export var camera_shoulder := 0.3

## TUNE: Spring arm collision margin, metres.
@export var camera_margin := 0.12

## TUNE: Base camera field of view, degrees.
@export var camera_fov := 75.0

## TUNE: Sprint field of view increase, degrees.
@export var sprint_fov_kick := 5.0

## TUNE: Camera height/FOV smoothing rate, per second.
@export var camera_response := 12.0

## TUNE: Mouse radians per pixel.
@export var mouse_sensitivity := 0.0025

## TUNE: Minimum camera pitch, radians.
@export var pitch_min := -1.2

## TUNE: Maximum camera pitch, radians.
@export var pitch_max := 0.6

## TUNE: Ground snap distance, metres.
@export var floor_snap := 0.2

## TUNE: Safety reset below this world height, metres.
@export var void_height := -20.0

## TUNE: Safety reset height, metres.
@export var respawn_height := 2.0

## TUNE: Maximum vertical component of a mantle wall normal (reject floor-like faces).
@export var mantle_wall_max_normal_y := 0.2

## TUNE: Maximum walkable floor slope, degrees.
@export var floor_max_angle_degrees := 45.0

## TUNE: lowest wall sample above airborne feet, m.
@export var mantle_space_probe_height := 0.1
## TUNE: horizontal reach beyond the capsule, m.
@export var mantle_space_reach := 0.45
## TUNE: maximum ledge rise above current airborne feet, m.
@export var mantle_space_max_rise := 1.0
## TUNE: clearance above and inside the ledge, m.
@export var mantle_space_clearance := 0.05
