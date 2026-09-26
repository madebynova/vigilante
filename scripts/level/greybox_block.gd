@tool
class_name GreyboxBlock
extends StaticBody3D
## Box-shaped level piece: one node gives a matching mesh and collision box.
## Resize with `size` (origin is the box centre) and tint with `color`.
## Convex boxes keep character collision and parkour probes reliable.

const SHADER := preload("res://scripts/level/greybox_grid.gdshader")

static var _material: ShaderMaterial

@export var size := Vector3.ONE:
	set(value):
		size = value
		_refresh()
@export var color := Color(0.6, 0.6, 0.62):
	set(value):
		color = value
		_refresh()

var _mesh_instance: MeshInstance3D
var _box_shape: BoxShape3D


func _ready() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = BoxMesh.new()
	_mesh_instance.material_override = _material
	add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	_box_shape = BoxShape3D.new()
	shape_owner_add_shape(create_shape_owner(self), _box_shape)
	_refresh()


func _refresh() -> void:
	if _mesh_instance == null:
		return
	(_mesh_instance.mesh as BoxMesh).size = size
	_box_shape.size = size
	_mesh_instance.set_instance_shader_parameter(&"tint", color)
