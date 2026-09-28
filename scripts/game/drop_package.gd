@tool
class_name DropPackage
extends Node3D
## The package in a dead drop: a small hard case with a blinking tracker
## light. Placeholder geometry built in code, sitting on the surface at this
## node's origin. Pure scenery (no collision): its MissionStep does the pickup.

const CASE_SIZE := Vector3(0.62, 0.34, 0.44)
const BLINK_PERIOD := 1.2

var _led_material: StandardMaterial3D
var _light: OmniLight3D
var _time := 0.0


func _ready() -> void:
	var shell := _material(Color(0.16, 0.17, 0.19), 0.6, 0.45)
	var trim := _material(Color(0.62, 0.64, 0.68), 0.9, 0.3)
	var stripe := _material(Color(0.95, 0.62, 0.18), 0.0, 0.6)
	stripe.emission_enabled = true
	stripe.emission = Color(0.95, 0.55, 0.12)
	stripe.emission_energy_multiplier = 0.6
	_add_box(CASE_SIZE, Vector3(0.0, CASE_SIZE.y * 0.5, 0.0), shell)
	# Latches, a carry handle and a hazard stripe so it reads as a case.
	for x: float in [-0.18, 0.18]:
		_add_box(Vector3(0.07, 0.08, 0.03), Vector3(x, CASE_SIZE.y * 0.62, CASE_SIZE.z * 0.5 + 0.01), trim)
	_add_box(Vector3(0.24, 0.035, 0.05), Vector3(0.0, CASE_SIZE.y + 0.06, 0.0), trim)
	for x: float in [-0.12, 0.12]:
		_add_box(Vector3(0.03, 0.07, 0.04), Vector3(x, CASE_SIZE.y + 0.03, 0.0), trim)
	_add_box(Vector3(CASE_SIZE.x + 0.01, 0.04, CASE_SIZE.z + 0.01), Vector3(0.0, CASE_SIZE.y * 0.3, 0.0), stripe)
	# Tracker light on the lid.
	_led_material = _material(Color(1.0, 0.25, 0.2), 0.0, 0.4)
	_led_material.emission_enabled = true
	_led_material.emission = Color(1.0, 0.2, 0.15)
	var led := SphereMesh.new()
	led.radius = 0.025
	led.height = 0.05
	var led_node := MeshInstance3D.new()
	led_node.mesh = led
	led_node.material_override = _led_material
	led_node.position = Vector3(0.2, CASE_SIZE.y + 0.01, -0.1)
	add_child(led_node, false, Node.INTERNAL_MODE_FRONT)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.2)
	_light.omni_range = 2.5
	_light.position = Vector3(0.2, CASE_SIZE.y + 0.2, -0.1)
	add_child(_light, false, Node.INTERNAL_MODE_FRONT)
	_blink(0.0)


func _process(delta: float) -> void:
	_time += delta
	_blink(_time)


func _blink(t: float) -> void:
	var on := fmod(t, BLINK_PERIOD) < 0.18
	_led_material.emission_energy_multiplier = 6.0 if on else 0.3
	_light.light_energy = 1.2 if on else 0.0


func _add_box(size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	add_child(node, false, Node.INTERNAL_MODE_FRONT)


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m
