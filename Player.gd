extends CharacterBody3D

# ── Speed ──
const WALK_SPEED        = 8.0
const SPRINT_SPEED      = 12.0
const JUMP_VELOCITY     = 10.0

const ACCEL_GROUND      = 25.0
const DECEL_GROUND      = 25.0
const ACCEL_AIR         = 8.0

# ── Bhop / Slide-Jump ──
# When you jump out of a slide your horizontal momentum is preserved into the air.
# Chaining slide-jumps lets you build speed up to BHOP_SPEED_CAP.
# While above SPRINT_SPEED in air, input steers instead of braking.
const BHOP_SPEED_CAP    = 100.0  # hard ceiling for chained slide-jump speed
const BHOP_AIR_STEER    = 3.5   # how quickly you redirect momentum above sprint speed
const LANDING_GRACE     = 0.12  # seconds of near-zero ground friction after a fast landing

# ── Slide ──
const FRICTION_SLIDE    = 2.5
const SLIDE_STEER       = 0.17
const SLIDE_CAM_TILT    = 5.0
const FALL_TO_SLIDE     = 0.4

# ── Wall Run ───
# When airborne and moving fast near a wall, the player grabs it and runs along
# it for up to WR_DURATION seconds. Jumping during a wall run launches them off.
const WR_DETECT_DIST    = 0.7   # side-raycast length to find a wall
const WR_DURATION       = 1.8   # maximum seconds you can run on one wall
const WR_SPEED          = 11.0  # speed along the wall surface
const WR_GRAV_DRIFT     = 6.0   # rate at which vertical vel drifts to WR_SINK_SPEED
const WR_SINK_SPEED     = -1.5  # slow downward drift while on wall
const WR_JUMP_OUT       = 7.0   # horizontal push away from wall on wall-jump
const WR_JUMP_UP        = 9.0   # vertical boost on wall-jump
const WR_CAM_TILT       = 10.0  # degrees of camera roll toward the wall
const WR_FOV_ADD        = 8.0
const WR_COOLDOWN       = 0.5   # seconds before the same (or any) wall can be grabbed again
const WR_MIN_HSPEED     = 3.5   # minimum horizontal speed required to grab a wall

# ── Gravity ──
const GRAVITY_UP        = 28.0
const GRAVITY_DOWN      = 48.0

# ── Mouse Look ──
const SENSITIVITY_X     = 0.003
const SENSITIVITY_Y     = 0.003
const PITCH_MIN         = -89.0
const PITCH_MAX         = 70.0

# ── Head Bob ──
const BOB_FREQ_WALK     = 2.0
const BOB_FREQ_SPRINT   = 3.2
const BOB_AMP_WALK      = 0.05
const BOB_AMP_SPRINT    = 0.09
var   t_bob             = 0.0

# ── FOV ──
const BASE_FOV          = 75.0
const FOV_SPRINT_ADD    = 6.0
const FOV_SLIDE_ADD     = 10.0
const FOV_LERP_SPEED    = 10.0

# ── Camera ───
const CROUCH_CAM_Y      = -0.5
const CAM_LERP_SPEED    = 12.0

# ── Lean ────
const LEAN_DISTANCE     = 0.4
const LEAN_TILT         = 8.0
const LEAN_SPEED        = 10.0

# ── Runtime State ───
var is_sliding          = false
var is_crouching        = false
var slide_dir           = Vector3.ZERO
var slide_steer_input   = 0.0
var lean_input          = 0.0

# Bhop / landing
var _jumped_this_frame  = false
var _was_on_floor       = true
var _landing_timer      = 0.0

# Wall run
var is_wall_running     = false
var _wall_normal        = Vector3.ZERO
var _wr_run_dir         = Vector3.ZERO   # locked horizontal direction along the wall
var _wr_timer           = 0.0
var _wr_cooldown        = 0.0
var _wr_side            = 0              # 1 = right wall, -1 = left wall

# ── Nodes ───
@onready var head            = $head
@onready var camera          = $head/Camera3D
@onready var collision_shape = $CollisionShape3D
@onready var pistol          = $head/Pistol

# ── Health ───────
signal health_changed(new_hp: float)
var health: float     = 100.0
var max_health: float = 100.0

