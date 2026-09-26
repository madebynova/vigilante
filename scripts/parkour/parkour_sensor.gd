class_name ParkourSensor
extends Node3D
## Physics probes describing vaultable / climbable geometry in front of a body.
##
## The sensor only answers questions ("is there something to vault here?",
## "is there a ledge I can grab?"). It never moves the player, so future moves
## (wall-run, slide-under, drop-to-hang...) can reuse the same probes.
## All positions are feet positions (bottom of the capsule).


## Low / waist-high geometry the player can vault over or onto.
class Obstacle:
	## Point on the obstacle face hit by the forward probe.
	var wall_point: Vector3
	## Face normal, flattened, pointing back at the player.
	var wall_normal: Vector3
	var top_y: float
	## Height of the top above the player's feet.
	var height: float
	## Gap between the body surface and the face.
	var distance: float
	## Thickness of the obstacle; INF means "platform, land on top of it".
	var depth: float
	var landing_point: Vector3

	func is_platform() -> bool:
		return is_inf(depth)


## An edge the player can hang from or climb onto.
class Ledge:
	## Point on the face at the height of the top edge.
	var wall_point: Vector3
	var wall_normal: Vector3
	var top_y: float
	var height: float
	## Feet position while hanging from the edge.
	var hang_position: Vector3
	## Feet position after climbing up.
	var stand_position: Vector3
	## False if hanging is impossible (e.g. the ground is right below).
	var can_hang: bool
	## False if there is only room to climb up crouched.
	var can_stand: bool


@export_flags_3d_physics var collision_mask := 1
@export var body_radius := 0.35
@export var standing_height := 1.8
@export var crouch_height := 1.1

@export_group("Vault")
@export var min_vault_height := 0.3
@export var max_vault_height := 1.3
## Obstacles thicker than this are treated as platforms to vault onto.
@export var max_vault_depth := 1.2
## How far past the body surface the vault probes reach.
@export var vault_reach := 1.1

@export_group("Ledge")
@export var min_ledge_height := 0.3
@export var max_ledge_height := 2.35
@export var ledge_reach := 0.7
## Feet sit this far below the top edge while hanging.
@export var hang_depth := 1.95

const _VAULT_PROBE_HEIGHTS: Array[float] = [0.2, 0.5, 0.85, 1.15]
const _LEDGE_PROBE_HEIGHTS: Array[float] = [0.6, 1.0, 1.4, 1.8]


## Looks for something to vault in direction `dir`. Returns null if nothing
## suitable (too high, too low, no room above it, nowhere to land...).
func detect_obstacle(feet: Vector3, dir: Vector3) -> Obstacle:
	dir = _flat(dir).normalized()
	if dir == Vector3.ZERO:
		return null
	var hit := _probe_face(feet, dir, _VAULT_PROBE_HEIGHTS, vault_reach)
	if hit.is_empty():
		return null
	var normal: Vector3 = hit.normal
	var face: Vector3 = hit.position
	var top := _find_top(face, normal, feet.y + max_vault_height + 0.3, feet.y + 0.1)
	if is_nan(top):
		return null
	var height := top - feet.y
	if height < min_vault_height or height > max_vault_height:
		return null

	var inward := -normal
	var edge := Vector3(face.x, top, face.z)
	# Need headroom above the edge for a tucked body.
	if not has_clearance(edge + inward * 0.2, crouch_height * 0.8, body_radius * 0.8):
		return null

	var o := Obstacle.new()
	o.wall_point = face
	o.wall_normal = normal
	o.top_y = top
	o.height = height
	o.distance = _flat(face - feet).length() - body_radius
	o.depth = _measure_depth(face, inward, top)
	if o.is_platform():
		o.landing_point = edge + inward * (body_radius + 0.3)
		if not has_clearance(o.landing_point, crouch_height):
			return null
	else:
		var land := face + inward * (o.depth + body_radius + 0.5)
		var ground := _ray(Vector3(land.x, top + 0.5, land.z), Vector3(land.x, feet.y - 3.0, land.z))
		if ground.is_empty():
			return null # never vault into a void
		o.landing_point = ground.position
		if not has_clearance(o.landing_point, crouch_height):
			return null
	return o


