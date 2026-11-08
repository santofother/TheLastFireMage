class_name Chicken
extends CharacterBody3D
## One chicken. Owner: S06. Lives under ChickenManager/$Chickens, spawned by its MultiplayerSpawner.
## NET: server simulates (authority 1); clients only display synced state ($Sync: position, rotation,
## state, carrier_id, is_hidden) and play clucks/pecking locally from `state`.
## Behaviour (server): IDLE (pecking) -> WANDER to a random reachable point (NavigationAgent3D on the map's
## navmesh via NavigationServer3D.map_get_path; straight line if the map has none) -> IDLE ...; FLEE away from living players within
## `tuning.flee_radius`. AIR after a drop/throw until it lands.
## Implements the CARRYABLE interface used by the interact system (S10), see ARCHITECTURE §Interact:
## `can_be_carried()`, `carry_speed_multiplier()`, `on_picked_up(carrier)`, `on_dropped(pos, impulse)`,
## `on_hidden(spot)`, `on_unhidden()`. All of them are called by S10 on the SERVER only.
## Death: Health.died -> GameEvents.chicken_killed(killer_id, pos) on all peers; server frees the node
## shortly after (so the death RPC reaches clients before the spawner despawns it).
## Public API: `carrier_id`, `is_hidden`, `state`, `tuning`, `health`, signal `clucked(scared)`.

enum State { IDLE, WANDER, FLEE, AIR, CARRIED, HIDDEN }

## Played a cluck (every peer, local). For tests/VFX.
signal clucked(scared: bool)

const GRAVITY := 9.8
## Fall below this y and the server puts the chicken back on its spawn point (safety net).
const KILL_Y := -20.0

## Peer id of the carrying player, 0 = free. Synced. While != 0 every peer places the chicken at the
## carrier's `carry_socket`.
var carrier_id := 0
## True while inside a hide spot. Synced.
var is_hidden := false:
	set(v):
		is_hidden = v
		if is_node_ready():
			_apply_hidden_look()
## Current behaviour (State as int). Synced on change; clients use it for clucks and pecking.
var state := State.IDLE
## Set by the manager before add_child (shared copy). Falls back to the .tres when spawned standalone.
var tuning: ChickenTuning
## Where it spawned (server), used to recover from falling out of the map.
var home := Vector3.ZERO

var _idle_left := 0.0
var _scared_left := 0.0
var _threat_check := 0.0
var _stuck_time := 0.0
var _target := Vector3.ZERO
var _cluck_left := 0.0
var _peck_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0

@onready var health: Health = $Health
@onready var cluck: AudioStreamPlayer3D = $Cluck
@onready var body: Node3D = $Body
@onready var collision: CollisionShape3D = $Collision
@onready var beacon: Node3D = $DebugBeacon

static var _cluck_stream: AudioStreamWAV


func _ready() -> void:
	if tuning == null:
		tuning = Tuning.load_tuning("res://game/chicken/tuning_chicken.tres", "chicken") as ChickenTuning
	health.max_hp = tuning.max_hp
	health.hp = tuning.max_hp
	health.died.connect(_on_died)
	cluck.stream = _make_cluck_stream()
	cluck.max_distance = tuning.noise_radius
	cluck.unit_size = tuning.noise_radius * 0.25
	_cluck_left = randf_range(0.2, tuning.cluck_interval_max)
	_idle_left = randf_range(tuning.idle_time_min, tuning.idle_time_max)
	if home == Vector3.ZERO:
		home = global_position
	_apply_hidden_look()


func _physics_process(delta: float) -> void:
	_update_cluck(delta)
	_update_look(delta)
	if carrier_id != 0:
		_follow_carrier()
		return
	if not Net.is_server(self) or not health.is_alive or is_hidden:
		return
	_simulate(delta)


# ------------------------------------------------------------------ server simulation