var cam_base_y:  float = 0.0
var head_base_x: float = 0.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	cam_base_y  = camera.transform.origin.y
	head_base_x = head.position.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY_X)
		camera.rotate_x(-event.relative.y * SENSITIVITY_Y)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event.is_action_pressed("fire"):
		pistol.try_fire($head/Pistol/SpawnPoint, is_crouching)

	if event.is_action_pressed("unload"):
		pistol.try_unload()

	if event.is_action_pressed("reload"):
		pistol.try_load()

	if event.is_action_pressed("cock"):
		pistol.try_cock()

func _physics_process(delta: float) -> void:
	# ── Reset per-frame flags ──
	_jumped_this_frame = false

	# ── Landing detection (is_on_floor() still reflects last frame here) ──
	if not _was_on_floor and is_on_floor():
		var h_spd = Vector2(velocity.x, velocity.z).length()
		if h_spd > SPRINT_SPEED:
			_landing_timer = LANDING_GRACE   # preserve speed briefly on landing
	_was_on_floor    = is_on_floor()
	_landing_timer   = max(_landing_timer - delta, 0.0)
	
	# Press the delete (del) key to exit the program quickly
	if Input.is_action_just_pressed("Exit Program"):
		get_tree().quit()

	# ── Main update order ──
	_handle_gravity(delta)
	_handle_slide()
	_handle_wall_run(delta)
	_handle_jump()
	_handle_movement(delta)
	_handle_lean(delta)
	_handle_headbob(delta)
	_handle_fov(delta)
	_handle_camera_tilt(delta)
	move_and_slide()

#  GRAVITY
func _handle_gravity(delta: float) -> void:
	if is_on_floor():
		return
	if is_wall_running:
		# Slow downward drift instead of full gravity player slides off gently
		velocity.y = move_toward(velocity.y, WR_SINK_SPEED, WR_GRAV_DRIFT * delta)
		return
	var grav = GRAVITY_DOWN if velocity.y < 0.0 else GRAVITY_UP
	velocity.y -= grav * delta

#  SLIDE
func _handle_slide() -> void:
	if is_wall_running:
		return

	var wants_crouch = Input.is_action_pressed("crouch")

	if wants_crouch and is_on_floor() and not is_sliding and velocity.y <= 0.0:
		var fall_bonus      = abs(min(velocity.y, 0.0)) * FALL_TO_SLIDE
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		var total_speed     = horizontal_speed + fall_bonus

		var current_horizontal = Vector2(velocity.x, velocity.z)
		if current_horizontal.length() > 1.0:
			slide_dir = Vector3(current_horizontal.x, 0, current_horizontal.y).normalized()
		else:
			slide_dir = -head.transform.basis.z

		is_sliding   = true
		is_crouching = false
		velocity.x   = slide_dir.x * total_speed
		velocity.z   = slide_dir.z * total_speed
		velocity.y   = 0.0

	if not wants_crouch:
		is_sliding   = false
		is_crouching = false

	if is_sliding:
		if not wants_crouch or not is_on_floor():
			is_sliding = false
			return
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed < 1.0:
			is_sliding   = false
			is_crouching = true

#  WALL RUN

# Casts a short ray to the left and right to find a wall surface.
# Returns { normal: Vector3, side: int } or an empty dict if none found.
func _get_wall_data() -> Dictionary:
	var space = get_world_3d().direct_space_state
	var right = head.global_transform.basis.x

	for side: int in [1, -1]:
		var query = PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + right * side * WR_DETECT_DIST
		)
		query.exclude = [get_rid()]
		var result = space.intersect_ray(query)
		if result:
			# Ignore floors and ceilings only grab mostly-vertical surfaces
			if abs(result.normal.y) < 0.3:
				return { "normal": Vector3(result.normal), "side": side }
	return {}


