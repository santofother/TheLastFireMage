class_name MageCombatTuning
extends Tuning
## Tuning for mage. Owner: S09. Instance: `tuning_mage_combat.tres`. `--tune=` section: "mage_combat".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var knife_damage := 20.0 ## TUNE: hp
@export var knife_cooldown := 0.7 ## TUNE: s
@export var knife_range := 1.6 ## TUNE: m
@export var knife_angle_deg := 60.0 ## TUNE: deg, full cone
@export var ignite_duration := 5.0 ## TUNE: s
@export var ignite_cooldown := 10.0 ## TUNE: s
@export var ignite_damage := 40.0 ## TUNE: hp per ignited swing
# FIX(S14, Codex): Fire Wave comes back faster at each unlocked mage tier.
@export var wave_cooldown := 15.0 ## TUNE: base seconds
@export var wave_cooldown_per_tier := 0.8 ## TUNE: remaining fraction of cooldown per tier
@export var wave_damage := 35.0 ## TUNE: hp against chickens and other targets
@export var wave_player_damage := 45.0 ## TUNE: hp against players
@export var wave_range := 6.0 ## TUNE: m
@export var wave_angle_deg := 60.0 ## TUNE: deg
@export var wave_knockback := 6.0 ## TUNE: m/s impulse

## FIX(S14, Codex): TUNE: Maximum distance to a villager for a locator pulse, in meters.
@export var locator_range := 20.0
## TUNE: Seconds between locator pulses.
@export var locator_interval := 4.0
