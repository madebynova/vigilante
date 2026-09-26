class_name MovementSettings
extends Resource
## Tuning values for the player's locomotion.
##
## Kept in a Resource so alternate movement profiles (injured, upgraded,
## different characters) can be swapped in later without touching code.

@export_group("Speed")
@export var walk_speed := 5.0
@export var sprint_speed := 9.5
@export var crouch_speed := 2.6

@export_group("Ground")
## How fast the player reaches the target speed (m/s²).
@export var acceleration := 50.0
## How fast the player stops with no input (m/s²).
@export var deceleration := 42.0
## Used when input opposes the current velocity, for crisp direction changes.
@export var braking := 75.0
## How quickly bonus momentum above the target speed bleeds away (m/s²).
@export var overspeed_decay := 9.0

@export_group("Air")
@export var air_acceleration := 16.0
@export var air_drag := 1.0

@export_group("Jump")
@export var jump_height := 1.35
@export var gravity := 26.0
## Falling is heavier than rising: makes jumps snappy instead of floaty.
@export var fall_gravity_multiplier := 1.6
## Extra gravity while rising with jump released, giving variable jump height.
@export var jump_cut_multiplier := 2.4
@export var terminal_velocity := 45.0
## Grace period to still jump after running off an edge.
@export var coyote_time := 0.12
## A jump pressed this long before landing still fires on touchdown.
@export var jump_buffer_time := 0.14

@export_group("Rotation")
@export var turn_sharpness := 14.0
@export var air_turn_sharpness := 6.0

@export_group("Body")
@export var standing_height := 1.8
@export var crouch_height := 1.1


func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)
