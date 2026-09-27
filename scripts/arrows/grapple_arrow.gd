class_name GrappleArrow
extends Node3D
## A grapple arrow: flies straight at a GrappleAnchor, sticks into it and holds
## the cable.
##
## Knows nothing about the player. Whoever fires it (see Grapple) reads `phase`
## and ties the cable to nock_position(). The origin is the arrowhead's tip
## and the arrow points along -Z, so a stuck arrow sits with its tip in the
## anchor and its nock facing the shooter. Placeholder geometry (shaft, claw
## head, fletching) is built in code until a real arrow model exists.

signal attached(anchor: GrappleAnchor)
## The arrow didn't hold: blocked on the way, out of time, or its anchor went
## away (disabled or removed).
signal missed

enum Phase { FLYING, ATTACHED, MISSED }

## Tip to nock.
const LENGTH := 0.9

## Flight speed in m/s (game time).
var speed := 80.0
## Still flying after this many game seconds counts as a miss.
var max_flight_time := 1.5
var collision_mask := 1
## Hitting something this close to the anchor still counts as reaching it
## (the anchor sits on the ledge it belongs to).
var anchor_tolerance := 1.0

var anchor: GrappleAnchor
var phase := Phase.FLYING

var _flight_time := 0.0


func _init() -> void:
	top_level = true


func _ready() -> void:
	_build_placeholder()


## Starts a flight with the tip at `tip`, aimed at `target`.
func launch(tip: Vector3, target: GrappleAnchor) -> void:
	anchor = target
	phase = Phase.FLYING
	_flight_time = 0.0
	global_position = tip
	_point_along(target.global_position - tip)
	reset_physics_interpolation()


func is_attached() -> bool:
	return phase == Phase.ATTACHED and _anchor_ok()


## Where the cable is tied (the back of the shaft), smoothed for rendering.
func nock_position() -> Vector3:
	return get_global_transform_interpolated() * Vector3(0.0, 0.0, LENGTH)


func _physics_process(delta: float) -> void:
	if phase == Phase.MISSED:
		return
	if not _anchor_ok():
		_miss()
	elif phase == Phase.ATTACHED:
		global_position = anchor.global_position # stays stuck in it
	else:
		_fly(delta)


func _fly(delta: float) -> void:
	_flight_time += delta
	var goal := anchor.global_position
	var to_goal := goal - global_position
	var distance := to_goal.length()
	var step := speed * delta
	var next := goal if distance <= step else global_position + to_goal / distance * step
	_point_along(to_goal)
	var query := PhysicsRayQueryParameters3D.create(global_position, next, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit.position as Vector3).distance_to(goal) > anchor_tolerance:
		global_position = hit.position # struck whatever was in the way
		_miss()
		return
	if distance <= step or not hit.is_empty():
		global_position = goal
		phase = Phase.ATTACHED
		attached.emit(anchor)
		return
	global_position = next
	if _flight_time > max_flight_time:
		_miss()


func _anchor_ok() -> bool:
	return anchor != null and is_instance_valid(anchor) and anchor.enabled


func _miss() -> void:
	phase = Phase.MISSED
	missed.emit()


func _point_along(dir: Vector3) -> void:
	if dir.length_squared() < 1e-6:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(dir, up)


# --- Placeholder geometry ----------------------------------------------------

func _build_placeholder() -> void:
	# Gunmetal with a sheen, a touch thicker than the matte cable, so the arrow
	# reads as its own object where the cable is tied on.
	var shaft_material := _material(Color(0.13, 0.14, 0.16), 0.5, 0.35)
	var steel := _material(Color(0.62, 0.64, 0.68), 0.9, 0.3)
	# Fletching picks up the suit's lens blue so the arrow reads in flight.
	var vane_material := _material(Color(0.34, 0.49, 0.67), 0.0, 0.7)
	vane_material.emission_enabled = true
	vane_material.emission = Color(0.05, 0.12, 0.21)
	# Cylinders are built along +Y; this turns +Y to point down the flight (-Z).
	var along := Basis(Vector3.RIGHT, -PI / 2.0)

	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.035
	head.height = 0.12
	_add_part(head, steel, Transform3D(along, Vector3(0.0, 0.0, 0.06)))

	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.024
	shaft.bottom_radius = 0.024
	shaft.height = LENGTH - 0.1
	shaft.radial_segments = 8
	_add_part(shaft, shaft_material, Transform3D(along, Vector3(0.0, 0.0, 0.1 + shaft.height * 0.5)))

	# Steel nock ring: where the cable is tied.
	var nock := CylinderMesh.new()
	nock.top_radius = 0.032
	nock.bottom_radius = 0.032
	nock.height = 0.04
	_add_part(nock, steel, Transform3D(along, Vector3(0.0, 0.0, LENGTH - 0.02)))

	for i in 3:
		var a := TAU * i / 3.0 + PI / 2.0
		var out := Vector3(cos(a), sin(a), 0.0)
		# Grapple claws: swept back from the base of the head.
		var claw := BoxMesh.new()
		claw.size = Vector3(0.014, 0.014, 0.13)
		var sweep := (Vector3.BACK * cos(deg_to_rad(35.0)) + out * sin(deg_to_rad(35.0))).normalized()
		_add_part(claw, steel, Transform3D(Basis.looking_at(-sweep), Vector3(0.0, 0.0, 0.1) + out * 0.02 + sweep * 0.065))
		# Fletching vanes around the back of the shaft.
		var vane := BoxMesh.new()
		vane.size = Vector3(0.004, 0.05, 0.16)
		_add_part(vane, vane_material, Transform3D(Basis(out.cross(Vector3.BACK), out, Vector3.BACK),
				Vector3(0.0, 0.0, LENGTH - 0.13) + out * 0.049))


func _add_part(mesh: Mesh, material: Material, xform: Transform3D) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = xform
	add_child(part)


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material
