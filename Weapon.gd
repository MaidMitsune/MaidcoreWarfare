extends Node3D
class_name Weapon

# Three separate inputs, just like Beyond Citadel:
#   UNLOAD (X) — eject the magazine manually
#   RELOAD (R) — insert a new magazine
#              — if magazine is still in: speed reload (old mag drops, bullets lost)
#   COCK   (C) — chamber a round after loading / also spam to clear jams

enum State {
	IDLE,      # magazine in, round chambered, ready to fire
	NO_MAG,    # magazine has been removed
	LOADING,   # inserting a new magazine (animation time)
	COCKING,   # chambering a round (animation time)
	JAMMED,    # failure-to-eject — spam COCK to clear
}

@export var magazine_size:   int   = 10
@export var max_reserve:     int   = 50
@export var fire_rate:       float = 0.15
@export var load_time:       float = 0.55   # seconds to insert a magazine
@export var cock_time:       float = 0.25   # seconds to chamber a round
@export var base_spread:     float = 0.01   # spread in radians at 100% condition
@export var condition_drain: float = 1.0    # % condition lost per shot
@export var bullet_scene: PackedScene

# Condition thresholds
const COND_GOOD   = 70.0
const COND_WORN   = 40.0
const COND_BAD    = 15.0

var state:         State = State.IDLE
var ammo_in_mag:   int   = 0
var ammo_reserve:  int   = 0
var is_chambered:  bool  = true
var condition:     float = 100.0
var can_fire:      bool  = true
var is_destroyed:  bool  = false

var _fire_timer:         float = 0.0
var _action_timer:       float = 0.0   # counts down during LOADING / COCKING
var _jam_presses_needed: int   = 0     # how many COCK presses to clear a jam

signal ammo_changed(in_mag: int, reserve: int, chambered: bool)
signal state_changed(new_state: State)
signal condition_changed(new_condition: float)
signal fired
signal jammed
signal jam_cleared
signal weapon_destroyed


func _ready() -> void:
	ammo_in_mag  = magazine_size
	ammo_reserve = max_reserve
	is_chambered = true
	ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)
	condition_changed.emit(condition)


func _process(delta: float) -> void:
	# Fire rate cooldown
	if _fire_timer > 0.0:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			can_fire = true

	# Loading / cocking animation timer
	if state == State.LOADING or state == State.COCKING:
		_action_timer -= delta
		if _action_timer <= 0.0:
			_finish_action()


# ── FIRE ───────────────────────────────────────────────────────────────────

func try_fire(spawn_point: Node3D, is_crouching: bool = false) -> void:
	if is_destroyed or state != State.IDLE or not can_fire:
		return
	if not is_chambered:
		return   # dry fire — need to cock

	if _roll_for_jam():
		state = State.JAMMED
		_jam_presses_needed = randi_range(3, 7)
		state_changed.emit(state)
		jammed.emit()
		return

	_do_fire(spawn_point, is_crouching)
	can_fire    = false
	_fire_timer = fire_rate

	condition = max(condition - condition_drain, 0.0)
	condition_changed.emit(condition)

	if ammo_in_mag > 0:
		ammo_in_mag -= 1
		is_chambered = true
	else:
		is_chambered = false

	ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)
	fired.emit()

	if condition <= 0.0:
		_destroy_weapon()


# ── UNLOAD (X) ─────────────────────────────────────────────────────────────
# Manually eject the magazine. Bullets inside are preserved in reserve
# (in Beyond Citadel they stay in the dropped mag — we simplify by returning them).

func try_unload() -> void:
	if is_destroyed:
		return
	if state != State.IDLE:
		return
	if ammo_in_mag == 0 and not is_chambered:
		return   # nothing to unload

	# Return partial mag bullets to reserve
	ammo_reserve += ammo_in_mag
	ammo_in_mag   = 0
	state         = State.NO_MAG
	state_changed.emit(state)
	ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)


# ── RELOAD (R) ─────────────────────────────────────────────────────────────
# If magazine is already out → normal load.
# If magazine is still in     → speed reload: old mag drops (bullets lost).

func try_load() -> void:
	if is_destroyed:
		return
	if state == State.LOADING or state == State.COCKING or state == State.JAMMED:
		return
	if ammo_reserve <= 0:
		return

	if state == State.IDLE:
		# Speed reload — dump the current magazine, bullets inside are lost
		ammo_in_mag  = 0

	# Start loading animation
	state         = State.LOADING
	_action_timer = load_time
	state_changed.emit(state)


# ── COCK (C) ───────────────────────────────────────────────────────────────
# After loading, press C to chamber a round.
# While jammed, spam C to clear the stoppage.

func try_cock() -> void:
	if is_destroyed:
		return

	if state == State.JAMMED:
		_jam_presses_needed -= 1
		if _jam_presses_needed <= 0:
			is_chambered = false   # round that jammed is lost
			state        = State.IDLE
			state_changed.emit(state)
			ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)
			jam_cleared.emit()
		return

	# Can only cock after the magazine is loaded
	if state != State.IDLE and state != State.NO_MAG:
		return
	if is_chambered:
		return   # already chambered
	if ammo_in_mag == 0:
		return   # nothing to chamber

	state         = State.COCKING
	_action_timer = cock_time
	state_changed.emit(state)


# ── ANIMATION FINISH ───────────────────────────────────────────────────────

func _finish_action() -> void:
	match state:
		State.LOADING:
			var to_load   = min(magazine_size, ammo_reserve)
			ammo_in_mag   = to_load
			ammo_reserve -= to_load
			state         = State.NO_MAG   # mag is in but not yet cocked
			# Treat it as IDLE-without-chamber so player must press C
			# We use NO_MAG as a temp — switch to IDLE but mark unchambered
			state = State.IDLE
			is_chambered  = false
			state_changed.emit(state)
			ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)

		State.COCKING:
			is_chambered = true
			state        = State.IDLE
			state_changed.emit(state)
			ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)


# ── JAM PROBABILITY ────────────────────────────────────────────────────────

func _roll_for_jam() -> bool:
	if condition > COND_WORN:
		return false
	var t      = 1.0 - (condition / COND_WORN)
	var chance = t * 0.35
	return randf() < chance


# ── SPREAD ─────────────────────────────────────────────────────────────────

func _get_spread(is_crouching: bool) -> float:
	var spread = base_spread
	if condition < COND_GOOD:
		var t  = 1.0 - (condition / COND_GOOD)
		spread = base_spread * (1.0 + t * 3.0)
	if is_crouching:
		spread *= 0.5
	return spread


# ── FIRE (override in subclasses) ─────────────────────────────────────────

func _do_fire(spawn_point: Node3D, is_crouching: bool) -> void:
	if bullet_scene == null:
		push_warning("Weapon: bullet_scene not set on " + name)
		return

	var spread = _get_spread(is_crouching)
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = spawn_point.global_transform

	var dir = spawn_point.global_transform.basis * Vector3.FORWARD * -1
	dir.x  += randf_range(-spread, spread)
	dir.y  += randf_range(-spread, spread)
	bullet.fire(dir.normalized())


# ── DESTROY ────────────────────────────────────────────────────────────────

func _destroy_weapon() -> void:
	is_destroyed = true
	weapon_destroyed.emit()
	queue_free()


# ── REPAIR ─────────────────────────────────────────────────────────────────

func repair(amount: float) -> void:
	condition = min(condition + amount, 100.0)
	condition_changed.emit(condition)