func _handle_wall_run(delta: float) -> void:
	_wr_cooldown = max(_wr_cooldown - delta, 0.0)

	# Land on floor → always ends wall run
	if is_on_floor():
		if is_wall_running:
			_end_wall_run()
		return

	# Slide state blocks wall run
	if is_sliding:
		return

	if is_wall_running:
		_wr_timer -= delta

		var wall_data = _get_wall_data()
		if _wr_timer <= 0.0 or wall_data.is_empty():
			# Timer expired or wall disappeared player falls off
			_end_wall_run()
			return

		# Refresh wall state (wall may curve slightly)
		_wall_normal = wall_data.normal
		_wr_side     = wall_data.side

		# Drive horizontal velocity along the locked run direction
		velocity.x = _wr_run_dir.x * WR_SPEED
		velocity.z = _wr_run_dir.z * WR_SPEED
		# Vertical handled by _handle_gravity

	else:
		# ── Try to start a wall run ──
		if _wr_cooldown > 0.0:
			return

		var h_speed = Vector2(velocity.x, velocity.z).length()
		if h_speed < WR_MIN_HSPEED:
			return

		var wall_data = _get_wall_data()
		if wall_data.is_empty():
			return

		# Project horizontal velocity onto the wall plane.
		# The component along the wall must be meaningful, running directly
		# into or away from the wall won't trigger a wall run.
		var h_vel            = Vector3(velocity.x, 0.0, velocity.z)
		var wall_normal_flat = Vector3(wall_data.normal.x, 0.0, wall_data.normal.z).normalized()
		var into_wall        = h_vel.dot(wall_normal_flat) * wall_normal_flat
		var along_wall       = h_vel - into_wall

		if along_wall.length() < 1.5:
			return   # not enough parallel speed don't grab

		# ── Begin wall run ───
		is_wall_running = true
		is_sliding      = false
		is_crouching    = false
		_wall_normal    = wall_data.normal
		_wr_side        = wall_data.side
		_wr_timer       = WR_DURATION
		_wr_run_dir     = along_wall.normalized()
		velocity.y      = 0.0   # cancel any downward velocity on grab


func _end_wall_run() -> void:
	is_wall_running = false
	_wr_timer       = 0.0

#  JUMP
func _handle_jump() -> void:
	if not Input.is_action_just_pressed("jump"):
		return

	if is_wall_running:
		# Launch perpendicular to the wall surface + upward
		velocity.x         = _wall_normal.x * WR_JUMP_OUT
		velocity.z         = _wall_normal.z * WR_JUMP_OUT
		velocity.y         = WR_JUMP_UP
		_end_wall_run()
		_wr_cooldown       = WR_COOLDOWN
		_jumped_this_frame = true
		return

	if not is_on_floor():
		return

	velocity.y         = JUMP_VELOCITY
	_jumped_this_frame = true
	is_sliding         = false
	is_crouching       = false

#  MOVEMENT  (ground / air / bhop)
func _handle_movement(delta: float) -> void:
	# Wall run drives its own velocity nothing to do here
	if is_wall_running:
		return

	# ── Slide ───
	if is_sliding:
		var steer = Input.get_axis("left", "right")
		slide_steer_input = steer
		if abs(steer) > 0.1:
			slide_dir = slide_dir.rotated(Vector3.UP, -steer * SLIDE_STEER * delta * 60.0 * delta)
			slide_dir = slide_dir.normalized()

		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		var new_speed        = move_toward(horizontal_speed, 0.0, FRICTION_SLIDE * delta)
		velocity.x           = slide_dir.x * new_speed
		velocity.z           = slide_dir.z * new_speed
		return

	slide_steer_input = 0.0

	# ── Target speed ────
	var target_speed: float
	if is_crouching:
		target_speed = WALK_SPEED * 0.5
	elif Input.is_action_pressed("sprint"):
		target_speed = SPRINT_SPEED
	else:
		target_speed = WALK_SPEED

	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# ── Ground ───
	# _jumped_this_frame: we just pressed jump this frame, is_on_floor() is
	# still true but we must skip ground decel or slide momentum is killed.
	if is_on_floor() and not _jumped_this_frame:
		if direction:
			velocity.x = lerp(velocity.x, direction.x * target_speed, ACCEL_GROUND * delta)
			velocity.z = lerp(velocity.z, direction.z * target_speed, ACCEL_GROUND * delta)
		else:
			# _landing_timer: freshly landed from high speed let momentum bleed
			# naturally instead of slamming to a halt.
			var decel_factor = 0.08 if _landing_timer > 0.0 else 1.0
			velocity.x = lerp(velocity.x, 0.0, DECEL_GROUND * decel_factor * delta)
			velocity.z = lerp(velocity.z, 0.0, DECEL_GROUND * decel_factor * delta)

	# ── Air / bhop ────
	else:
		var h_speed = Vector2(velocity.x, velocity.z).length()

		if h_speed > SPRINT_SPEED and direction.length() > 0.1:
			# Above sprint speed steer without braking.
			# Input redirects the velocity vector toward the look direction
			# while keeping the current magnitude (up to BHOP_SPEED_CAP).
			var current_h = Vector3(velocity.x, 0.0, velocity.z)
			var steered   = current_h.lerp(direction * h_speed, BHOP_AIR_STEER * delta)
			var steered2d = Vector2(steered.x, steered.z)
			if steered2d.length() > BHOP_SPEED_CAP:
				steered2d = steered2d.normalized() * BHOP_SPEED_CAP
				steered.x = steered2d.x
				steered.z = steered2d.y
			velocity.x = steered.x
			velocity.z = steered.z
		else:
			# Normal air movement
			velocity.x = lerp(velocity.x, direction.x * target_speed, ACCEL_AIR * delta)
			velocity.z = lerp(velocity.z, direction.z * target_speed, ACCEL_AIR * delta)

