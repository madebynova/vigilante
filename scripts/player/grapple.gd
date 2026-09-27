class_name Grapple
extends Node3D
## The grapple arrow: targeting, firing and the cable.
##
## Finds the best GrappleAnchor along the camera's aim (within range, inside
## the aim cone, with line of sight), fires a GrappleArrow at it and draws the
## cable from the player's hand to the arrow: paying out while it flies, taut
## once it has stuck. The pull itself is a player state (see Player); this
## node answers "what would I grapple to?", owns the arrow in play and shows
## the cable. Everything the grapple arrow needs lives here and in
## GrappleArrow, so a future arrow selection only decides when fire() is used.

## The arrow's nock starts this far in front of the hand, clear of the body.
const NOCK_CLEARANCE := 0.4

@export_flags_3d_physics var collision_mask := 1
@export var max_range := 35.0
## Anchors closer than this are ignored (you are basically there already).
@export var min_range := 1.5
## Half-angle of the aim cone around the camera's forward direction.
@export_range(1.0, 45.0) var aim_cone_degrees := 15.0
## A line-of-sight hit this close to the anchor still counts as a clear line
## (the anchor sits on the ledge it belongs to).
@export var line_of_sight_tolerance := 1.0

@export_group("Arrow")
## Grapple arrow flight speed in m/s (game time, so it slows with bullet time).
@export var arrow_speed := 80.0
## Height above the feet of the hand that shoots and holds the cable.
@export var hand_height := 1.3

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
## Anchor the arrow in play was fired at, or null.
var anchor: GrappleAnchor
## The arrow in play (flying or stuck), or null.
var arrow: GrappleArrow

var _cable: MeshInstance3D


func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.02
	mesh.height = 1.0
	mesh.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.12, 0.14)
	material.roughness = 0.6
	_cable = MeshInstance3D.new()
	_cable.mesh = mesh
	_cable.material_override = material
	_cable.top_level = true
	_cable.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cable.visible = false
	add_child(_cable)


## Picks the best anchor for a player whose chest is at `from`, aiming with
## `camera`. Updates the highlight and returns it (or null).
func update_target(from: Vector3, camera: Camera3D) -> GrappleAnchor:
	var best: GrappleAnchor = null
	var best_angle := aim_cone_degrees
	var aim_from := camera.global_position
	var forward := -camera.global_basis.z.normalized()
	for node in get_tree().get_nodes_in_group(GrappleAnchor.GROUP):
		var candidate := node as GrappleAnchor
		if candidate == null or not candidate.enabled:
			continue
		var distance := from.distance_to(candidate.global_position)
		if distance > max_range or distance < min_range:
			continue
		var angle := rad_to_deg(forward.angle_to(candidate.global_position - aim_from))
		if angle > best_angle or not has_line_of_sight(from, candidate.global_position):
			continue
		best = candidate
		best_angle = angle
	_set_target(best)
	return best


func has_line_of_sight(from: Vector3, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, point, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit.position as Vector3).distance_to(point) <= line_of_sight_tolerance


func clear_target() -> void:
	_set_target(null)


## Fires a grapple arrow from the player's hand at `at`. The cable pays out
## behind it; is_attached() turns true once it has stuck.
func fire(at: GrappleAnchor) -> void:
	detach()
	anchor = at
	_set_target(at)
	var hand := hand_position()
	var dir := (at.global_position - hand).normalized()
	arrow = GrappleArrow.new()
	arrow.speed = arrow_speed
	arrow.collision_mask = collision_mask
	arrow.anchor_tolerance = line_of_sight_tolerance
	add_child(arrow)
	arrow.launch(hand + dir * (GrappleArrow.LENGTH + NOCK_CLEARANCE), at)
	_update_cable()


## The arrow is stuck in its anchor and the cable is connected.
func is_attached() -> bool:
	return arrow != null and arrow.is_attached()


func is_arrow_flying() -> bool:
	return arrow != null and arrow.phase == GrappleArrow.Phase.FLYING


## Lets go: removes the arrow and cable and clears the highlight.
func detach() -> void:
	if arrow != null:
		arrow.set_physics_process(false)
		arrow.queue_free()
		arrow = null
	anchor = null
	_cable.visible = false
	_set_target(null)


func hand_position() -> Vector3:
	return (get_parent() as Node3D).global_position + Vector3.UP * hand_height


func _process(_delta: float) -> void:
	if arrow != null:
		_update_cable()


## Straight cable from the player's hand to the arrow's nock, drawn from
## interpolated positions so it stays glued to both.
func _update_cable() -> void:
	if arrow == null:
		_cable.visible = false
		return
	var body := get_parent() as Node3D
	var from := body.get_global_transform_interpolated().origin + Vector3.UP * hand_height
	var to := arrow.nock_position()
	var along := to - from
	var length := along.length()
	if length < 0.01:
		_cable.visible = false
		return
	var y := along / length
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	_cable.global_transform = Transform3D(Basis(x, y * length, z), from + along * 0.5)
	_cable.visible = true


func _set_target(value: GrappleAnchor) -> void:
	if value == target:
		return
	if target != null and is_instance_valid(target):
		target.set_targeted(false)
	target = value
	if target != null:
		target.set_targeted(true)
