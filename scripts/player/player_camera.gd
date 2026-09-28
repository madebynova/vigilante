class_name PlayerCamera
extends Node3D
## Third-person orbit camera.
##
## A top-level node that follows the player's interpolated position every
## rendered frame. Yaw rotates this node, pitch rotates the child pivot, and
## the Camera3D is pulled in with a sphere cast so it never clips into walls.
## Also owns mouse capture: Esc releases the mouse, left click recaptures it.

@export var target: Node3D

@export_group("Orbit")
@export var mouse_sensitivity := 0.0022
@export_range(-89.0, 0.0) var min_pitch_degrees := -70.0
@export_range(0.0, 89.0) var max_pitch_degrees := 50.0

@export_group("Framing")
@export var distance := 4.3
@export var pivot_height := 1.55
@export var crouch_pivot_height := 1.05
## Sideways offset for an over-the-shoulder view.
@export var shoulder_offset := 0.4

@export_group("Smoothing")
@export var follow_sharpness := 18.0
## Lower than follow_sharpness so jumps and vaults don't jerk the view.
@export var vertical_sharpness := 9.0
## How quickly the camera eases back out after a collision pulled it in.
@export var zoom_out_sharpness := 5.0

@export_group("Collision")
@export_flags_3d_physics var collision_mask := 1
@export var probe_radius := 0.22
## Render layers hidden from the camera when it is pulled in closer than
## `hide_distance`, so the player's own body never fills the screen.
@export_flags_3d_render var hide_layers_when_close := 2
@export var hide_distance := 1.0

@export_group("Field of View")
@export var base_fov := 70.0
@export var sprint_fov := 80.0
@export var fov_sharpness := 6.0
## FOV change at full focus (negative tightens), used during traversal sequences.
@export var focus_fov_offset := -7.0

@export_group("Wall run")
## Slight roll away from the wall while wall-running, for readability.
@export var wall_run_roll_degrees := 4.0

var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var crouched := false
## 0..1, drives the sprint FOV kick.
var speed_amount := 0.0
## 0..1, temporary FOV tightening for focus moments (window sequence).
var focus_amount := 0.0
## Fraction of the full boom length currently in use (1 = unobstructed).
var boom_fraction := 1.0
## Normal of the wall the player is running along (ZERO when not wall-running).
## The shoulder offset moves to the open side so the wall doesn't swallow the
## camera, and the view rolls slightly away from the wall. Yaw and pitch stay
## entirely with the player.
var wall_normal := Vector3.ZERO

var _focus := Vector3.ZERO
var _height := 1.55
var _shake := 0.0
var _shoulder := 0.4
var _roll := 0.0
var _probe := SphereShape3D.new()

@onready var _pitch_pivot: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Camera3D


func _ready() -> void:
	top_level = true
	_probe.radius = probe_radius
	if target:
		yaw = target.global_rotation.y
	snap()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Jumps straight to the target without smoothing (spawn, respawn).
func snap() -> void:
	_height = pivot_height
	_shoulder = shoulder_offset
	_roll = 0.0
	if target:
		_focus = target.global_position + Vector3.UP * _height
	boom_fraction = 1.0
	_update_transform(0.0)


func add_look_input(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


## Basis used to turn stick/WASD input into world-space movement.
func yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look_input((event as InputEventMouseMotion).screen_relative)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if target == null:
		return
	var goal_height := crouch_pivot_height if crouched else pivot_height
	_height = lerpf(_height, goal_height, _blend(10.0, delta))
	var goal := target.get_global_transform_interpolated().origin + Vector3.UP * _height
	var h := _blend(follow_sharpness, delta)
	_focus.x = lerpf(_focus.x, goal.x, h)
	_focus.z = lerpf(_focus.z, goal.z, h)
	_focus.y = lerpf(_focus.y, goal.y, _blend(vertical_sharpness, delta))
	# FOV, shake and the wall-run framing run on real time so slow-motion
	# doesn't drag them out.
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	var shoulder_goal := shoulder_offset
	var roll_goal := 0.0
	var across := wall_normal.dot(global_basis.x) # > 0: wall on the camera's left
	if absf(across) > 0.2: # (looking straight at or away from it: default framing)
		var wall_side := signf(across)
		shoulder_goal = shoulder_offset * wall_side
		roll_goal = -wall_side * deg_to_rad(wall_run_roll_degrees)
	_shoulder = lerpf(_shoulder, shoulder_goal, _blend(6.0, real_delta))
	_roll = lerpf(_roll, roll_goal, _blend(8.0, real_delta))
	_update_transform(delta)

	var target_fov := lerpf(base_fov, sprint_fov, speed_amount) + focus_fov_offset * focus_amount
	camera.fov = lerpf(camera.fov, target_fov, _blend(fov_sharpness, real_delta))
	_shake = move_toward(_shake, 0.0, real_delta * 1.5)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.15
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.15


func _update_transform(delta: float) -> void:
	global_position = _focus
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_pivot.rotation = Vector3(pitch, 0.0, 0.0)

	var boom := Vector3(_shoulder, 0.0, distance)
	var free := _free_fraction(_focus, _pitch_pivot.global_basis * boom)
	if free < boom_fraction or delta <= 0.0:
		boom_fraction = free # pull in instantly so we never see through walls
	else:
		boom_fraction = lerpf(boom_fraction, free, _blend(zoom_out_sharpness, delta))
	camera.position = boom * boom_fraction
	camera.rotation.z = _roll
	if camera.position.length() < hide_distance:
		camera.cull_mask &= ~hide_layers_when_close
	else:
		camera.cull_mask |= hide_layers_when_close


func _free_fraction(from: Vector3, motion: Vector3) -> float:
	if not is_inside_tree():
		return 1.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.collision_mask = collision_mask
	params.transform = Transform3D(Basis(), from)
	params.motion = motion
	var result := get_world_3d().direct_space_state.cast_motion(params)
	return result[0] if result.size() > 0 else 1.0


static func _blend(sharpness: float, delta: float) -> float:
	return 1.0 - exp(-sharpness * delta)
