class_name CounterplayTuning
extends Tuning
## Tuning for counterplay. Owner: S15. Instance: `tuning_counterplay.tres`. `--tune=` section: "counterplay".
## Defaults are the GDD numbers (mostly guesses, balance in playtests).

@export var stun_duration := 1.5 ## TUNE: s, bucket stun
@export var stun_cooldown := 20.0 ## TUNE: s per source (a villager can land one stun per this time)
@export var dr_window := 8.0 ## TUNE: s, repeated stuns inside this window are shorter
@export var dr_factor := 0.5 ## TUNE: stun length multiplier per repeat
@export var item_respawn_time := 20.0 ## TUNE: s
@export var pot_stun := 0.7 ## TUNE: s, clay pot stagger
@export var net_slow := 0.5 ## TUNE: speed multiplier from the fishing net
@export var net_slow_time := 4.0 ## TUNE: s
@export var dead_break_chance := 0.9 ## TUNE: thrown dead-area items break on the ground with this chance
@export var carry_speed_mult := 0.9 ## TUNE: carrier slow while holding an item
@export var hit_radius := 0.45 ## TUNE: m, extra reach around the mage's body for thrown items
@export var cart_stun := 1.0 ## TUNE: s, mage hit by a tipping cart
@export var cart_reach := 2.5 ## TUNE: m, how far the cart's fall reaches
@export var sheet_time := 10.0 ## TUNE: s, laundry sheet blocks sight
