class_name TraversalWindow
extends Area3D
## A wall opening the player can dive or climb through.
##
## Place the node on the sill at the centre of the opening, with its local Z
## axis pointing through the wall. The child CollisionShape3D is the approach
## zone and should cover both sides. The player registers itself while inside
## the zone and asks this node whether an approach qualifies and which
## TraversalMotion to play.

## How the traversal is performed.
enum Style { DIVE, VAULT, CLIMB }

@export var opening_width := 1.6
@export var opening_height := 1.2
@export var wall_thickness := 0.3

@export_group("Triggering")
## Dive window: only the Traverse button (E) takes it, as a dive, from either
## side. Running or jumping into it does nothing. When false it is a plain
## window: sprinting into it vaults, E / Jump climbs through.
@export var dive_window := true
## Dive window: how far from the wall pressing E starts the dive.
@export var dive_distance := 3.0
## Plain window: horizontal speed at which running into it vaults.
@export var auto_speed := 7.0
## Distance from the wall where the player leaves the ground.
@export var takeoff_distance := 1.2
## Max distance from the wall for a slow, button-pressed climb-through.
@export var climb_distance := 1.7
## How far past the wall the player lands.
@export var landing_distance := 1.9


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## +1 or -1 depending on which side of the wall `pos` is.
func side_of(pos: Vector3) -> float:
	return 1.0 if to_local(pos).z >= 0.0 else -1.0


func distance_to_wall(pos: Vector3) -> float:
	return absf(to_local(pos).z)


## Unit vector pointing through the opening, away from `pos`'s side.
func through_direction(pos: Vector3) -> Vector3:
	return -global_basis.z.normalized() * side_of(pos)


## True if heading `dir` from `pos` points through the opening: roughly
## square to the wall, and aimed so it would pass through the gap.
func is_lined_up(pos: Vector3, dir: Vector3) -> bool:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return false
	flat = flat.normalized()
	if flat.dot(through_direction(pos)) < 0.8:
		return false
	var local_pos := to_local(pos)
	var local_dir := global_basis.inverse() * flat
	var x_at_wall := local_pos.x + local_dir.x * absf(local_pos.z / local_dir.z)
	return absf(x_at_wall) <= opening_width * 0.5 + 0.2


## True if `point` is on this opening's sill. Used to stop generic vaults
## from taking a dive window without the Traverse button.
func covers_point(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= opening_width * 0.5 + 0.1 \
			and absf(local.z) <= wall_thickness * 0.5 + 0.15 and local.y <= opening_height


## Where the player should leave the ground, on `pos`'s side. Never further
## out than `pos` itself, so a close start never steps backwards.
func takeoff_point(pos: Vector3) -> Vector3:
	var local := to_local(pos)
	var depth := minf(takeoff_distance, absf(local.z))
	return to_global(Vector3(_lane_x(local.x), local.y, side_of(pos) * depth))


## Builds the movement through the opening from `start`.
func build_motion(start: Vector3, speed: float, style: Style) -> TraversalMotion:
	var s := side_of(start)
	var x := _lane_x(to_local(start).x)
	var half := wall_thickness * 0.5
	var land := _landing_point(x, s)
	var pts := PackedVector3Array([start])
	var m: TraversalMotion
	match style:
		Style.DIVE:
			# Low, fast, horizontal dive that rolls out with extra speed.
			pts.append(to_global(Vector3(x, -0.1, s * (half + 0.45))))
			pts.append(to_global(Vector3(x, -0.25, 0.0)))
			pts.append(to_global(Vector3(x, -0.45, -s * (half + 0.6))))
			pts.append(land)
			m = TraversalMotion.new(&"window_dive", _ahead_of(pts, start), 1.0)
			m.duration = clampf(m.length() / (speed * 1.05), 0.35, 0.6)
			m.exit_velocity = through_direction(start) * speed * 1.12
			m.body_pitch = -1.4
			m.tumble_turns = 1
			m.landing_shake = 0.15
		Style.VAULT:
			# Hands on the sill, legs swing through.
			pts.append(to_global(Vector3(x, 0.0, s * (half + 0.35))))
			pts.append(to_global(Vector3(x, 0.08, 0.0)))
			pts.append(to_global(Vector3(x, -0.1, -s * (half + 0.5))))
			pts.append(land)
			m = TraversalMotion.new(&"window_vault", _ahead_of(pts, start), 1.0)
			m.duration = clampf(m.length() / (speed * 0.9), 0.45, 0.85)
			m.exit_velocity = through_direction(start) * maxf(speed * 0.85, 5.0)
			m.body_pitch = -0.4
		_:
			# Slow, deliberate climb through for walking approaches.
			pts.append(to_global(Vector3(x, 0.0, s * (half + 0.3))))
			pts.append(to_global(Vector3(x, 0.1, 0.0)))
			pts.append(to_global(Vector3(x, -0.1, -s * (half + 0.45))))
			pts.append(land)
			m = TraversalMotion.new(&"window_climb", _ahead_of(pts, start), 0.95)
			m.ease_out = 0.3
			m.exit_velocity = through_direction(start) * 1.5
			m.body_pitch = -0.2
	return m


## Drops path points that aren't ahead of `start` (a start already close to
## the wall would otherwise step backwards before going through).
func _ahead_of(pts: PackedVector3Array, start: Vector3) -> PackedVector3Array:
	var s := side_of(start)
	var start_depth := s * to_local(start).z
	var kept := PackedVector3Array([pts[0]])
	for i in range(1, pts.size()):
		if s * to_local(pts[i]).z < start_depth - 0.1:
			kept.append(pts[i])
	return kept


func _lane_x(local_x: float) -> float:
	var limit := maxf(opening_width * 0.5 - 0.35, 0.0)
	return clampf(local_x, -limit, limit)


func _landing_point(x: float, side: float) -> Vector3:
	var above := to_global(Vector3(x, 0.5, -side * landing_distance))
	var below := to_global(Vector3(x, -3.0, -side * landing_distance))
	var query := PhysicsRayQueryParameters3D.create(above, below, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else below


func _on_body_entered(body: Node3D) -> void:
	if body.has_method(&"register_window"):
		body.register_window(self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method(&"unregister_window"):
		body.unregister_window(self)