#  LEAN
func _handle_lean(delta: float) -> void:
	# Lean is suppressed during slides and wall runs
	if is_sliding or is_wall_running:
		lean_input = 0.0
	elif Input.is_action_pressed("lean_right"):
		lean_input = 1.0
	elif Input.is_action_pressed("lean_left"):
		lean_input = -1.0
	else:
		lean_input = 0.0

	var target_x   = head_base_x + lean_input * LEAN_DISTANCE
	head.position.x = lerp(head.position.x, target_x, LEAN_SPEED * delta)

#  HEAD BOB
func _handle_headbob(delta: float) -> void:
	if is_wall_running:
		# No bob on walls just center the camera
		camera.transform.origin.x = lerp(camera.transform.origin.x, 0.0, CAM_LERP_SPEED * delta)
		camera.transform.origin.y = lerp(camera.transform.origin.y, cam_base_y, CAM_LERP_SPEED * delta)
		return

	if is_sliding or is_crouching:
		camera.transform.origin.y = lerp(camera.transform.origin.y, cam_base_y + CROUCH_CAM_Y, CAM_LERP_SPEED * delta)
		camera.transform.origin.x = lerp(camera.transform.origin.x, 0.0, CAM_LERP_SPEED * delta)
		return

	var is_moving = velocity.length() > 0.2 and is_on_floor()
	var freq = BOB_FREQ_SPRINT if Input.is_action_pressed("sprint") else BOB_FREQ_WALK
	var amp  = BOB_AMP_SPRINT  if Input.is_action_pressed("sprint") else BOB_AMP_WALK

	if is_moving:
		t_bob += delta * velocity.length()
		var bob_offset = Vector3(
			cos(t_bob * freq / 2.0) * amp,
			sin(t_bob * freq) * amp,
			0.0
		)
		camera.transform.origin.x = lerp(camera.transform.origin.x, bob_offset.x, delta * 10.0)
		camera.transform.origin.y = lerp(camera.transform.origin.y, cam_base_y + bob_offset.y, delta * 10.0)
	else:
		camera.transform.origin.x = lerp(camera.transform.origin.x, 0.0, delta * 10.0)
		camera.transform.origin.y = lerp(camera.transform.origin.y, cam_base_y, delta * 10.0)

#  FOV
func _handle_fov(delta: float) -> void:
	var target_fov = BASE_FOV
	if is_wall_running:
		target_fov += WR_FOV_ADD
	elif is_sliding:
		target_fov += FOV_SLIDE_ADD
	elif Input.is_action_pressed("sprint"):
		target_fov += FOV_SPRINT_ADD
	camera.fov = lerp(camera.fov, target_fov, FOV_LERP_SPEED * delta)

#  CAMERA TILT
func _handle_camera_tilt(delta: float) -> void:
	var target_roll = 0.0

	if is_wall_running:
		# Tilt toward the wall.  _wr_side: 1 = right wall → tilt right (negative roll)
		target_roll = deg_to_rad(WR_CAM_TILT * _wr_side)
	elif is_sliding and abs(slide_steer_input) > 0.1:
		target_roll = deg_to_rad(-SLIDE_CAM_TILT * slide_steer_input)
	elif not is_sliding:
		target_roll = deg_to_rad(-LEAN_TILT * lean_input)

	camera.rotation.z = lerp(camera.rotation.z, target_roll, CAM_LERP_SPEED * delta)