func _simulate(delta: float) -> void: # NET: server only
	if global_position.y < KILL_Y:
		print("[Chicken] %s fell out of the map, back home" % name)
		global_position = home
		velocity = Vector3.ZERO
	_threat_check -= delta
	if _threat_check <= 0.0 and state != State.AIR:
		_threat_check = 0.25
		_check_threats()
	var speed := 0.0
	match state:
		State.IDLE:
			_idle_left -= delta
			if _idle_left <= 0.0:
				_set_target(_random_point_near(global_position, tuning.wander_radius))
				state = State.WANDER
		State.WANDER:
			speed = tuning.walk_speed
		State.FLEE:
			speed = tuning.flee_speed
			_scared_left -= delta
		State.AIR:
			if is_on_floor() and velocity.y <= 0.0:
				_go_idle()
	var hv := Vector3.ZERO
	if speed > 0.0:
		hv = _steer(speed, delta)
	if state == State.AIR:
		velocity.x = move_toward(velocity.x, 0.0, delta * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 2.0)
	else:
		velocity.x = hv.x
		velocity.z = hv.z
	velocity.y = 0.0 if is_on_floor() and velocity.y < 0.0 else velocity.y - GRAVITY * delta
	move_and_slide()
	if hv.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(hv.x, hv.z), minf(1.0, delta * 10.0))


## Horizontal velocity along the current path; ends the leg when it arrives or gets stuck.
func _steer(speed: float, delta: float) -> Vector3:
	# WHY: own waypoint following with FLAT distances. NavigationAgent3D compares in 3D and never advanced
	# when the baked navmesh sat a few cm above the floor, so chickens jittered in place.
	while _path_i < _path.size() - 1 and _flat(_path[_path_i] - global_position).length() < 0.3:
		_path_i += 1
	var next: Vector3 = _path[_path_i] if _path_i < _path.size() else _target
	var to := _flat(next - global_position)
	var arrived := _flat(_target - global_position).length() < 0.4
	_stuck_time = _stuck_time + delta if _flat(get_real_velocity()).length() < speed * 0.2 else 0.0
	if arrived or _stuck_time > 1.0 or to.length() < 0.01:
		if state == State.FLEE and _scared_left > 0.0:
			_flee_from_nearest() # keep running
		else:
			_go_idle()
		return Vector3.ZERO
	return to.normalized() * speed


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _check_threats() -> void:
	var t := _nearest_threat()
	if t == null:
		return
	if state != State.FLEE:
		print("[Chicken] %s scared" % name)
	state = State.FLEE
	_scared_left = tuning.calm_time
	_flee_from(t.global_position)


func _flee_from_nearest() -> void:
	var t := _nearest_threat(tuning.flee_radius * 2.0)
	if t:
		_flee_from(t.global_position)
	else:
		_go_idle()


func _flee_from(threat: Vector3) -> void:
	var away := global_position - threat
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	away = away.normalized().rotated(Vector3.UP, randf_range(-0.6, 0.6))
	_set_target(_closest_on_nav(global_position + away * tuning.flee_distance))


func _nearest_threat(radius: float = -1.0) -> Node3D:
	var r := tuning.flee_radius if radius < 0.0 else radius
	var best: Node3D = null
	var best_d := r * r
	for p in Players.all():
		if not p.is_alive or p.peer_id == carrier_id:
			continue
		var d: float = ((p as Node3D).global_position - global_position).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best


func _go_idle() -> void:
	state = State.IDLE
	_idle_left = randf_range(tuning.idle_time_min, tuning.idle_time_max)
	_stuck_time = 0.0


func _set_target(p: Vector3) -> void:
	_target = p
	_stuck_time = 0.0
	_path_i = 0
	_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, p, true) \
		if _has_nav() else PackedVector3Array()
	if not _path.is_empty():
		_target = _path[_path.size() - 1]


func _has_nav() -> bool:
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_iteration_id(map) > 0 \
		and not NavigationServer3D.map_get_regions(map).is_empty()


func _random_point_near(center: Vector3, radius: float) -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius
	return _closest_on_nav(center + Vector3(cos(a) * r, 0.0, sin(a) * r))


func _closest_on_nav(p: Vector3) -> Vector3:
	if not _has_nav():
		return p
	var q := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
	return q if q != Vector3.ZERO or p.length() < 0.5 else p


# ------------------------------------------------------------------ all peers: carry, look, sound

func _follow_carrier() -> void:
	var carrier := Players.get_player(carrier_id) as Node3D
	if carrier == null:
		return
	var socket := carrier.get(&"carry_socket") as Node3D
	global_transform = socket.global_transform if socket else carrier.global_transform
	velocity = Vector3.ZERO