## Looks for a ledge in direction `dir` within hand reach of `feet`.
func detect_ledge(feet: Vector3, dir: Vector3) -> Ledge:
	dir = _flat(dir).normalized()
	if dir == Vector3.ZERO:
		return null
	var hit := _probe_face(feet, dir, _LEDGE_PROBE_HEIGHTS, ledge_reach)
	if hit.is_empty():
		return null
	var normal: Vector3 = hit.normal
	var face: Vector3 = hit.position
	var top := _find_top(face, normal, feet.y + max_ledge_height + 0.25, feet.y + min_ledge_height - 0.1)
	if is_nan(top):
		return null
	var height := top - feet.y
	if height < min_ledge_height or height > max_ledge_height:
		return null

	var l := Ledge.new()
	l.wall_normal = normal
	l.top_y = top
	l.height = height
	l.wall_point = Vector3(face.x, top, face.z)

	# There must be a surface to stand on behind the edge (not a thin wall top).
	var stand := l.wall_point - normal * (body_radius + 0.3)
	var floor_hit := _ray(stand + Vector3.UP * 0.3, stand - Vector3.UP * 0.3)
	if floor_hit.is_empty():
		return null
	l.stand_position = floor_hit.position
	l.can_stand = has_clearance(l.stand_position, standing_height)
	if not l.can_stand and not has_clearance(l.stand_position, crouch_height):
		return null

	l.hang_position = l.wall_point + normal * (body_radius + 0.05) - Vector3.UP * hang_depth
	var ground_below := _ray(l.hang_position + Vector3.UP * 0.1, l.hang_position - Vector3.UP * 0.5)
	l.can_hang = ground_below.is_empty() \
			and has_clearance(l.hang_position, standing_height, body_radius * 0.9)
	return l


## True if a capsule of `height` standing at `feet` overlaps no geometry.
func has_clearance(feet: Vector3, height: float, radius := -1.0) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_radius if radius < 0.0 else radius
	capsule.height = maxf(height, capsule.radius * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.collision_mask = collision_mask
	params.transform = Transform3D(Basis(), feet + Vector3.UP * (capsule.height * 0.5 + 0.06))
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


## Forward rays at several heights; returns the lowest head-on hit on a
## wall-like face (normal flattened), or an empty Dictionary.
func _probe_face(feet: Vector3, dir: Vector3, heights: Array[float], reach: float) -> Dictionary:
	for h in heights:
		var from := feet + Vector3.UP * h
		var hit := _ray(from, from + dir * (body_radius + reach))
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.3:
			continue # floor, ramp or ceiling rather than a face
		n = _flat(n).normalized()
		if n.dot(dir) > -0.5:
			continue # too glancing an angle
		hit.normal = n
		return hit
	return {}


## Casts down just behind the face to find the top surface. NAN if none.
func _find_top(face: Vector3, normal: Vector3, from_y: float, to_y: float) -> float:
	var p := face - normal * 0.12
	var hit := _ray(Vector3(p.x, from_y, p.z), Vector3(p.x, to_y, p.z))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.7:
		return NAN
	return (hit.position as Vector3).y


## Walks across the top surface to find where it ends. INF if it continues.
func _measure_depth(face: Vector3, inward: Vector3, top: float) -> float:
	var d := 0.15
	while d <= max_vault_depth + 0.15:
		var p := face + inward * d
		var hit := _ray(Vector3(p.x, top + 0.3, p.z), Vector3(p.x, top - 0.3, p.z))
		if hit.is_empty() or (hit.position as Vector3).y < top - 0.25:
			return d
		d += 0.15
	return INF


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	query.hit_back_faces = false
	return get_world_3d().direct_space_state.intersect_ray(query)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
