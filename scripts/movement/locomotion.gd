class_name Locomotion
extends RefCounted
## Stateless velocity math for walking, sprinting, air control and gravity.
##
## Kept separate from the player so the formulas are easy to tune and could be
## reused by other characters later.


## Horizontal velocity on the ground.
static func ground(velocity: Vector3, wish_dir: Vector3, target_speed: float,
		s: MovementSettings, delta: float) -> Vector3:
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir.is_zero_approx():
		return hvel.move_toward(Vector3.ZERO, s.deceleration * delta)

	var speed := hvel.length()
	if speed > target_speed and hvel.dot(wish_dir) > 0.0:
		# Carrying bonus momentum (e.g. after a perfect window dive): steer
		# freely but bleed the extra speed gradually instead of cutting it.
		speed = move_toward(speed, target_speed, s.overspeed_decay * delta)
		var dir := hvel.normalized().slerp(wish_dir.normalized(), clampf(12.0 * delta, 0.0, 1.0))
		return dir.normalized() * speed

	var rate := s.acceleration if hvel.dot(wish_dir) >= 0.0 else s.braking
	return hvel.move_toward(wish_dir * target_speed, rate * delta)


## Horizontal velocity in the air. Steering never slows the player below
## their launch speed, so sprint jumps keep their momentum.
static func air(velocity: Vector3, wish_dir: Vector3, target_speed: float,
		s: MovementSettings, delta: float) -> Vector3:
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir.is_zero_approx():
		return hvel.move_toward(Vector3.ZERO, s.air_drag * delta)
	var cap := maxf(target_speed, hvel.length())
	return (hvel + wish_dir * s.air_acceleration * delta).limit_length(cap)


## Vertical velocity after one step of gravity.
static func apply_gravity(vertical: float, jump_held: bool, s: MovementSettings, delta: float) -> float:
	var g := s.gravity
	if vertical < 0.0:
		g *= s.fall_gravity_multiplier
	elif not jump_held:
		g *= s.jump_cut_multiplier
	return maxf(vertical - g * delta, -s.terminal_velocity)
