class_name Grapple
extends Node3D
## Grapple targeting and rope.
##
## Finds the best GrappleAnchor along the camera's aim (within range, inside
## the aim cone, with line of sight) and draws a straight rope while the
## player is being pulled. The pull itself is a player state (see Player);
## this node only answers "what would I grapple to?" and shows the rope.

@export_flags_3d_physics var collision_mask := 1
@export var max_range := 35.0
## Anchors closer than this are ignored (you are basically there already).
@export var min_range := 1.5
## Half-angle of the aim cone around the camera's forward direction.
@export_range(1.0, 45.0) var aim_cone_degrees := 15.0
## A line-of-sight hit this close to the anchor still counts as a clear line
## (the anchor sits on the ledge it belongs to).
@export var line_of_sight_tolerance := 1.0

@export_group("Pull")
@export var pull_speed := 22.0
@export var pull_acceleration := 90.0
## Arrive once the feet are this close to the anchor.
@export var arrive_distance := 0.9
@export var max_pull_time := 3.0
## Hop onto the ledge on arrival.
@export var hop_up_speed := 4.5
@export var hop_forward_speed := 5.5

## Anchor the player would grapple to right now (highlighted), or null.
var target: GrappleAnchor
## Anchor the player is being pulled toward, or null.
var attached: GrappleAnchor

var _rope: MeshInstance3D


func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.02
	mesh.height = 1.0
	mesh.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.12, 0.14)
	material.roughness = 0.6
	_rope = MeshInstance3D.new()
	_rope.mesh = mesh
	_rope.material_override = material
	_rope.top_level = true
	_rope.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rope.visible = false
	add_child(_rope)


## Picks the best anchor for a player whose chest is at `from`, aiming with
## `camera`. Updates the highlight and returns it (or null).
func update_target(from: Vector3, camera: Camera3D) -> GrappleAnchor:
	var best: GrappleAnchor = null
	var best_angle := aim_cone_degrees
	var aim_from := camera.global_position
	var forward := -camera.global_basis.z.normalized()
	for node in get_tree().get_nodes_in_group(GrappleAnchor.GROUP):
		var anchor := node as GrappleAnchor
		if anchor == null or not anchor.enabled:
			continue
		var distance := from.distance_to(anchor.global_position)
		if distance > max_range or distance < min_range:
			continue
		var angle := rad_to_deg(forward.angle_to(anchor.global_position - aim_from))
		if angle > best_angle or not has_line_of_sight(from, anchor.global_position):
			continue
		best = anchor
		best_angle = angle
	_set_target(best)
	return best


func has_line_of_sight(from: Vector3, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, point, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit.position as Vector3).distance_to(point) <= line_of_sight_tolerance


func clear_target() -> void:
	_set_target(null)


func attach(anchor: GrappleAnchor) -> void:
	attached = anchor
	_set_target(anchor)
	_rope.visible = true
	_update_rope()


func detach() -> void:
	attached = null
	_rope.visible = false
	_set_target(null)


func _process(_delta: float) -> void:
	if attached != null:
		_update_rope()


## Straight rope from the player's hand height to the anchor, drawn from the
## player's interpolated position so it stays glued to the body.
func _update_rope() -> void:
	if attached == null or not is_instance_valid(attached):
		return
	var body := get_parent() as Node3D
	var from := body.get_global_transform_interpolated().origin + Vector3.UP * 1.3
	var to := attached.global_position
	var along := to - from
	var length := along.length()
	if length < 0.01:
		_rope.visible = false
		return
	var y := along / length
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	_rope.global_transform = Transform3D(Basis(x, y * length, z), from + along * 0.5)
	_rope.visible = true


func _set_target(anchor: GrappleAnchor) -> void:
	if anchor == target:
		return
	if target != null and is_instance_valid(target):
		target.set_targeted(false)
	target = anchor
	if target != null:
		target.set_targeted(true)
