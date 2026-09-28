class_name PlayerVisual
extends Node3D
## Holds the Vigilante model and applies light procedural motion to it: lean
## into acceleration, squash on landing, tuck and tumble during traversal,
## compress when crouching. The skeleton itself only has a pose: the idle
## loop while the player stands still, the neutral stance otherwise (until
## locomotion animations exist). Both only move bones, never the body or its
## collision. The controller only uses the small API below. Ticked from the
## player's physics step so physics interpolation keeps it smooth.

const STAND_PIVOT_Y := 0.9

@export var standing_height := 1.8
@export var crouch_height := 1.1

var crouched := false
var tucked := false
## Pitch in radians set by the controller during traversals.
var traversal_pitch := 0.0
## Extra pitch from rolls, in radians.
var tumble := 0.0
## Roll in radians set by the controller while wall-running (leans the body
## off the wall, feet on it). Smoothed here.
var wall_roll := 0.0
## Set by the controller: on the ground, not moving, no input. Plays the
## idle loop; anything else holds the neutral stance.
var standing_still := false

## Skeleton pose clips in the AnimationPlayer child's library.
@export var idle_animation: StringName = &"idle"
@export var moving_animation: StringName = &"neutral"
## Crossfade between the two (seconds).
@export var pose_blend := 0.25

var _lean := Vector2.ZERO
var _wall_roll := 0.0
var _squash := 0.0
var _height_scale := 1.0
var _wobble := 0.0
var _wobble_time := 0.0
var _last_velocity := Vector3.ZERO

## Render layers for every mesh of the character model. The camera hides
## these layers when it is pushed right up against the player.
@export_flags_3d_render var model_layers := 2

@onready var _pivot: Node3D = $Pivot
@onready var _poses: AnimationPlayer = get_node_or_null(^"AnimationPlayer")


func _ready() -> void:
	for node in find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = model_layers


func on_landed(impact_speed: float) -> void:
	_squash = clampf(impact_speed / 30.0, 0.0, 0.3)


func on_jump() -> void:
	_squash = -0.12


func stumble() -> void:
	_wobble = 1.0


func tick(delta: float, velocity: Vector3, sprint_amount: float) -> void:
	var accel := (velocity - _last_velocity) / maxf(delta, 0.0001)
	_last_velocity = velocity
	# Acceleration in the body's own frame: -z forward, +x right.
	var local_accel := global_basis.inverse() * accel
	var target_lean := Vector2(
			clampf(local_accel.z * 0.012, -0.25, 0.25) - 0.1 * sprint_amount,
			clampf(-local_accel.x * 0.01, -0.22, 0.22))
	if tucked:
		target_lean = Vector2.ZERO
	_lean = _lean.lerp(target_lean, 1.0 - exp(-10.0 * delta))

	_squash = lerpf(_squash, 0.0, 1.0 - exp(-12.0 * delta))
	_wobble = move_toward(_wobble, 0.0, delta * 1.8)
	_wobble_time += delta
	var wobble_roll := sin(_wobble_time * 22.0) * 0.3 * _wobble

	var low := crouched or tucked
	var height_scale := crouch_height / standing_height if low else 1.0
	var pivot_y := STAND_PIVOT_Y * height_scale
	var blend := 1.0 - exp(-16.0 * delta)
	_pivot.position.y = lerpf(_pivot.position.y, pivot_y, blend)
	_height_scale = lerpf(_height_scale, height_scale, blend)
	_pivot.scale = Vector3(1.0 + _squash * 0.6, _height_scale * (1.0 - _squash), 1.0 + _squash * 0.6)
	_wall_roll = lerpf(_wall_roll, wall_roll, 1.0 - exp(-12.0 * delta))
	_update_pose()
	_pivot.rotation = Vector3(_lean.x + traversal_pitch + tumble, 0.0, _lean.y + wobble_roll + _wall_roll)


## The idle loop while standing still, the neutral stance otherwise.
func _update_pose() -> void:
	if _poses == null:
		return
	var want := idle_animation if standing_still else moving_animation
	if _poses.current_animation != want and _poses.has_animation(want):
		_poses.play(want, pose_blend)


## The pose clip playing now ("" without an AnimationPlayer).
func current_pose() -> StringName:
	return _poses.current_animation if _poses != null else &""
