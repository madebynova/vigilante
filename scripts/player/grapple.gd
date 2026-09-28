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
##
## Balance: the grapple extends movement rather than replacing it. The pull
## is strongest when fired on the move (see pull_speed_for), and after a
## grapple the next arrow takes a moment to nock unless a parkour move gets
## there first (see nock()). The reach stays long so wall-jump -> grapple and
## window -> grapple lines keep working.

## The arrow's nock starts this far in front of the hand, clear of the body.
const NOCK_CLEARANCE := 0.4

## Why the anchor under the aim can't be grappled right now (reticle readout).
enum Block { NONE, TOO_FAR, TOO_CLOSE, BLOCKED }

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
## Pull speed when fired carrying momentum (sprinting, jumping, diving,
## falling)...
@export var pull_speed := 22.0
## ...and from a standstill: a steady winch rather than a launch...
@export var pull_speed_standing := 13.0
## ...scaling up from below 2 m/s to pull_speed at this much speed when the
## pull starts (m/s): a sprint gets the full pull, a walk about 17 m/s.
@export var momentum_speed := 9.0
@export var pull_acceleration := 90.0
## Arrive once the feet are this close to the anchor.
@export var arrive_distance := 0.9
@export var max_pull_time := 3.0
## Hop onto the ledge on arrival.
@export var hop_up_speed := 4.5
@export var hop_forward_speed := 5.5

@export_group("Nock")
## After a grapple ends (arrived, let go or missed) the next arrow is ready
## after this long (game seconds). Any parkour move (vault, ledge, wall-run,
## window, climb, roll) nocks it at once, so grapple -> parkour -> grapple
## flows but grapple -> grapple waits a beat.
@export var nock_time := 1.0

@export_group("Release")
## Letting go mid-pull keeps the pull's direction but at most this much speed
## across (m/s, a fast run): the cable's speed isn't the player's own...
@export var release_speed := 12.5
## ...and at most this much upward (m/s, about a jump's rise), so letting go
## by a wall or under a ledge is never a launch. Falling speed is kept.
@export var release_rise_speed := 8.0

@export_group("Aim readout")
## An anchor this close to the aim (degrees) that can't be grappled is shown
## crossed on the reticle...
@export var readout_cone_degrees := 6.0
## ...if the camera can see it (then out to this range, m)...
@export var readout_range := 70.0
## ...or, hidden behind something, only this close (m): nearby anchors
## around a corner still explain themselves, far ones behind buildings stay
## for the player to find.
@export var hidden_readout_range := 14.0

## Anchor the player would grapple to right now (highlighted), or null.
var target: GrappleAnchor
## Without a target: the anchor right under the aim that can't be grappled
## (null if none) and why (see Block). Drives the reticle's crossed circle.
var aimed: GrappleAnchor
var aimed_block := Block.NONE
## Anchor the arrow in play was fired at, or null.
var anchor: GrappleAnchor
## The arrow in play (flying or stuck), or null.
var arrow: GrappleArrow

var _cable: MeshInstance3D
var _nock := 0.0


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
	var forward := -camera.global_basis.z
	var best := find_target(from, camera.global_position, forward)
	_set_target(best)
	_update_aim_readout(from, camera.global_position, forward)
	return best


## The next arrow is nocked (a grapple can fire).
func is_ready() -> bool:
	return _nock <= 0.0


## 0 just after a grapple .. 1 nocked.
func nock_fraction() -> float:
	return 1.0 - _nock / nock_time if nock_time > 0.0 else 1.0


## Starts nocking the next arrow (a grapple just ended).
func start_nock() -> void:
	_nock = nock_time


## Nocked at once (a parkour move, a respawn).
func nock() -> void:
	_nock = 0.0


## Pull speed for a pull starting with the player moving at `speed` (m/s):
## pull_speed_standing from a standstill up to pull_speed at momentum_speed.
func pull_speed_for(speed: float) -> float:
	var t := clampf((speed - 2.0) / maxf(momentum_speed - 2.0, 0.01), 0.0, 1.0)
	return lerpf(pull_speed_standing, pull_speed, t)


func _physics_process(delta: float) -> void:
	_nock = maxf(_nock - delta, 0.0)


## Velocity to carry on with after letting go of a pull moving at `pull`
## (see release_speed). Never faster than `pull`.
func release_velocity(pull: Vector3) -> Vector3:
	var flat := Vector3(pull.x, 0.0, pull.z).limit_length(release_speed)
	return Vector3(flat.x, minf(pull.y, release_rise_speed), flat.z)


## Without a target, the anchor closest to the aim (within
## readout_cone_degrees and readout_range) and what rules it out. One hidden
## from the camera by the world only shows when it's near (see
## hidden_readout_range): the reticle never reveals anchors behind buildings.
func _update_aim_readout(from: Vector3, aim_from: Vector3, forward: Vector3) -> void:
	aimed = null
	aimed_block = Block.NONE
	if target != null:
		return
	var best_angle := readout_cone_degrees
	for node in get_tree().get_nodes_in_group(GrappleAnchor.GROUP):
		var candidate := node as GrappleAnchor
		if candidate == null or not candidate.enabled:
			continue
		if from.distance_to(candidate.global_position) > readout_range:
			continue
		var angle := rad_to_deg(forward.normalized().angle_to(candidate.global_position - aim_from))
		if angle < best_angle:
			aimed = candidate
			best_angle = angle
	if aimed == null:
		return
	var distance := from.distance_to(aimed.global_position)
	if distance > max_range:
		aimed_block = Block.TOO_FAR
	elif distance < min_range:
		aimed_block = Block.TOO_CLOSE
	else:
		aimed_block = Block.BLOCKED
	if distance > hidden_readout_range and not has_line_of_sight(aim_from, aimed.global_position):
		aimed = null # out of sight and not close: nothing to show
		aimed_block = Block.NONE


## Pure query (no highlight): the placed anchor closest to the aim direction
## `forward` from the eye at `aim_from`, within range of the chest at `from`,
## inside the aim cone and in line of sight. Null if none.
##
## Future free-aim grappling plugs in here: a second finder raycasts the aim
## against a "grappleable" physics layer (the way climbing uses its own layer)
## and returns a point target. See README, "Future architecture notes".
func find_target(from: Vector3, aim_from: Vector3, forward: Vector3) -> GrappleAnchor:
	var best: GrappleAnchor = null
	var best_angle := aim_cone_degrees
	forward = forward.normalized()
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
	return best


func has_line_of_sight(from: Vector3, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, point, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit.position as Vector3).distance_to(point) <= line_of_sight_tolerance


func clear_target() -> void:
	_set_target(null)
	aimed = null
	aimed_block = Block.NONE


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
