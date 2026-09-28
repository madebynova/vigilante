class_name ObjectiveBeacon
extends Node3D
## Marks the current objective in the world so it can be found by eye from
## anywhere in the city: a soft light beam rising from it and a slowly
## turning ring on the spot itself. Move it with place(); hide it when there
## is no objective.

const SHADER := preload("res://scripts/game/objective_beacon.gdshader")
const BEAM_HEIGHT := 90.0
const COLOR := Color(1.0, 0.68, 0.25)

var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	# A quad the shader turns toward the camera (see objective_beacon.gdshader).
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, BEAM_HEIGHT)
	var beam_material := ShaderMaterial.new()
	beam_material.shader = SHADER
	beam_material.set_shader_parameter(&"beam_color", COLOR)
	beam_material.set_shader_parameter(&"height", BEAM_HEIGHT)
	_beam = MeshInstance3D.new()
	_beam.mesh = quad
	_beam.material_override = beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.custom_aabb = AABB(Vector3(-6.0, -BEAM_HEIGHT * 0.5, -6.0), Vector3(12.0, BEAM_HEIGHT, 12.0))
	_beam.position = Vector3.UP * BEAM_HEIGHT * 0.5
	add_child(_beam)

	var torus := TorusMesh.new()
	torus.inner_radius = 1.05
	torus.outer_radius = 1.2
	torus.rings = 48
	torus.ring_segments = 6
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = COLOR
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	_ring.position = Vector3.UP * 0.08
	add_child(_ring)


## Puts the beacon on `point` and shows it.
func place(point: Vector3) -> void:
	global_position = point
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_ring.rotation.y = _time * 0.8
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	_ring.scale = Vector3(1.0 + 0.08 * pulse, 0.25, 1.0 + 0.08 * pulse)
	_ring_material.albedo_color = Color(COLOR, 0.55 + 0.35 * pulse)
