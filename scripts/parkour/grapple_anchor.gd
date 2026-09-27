@tool
class_name GrappleAnchor
extends Node3D
## A point the player can grapple to.
##
## The player is pulled until their feet reach this point, then hops forward
## onto whatever is behind it, so place it just above and slightly inside the
## ledge it belongs to. Shown as a small glowing marker that brightens while it
## is the player's current grapple target.

const GROUP := &"grapple_anchor"
const COLOR := Color(1.0, 0.72, 0.2)

## Disabled anchors are ignored by targeting (and end an active pull).
@export var enabled := true

var _marker: MeshInstance3D
var _material: StandardMaterial3D
var _targeted := false


func _ready() -> void:
	add_to_group(GROUP)
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR
	_material.emission_enabled = true
	_material.emission = COLOR
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	_marker = MeshInstance3D.new()
	_marker.mesh = sphere
	_marker.material_override = _material
	add_child(_marker, false, Node.INTERNAL_MODE_FRONT)
	# A short post down to the surface, so the anchor reads as attached.
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.035
	post_mesh.bottom_radius = 0.035
	post_mesh.height = 0.5
	var post := MeshInstance3D.new()
	post.mesh = post_mesh
	post.material_override = _material
	post.position = Vector3(0.0, -0.25, 0.0)
	add_child(post, false, Node.INTERNAL_MODE_FRONT)
	_apply()


func set_targeted(value: bool) -> void:
	if value != _targeted:
		_targeted = value
		_apply()


func is_targeted() -> bool:
	return _targeted


func _apply() -> void:
	if _marker == null:
		return
	_material.emission_energy_multiplier = 3.0 if _targeted else 0.6
	_marker.scale = Vector3.ONE * (1.4 if _targeted else 1.0)
