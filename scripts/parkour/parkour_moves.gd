class_name ParkourMoves
extends RefCounted
## Turns ParkourSensor results into playable TraversalMotions.
## Tweak the numbers here to change how each move looks and flows.

const UP := Vector3.UP


## Vault over a thin obstacle, or onto a deep one.
static func vault(o: ParkourSensor.Obstacle, start: Vector3, speed: float) -> TraversalMotion:
	var inward := -o.wall_normal
	var edge := Vector3(o.wall_point.x, o.top_y, o.wall_point.z)
	var travel := maxf(speed, 5.5)
	var pts := PackedVector3Array([start])
	var m: TraversalMotion
	if o.is_platform():
		pts.append(edge + o.wall_normal * 0.25 + UP * 0.3)
		pts.append(o.landing_point + UP * 0.08)
		m = TraversalMotion.new(&"vault_onto", pts, 1.0)
		m.duration = clampf(m.length() / travel, 0.28, 0.55)
		m.exit_velocity = inward * travel * 0.85
		m.body_pitch = -0.3
	else:
		pts.append(edge + o.wall_normal * 0.2 + UP * 0.3)
		pts.append(edge + inward * (o.depth * 0.5) + UP * 0.4)
		pts.append(o.landing_point)
		m = TraversalMotion.new(&"vault_over", pts, 1.0)
		m.duration = clampf(m.length() / travel, 0.3, 0.6)
		m.exit_velocity = inward * travel * 0.95
		m.body_pitch = -0.5
	return m


## Pull up over a ledge. `from_air` = quick mantle straight out of a jump,
## otherwise a slower climb from a hang.
static func climb_up(l: ParkourSensor.Ledge, start: Vector3, from_air: bool) -> TraversalMotion:
	var n := l.wall_normal
	var pts := PackedVector3Array([start])
	var close := l.wall_point + n * 0.4
	pts.append(Vector3(close.x, maxf(start.y, l.top_y - 0.7), close.z))
	pts.append(l.wall_point - n * 0.1 + UP * 0.35)
	pts.append(l.stand_position)
	var m := TraversalMotion.new(&"mantle" if from_air else &"climb_up", pts, 0.42 if from_air else 0.6)
	m.ease_out = 0.5
	m.tuck = true
	m.body_pitch = -0.35
	m.end_crouched = not l.can_stand
	m.exit_velocity = -n * 1.5
	return m
