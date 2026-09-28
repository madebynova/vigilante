class_name FacadeWindows
extends MultiMeshInstance3D
## Flat glass windows on building facades (scenery, no collision). The city
## kit bakes their positions here and the MultiMesh is built when the scene
## loads: a MultiMesh filled during a headless bake keeps no transforms.

## Per window: x, y, z of its centre and 0 (faces along z) or 1 (along x).
@export var windows := PackedFloat32Array()
@export var window_size := Vector3(1.3, 1.7, 0.03)


func _ready() -> void:
	var quad := BoxMesh.new()
	quad.size = window_size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	var total := count()
	mm.instance_count = total
	var turned := Basis(Vector3.UP, PI * 0.5)
	for i in total:
		var facing := turned if windows[i * 4 + 3] > 0.5 else Basis()
		mm.set_instance_transform(i, Transform3D(facing, Vector3(windows[i * 4], windows[i * 4 + 1], windows[i * 4 + 2])))
	multimesh = mm


## Number of windows in this set.
func count() -> int:
	@warning_ignore("integer_division")
	return windows.size() / 4
