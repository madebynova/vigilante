class_name TraversalMotion
extends RefCounted
## A short authored movement along a smooth path (vault, climb, window dive...).
##
## The player is carried along the path over `duration` seconds at a constant
## speed, so a traversal reads as a physical action rather than a teleport.
## Parkour code builds these from sensor data; the player controller only
## plays them back. Replace the cosmetic fields with animation names once a
## real character rig exists.

const SAMPLES_PER_SEGMENT := 12

var id: StringName
var duration: float
## Velocity handed back to normal movement when the motion ends.
var exit_velocity := Vector3.ZERO
## Seconds of reduced control afterwards (used for clumsy results).
var recovery_time := 0.0
var end_crouched := false
## 0 = constant speed, 1 = strong slow-down towards the end.
var ease_out := 0.0

# Cosmetic hints for the placeholder visual and camera.
## Body tucks into a compact shape during the move.
var tuck := true
## Peak body pitch in radians (negative leans forward, e.g. a dive).
var body_pitch := 0.0
## Whole forward rolls performed near the end of the move.
var tumble_turns := 0
var start_shake := 0.0
var landing_shake := 0.0

var elapsed := 0.0

var _points := PackedVector3Array()
var _lengths := PackedFloat32Array()


func _init(p_id: StringName, control_points: PackedVector3Array, p_duration: float) -> void:
	id = p_id
	duration = maxf(p_duration, 0.01)
	_bake(control_points)


## Moves time forward and returns the new position.
func advance(delta: float) -> Vector3:
	elapsed = minf(elapsed + delta, duration)
	return sample(progress())


func progress() -> float:
	return elapsed / duration


func is_finished() -> bool:
	return elapsed >= duration


func length() -> float:
	return _lengths[_lengths.size() - 1]


func end_position() -> Vector3:
	return _points[_points.size() - 1]


## Position at normalised time t (0..1).
func sample(t: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	t = lerpf(t, 1.0 - (1.0 - t) * (1.0 - t), ease_out)
	var target := t * length()
	for i in range(1, _points.size()):
		if _lengths[i] >= target:
			var segment := _lengths[i] - _lengths[i - 1]
			var f := 0.0 if segment <= 0.0 else (target - _lengths[i - 1]) / segment
			return _points[i - 1].lerp(_points[i], f)
	return end_position()


## Bakes a centripetal Catmull-Rom spline (no loops or overshoot) into a dense
## polyline with cumulative lengths, so playback runs at constant speed.
func _bake(cp: PackedVector3Array) -> void:
	var n := cp.size()
	_points.append(cp[0])
	for i in n - 1:
		var p0 := cp[i - 1] if i > 0 else cp[0] * 2.0 - cp[1]
		var p3 := cp[i + 2] if i + 2 < n else cp[n - 1] * 2.0 - cp[n - 2]
		for step in range(1, SAMPLES_PER_SEGMENT + 1):
			_points.append(_centripetal(p0, cp[i], cp[i + 1], p3, float(step) / SAMPLES_PER_SEGMENT))
	_lengths.append(0.0)
	for i in range(1, _points.size()):
		_lengths.append(_lengths[i - 1] + _points[i - 1].distance_to(_points[i]))


static func _centripetal(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 1e-4)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-4)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-4)
	var u := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))
