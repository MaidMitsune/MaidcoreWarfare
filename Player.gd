extends CharacterBody3D

const WALK_SPEED       = 8.0
const SPRINT_SPEED     = 12.0
const JUMP_VELOCITY    = 10.0

const ACCEL_GROUND     = 25.0
const DECEL_GROUND     = 25.0
const ACCEL_AIR        = 8.0

const FRICTION_SLIDE   = 2.5

const GRAVITY_UP       = 28.0
const GRAVITY_DOWN     = 48.0

const SENSITIVITY_X    = 0.003
const SENSITIVITY_Y    = 0.003
const PITCH_MIN        = -89.0
const PITCH_MAX        = 70.0

const BOB_FREQ_WALK    = 2.0
const BOB_FREQ_SPRINT  = 3.2
const BOB_AMP_WALK     = 0.05
const BOB_AMP_SPRINT   = 0.09
var t_bob = 0.0

const BASE_FOV         = 75.0
const FOV_SPRINT_ADD   = 6.0
const FOV_SLIDE_ADD    = 10.0
const FOV_LERP_SPEED   = 10.0

const CROUCH_CAM_Y     = -0.5
const CAM_LERP_SPEED   = 12.0

const SLIDE_STEER      = 0.17
const SLIDE_CAM_TILT   = 5.0
const FALL_TO_SLIDE    = 0.4

const LEAN_DISTANCE    = 0.4
const LEAN_TILT        = 8.0
const LEAN_SPEED       = 10.0

var is_sliding         = false
var is_crouching       = false
var slide_dir          = Vector3.ZERO
var slide_steer_input  = 0.0
var lean_input         = 0.0

@onready var head            = $head
@onready var camera          = $head/Camera3D
@onready var collision_shape = $CollisionShape3D
@onready var pistol          = $head/Pistol

var cam_base_y: float = 0.0
var head_base_x: float = 0.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	cam_base_y = camera.transform.origin.y
	head_base_x = head.position.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY_X)
		camera.rotate_x(-event.relative.y * SENSITIVITY_Y)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event.is_action_pressed("fire"):
		pistol.try_fire($head/Pistol/SpawnPoint)

	if event.is_action_pressed("reload"):
		pistol.start_reload()


func _physics_process(delta: float) -> void:
	_handle_gravity(delta)
	_handle_slide()
	_handle_jump()
	_handle_movement(delta)
	_handle_lean(delta)
	_handle_headbob(delta)
	_handle_fov(delta)
	_handle_camera_tilt(delta)
	move_and_slide()


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		var grav = GRAVITY_DOWN if velocity.y < 0.0 else GRAVITY_UP
		velocity.y -= grav * delta


func _handle_slide() -> void:
	var wants_crouch = Input.is_action_pressed("crouch")

	if wants_crouch and is_on_floor() and not is_sliding and velocity.y <= 0.0:
		var fall_bonus = abs(min(velocity.y, 0.0)) * FALL_TO_SLIDE
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		var total_speed = horizontal_speed + fall_bonus

		var current_horizontal = Vector2(velocity.x, velocity.z)
		if current_horizontal.length() > 1.0:
			slide_dir = Vector3(current_horizontal.x, 0, current_horizontal.y).normalized()
		else:
			slide_dir = -head.transform.basis.z

		is_sliding = true
		is_crouching = false
		velocity.x = slide_dir.x * total_speed
		velocity.z = slide_dir.z * total_speed
		velocity.y = 0.0

	if not wants_crouch:
		is_sliding = false
		is_crouching = false

	if is_sliding:
		if not wants_crouch or not is_on_floor():
			is_sliding = false
			return
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed < 1.0:
			is_sliding = false
			is_crouching = true


func _handle_jump() -> void:
	if not Input.is_action_just_pressed("jump") or not is_on_floor():
		return
	velocity.y = JUMP_VELOCITY
	is_sliding = false
	is_crouching = false


func _handle_movement(delta: float) -> void:
	if is_sliding:
		var steer = Input.get_axis("left", "right")
		slide_steer_input = steer
		if abs(steer) > 0.1:
			slide_dir = slide_dir.rotated(Vector3.UP, -steer * SLIDE_STEER * delta * 60.0 * delta)
			slide_dir = slide_dir.normalized()

		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		var new_speed = move_toward(horizontal_speed, 0.0, FRICTION_SLIDE * delta)
		velocity.x = slide_dir.x * new_speed
		velocity.z = slide_dir.z * new_speed
		return

	slide_steer_input = 0.0

	var target_speed: float
	if is_crouching:
		target_speed = WALK_SPEED * 0.5
	elif Input.is_action_pressed("sprint"):
		target_speed = SPRINT_SPEED
	else:
		target_speed = WALK_SPEED

	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if is_on_floor():
		if direction:
			velocity.x = lerp(velocity.x, direction.x * target_speed, ACCEL_GROUND * delta)
			velocity.z = lerp(velocity.z, direction.z * target_speed, ACCEL_GROUND * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, DECEL_GROUND * delta)
			velocity.z = lerp(velocity.z, 0.0, DECEL_GROUND * delta)
	else:
		velocity.x = lerp(velocity.x, direction.x * target_speed, ACCEL_AIR * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, ACCEL_AIR * delta)


func _handle_lean(delta: float) -> void:
	if is_sliding:
		lean_input = 0.0
	elif Input.is_action_pressed("lean_right"):
		lean_input = 1.0
	elif Input.is_action_pressed("lean_left"):
		lean_input = -1.0
	else:
		lean_input = 0.0

	var target_x = head_base_x + lean_input * LEAN_DISTANCE
	head.position.x = lerp(head.position.x, target_x, LEAN_SPEED * delta)


func _handle_headbob(delta: float) -> void:
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


func _handle_fov(delta: float) -> void:
	var target_fov = BASE_FOV
	if is_sliding:
		target_fov += FOV_SLIDE_ADD
	elif Input.is_action_pressed("sprint"):
		target_fov += FOV_SPRINT_ADD
	camera.fov = lerp(camera.fov, target_fov, FOV_LERP_SPEED * delta)


func _handle_camera_tilt(delta: float) -> void:
	var target_roll = 0.0
	if is_sliding and abs(slide_steer_input) > 0.1:
		target_roll = deg_to_rad(SLIDE_CAM_TILT * slide_steer_input)
	elif not is_sliding:
		target_roll = deg_to_rad(-LEAN_TILT * lean_input)
	camera.rotation.z = lerp(camera.rotation.z, target_roll, CAM_LERP_SPEED * delta)