func _update_cluck(delta: float) -> void:
	if not health.is_alive:
		return
	_cluck_left -= delta
	if _cluck_left > 0.0:
		return
	var scared := state == State.FLEE
	var interval := tuning.scared_cluck_interval * randf_range(0.6, 1.4) if scared \
		else randf_range(tuning.cluck_interval_min, tuning.cluck_interval_max)
	if carrier_id != 0:
		interval *= tuning.carried_cluck_mult
	if is_hidden:
		interval *= tuning.hidden_cluck_mult
	_cluck_left = interval
	cluck.volume_db = (tuning.scared_cluck_db if scared else 0.0) + (tuning.hidden_cluck_db if is_hidden else 0.0)
	cluck.pitch_scale = randf_range(0.9, 1.25) * (1.15 if scared else 1.0)
	cluck.play()
	clucked.emit(scared)


## Cosmetic pecking bob while idle (every peer).
func _update_look(delta: float) -> void:
	beacon.visible = tuning.debug_beacons and carrier_id == 0
	if state == State.IDLE and carrier_id == 0:
		_peck_t += delta * 6.0
		body.rotation.x = maxf(0.0, sin(_peck_t)) * 0.6
	else:
		body.rotation.x = move_toward(body.rotation.x, 0.0, delta * 4.0)


func _apply_hidden_look() -> void:
	visible = not is_hidden and health.is_alive
	_set_collision(not is_hidden and carrier_id == 0 and health.is_alive)


func _set_collision(on: bool) -> void:
	collision.set_deferred(&"disabled", not on)


## A short two-tone "buk" (placeholder). Generated once, shared by every chicken.
static func _make_cluck_stream() -> AudioStreamWAV:
	if _cluck_stream:
		return _cluck_stream
	var rate := 22050
	var n := int(rate * 0.12)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(900.0, 520.0, t) if t < 0.5 else lerpf(700.0, 400.0, t)
		phase += TAU * f / rate
		var env := sin(PI * t) * (1.0 - 0.5 * t)
		var s := (sin(phase) + 0.3 * sin(phase * 2.0)) * env * 0.5
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	_cluck_stream = AudioStreamWAV.new()
	_cluck_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_cluck_stream.mix_rate = rate
	_cluck_stream.data = data
	return _cluck_stream


# ------------------------------------------------------------------ death

func _on_died(killer_id: int, cause: StringName) -> void: # every peer (Health RPC)
	print("[Chicken] %s killed by %d (%s)" % [name, killer_id, cause])
	GameEvents.chicken_killed.emit(killer_id, global_position)
	visible = false
	_set_collision(false)
	if Net.is_server(self):
		# WHY: freeing at once can despawn the node on clients before the death RPC arrives there.
		get_tree().create_timer(0.5).timeout.connect(queue_free)


# ------------------------------------------------------------------ Carryable (S10 calls, server only)

## Carryable: can a player pick this up right now?
func can_be_carried() -> bool:
	return health.is_alive and carrier_id == 0


## Carryable: carrier speed multiplier while carrying this.
func carry_speed_multiplier() -> float:
	return tuning.carry_speed_mult


## Carryable, NET: server only. Follows the carrier's carry_socket on every peer until dropped/hidden.
func on_picked_up(carrier: Node3D) -> void:
	carrier_id = int(carrier.get(&"peer_id"))
	is_hidden = false
	state = State.CARRIED
	velocity = Vector3.ZERO
	_set_collision(false)
	print("[Chicken] %s picked up by %d" % [name, carrier_id])


## Carryable, NET: server only. `impulse` = throw velocity (zero for a plain drop).
func on_dropped(pos: Vector3, impulse: Vector3) -> void:
	carrier_id = 0
	is_hidden = false
	global_position = pos
	velocity = impulse
	state = State.AIR
	_set_collision(true)
	print("[Chicken] %s dropped" % name)


## Carryable, NET: server only. Parks the chicken (invisible, no collision) at the spot.
func on_hidden(spot: Node3D) -> void:
	carrier_id = 0
	global_position = spot.global_position
	velocity = Vector3.ZERO
	state = State.HIDDEN
	is_hidden = true
	print("[Chicken] %s hidden" % name)


## Carryable, NET: server only. Found by the mage or taken out by a villager. S10 then either calls
## `on_picked_up` (taken out) or `on_dropped` (kicked out); on its own it just stands up idle.
func on_unhidden() -> void:
	is_hidden = false
	_go_idle()
	print("[Chicken] %s unhidden" % name)
