class_name DayNight
extends Node
## Day / night prototype: two lighting states and a short blend between them,
## so the city can be judged in both. N (the debug_day_night action, handled
## by the debug HUD) toggles.
##
## Drives the sun (a cool moon at night), the procedural sky, ambient light,
## fog, exposure and a touch of glow, plus the city's night pieces: lamps and
## feature lights (group "night_lights"), glowing bulbs, beacons and signs
## ("night_glow") and the lit facade windows ("city_lit_windows"). Gameplay is
## untouched. There is no clock: `night` is the whole state, and a future
## time-of-day system only needs to drive `blend` (0 day .. 1 night).

signal changed(is_night: bool)

const GROUP := &"day_night"

@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Real seconds to blend from one state to the other.
@export var transition_time := 1.5
@export var start_at_night := false

@export_group("Day")
@export var day_sky_top := Color(0.36, 0.5, 0.72)
@export var day_sky_horizon := Color(0.7, 0.74, 0.8)
@export var day_ground_bottom := Color(0.46, 0.48, 0.52)
@export var day_sun_color := Color(1.0, 0.97, 0.92)
@export var day_sun_energy := 1.2
@export var day_ambient_energy := 0.9
@export var day_fog_color := Color(0.7, 0.74, 0.8)
@export var day_fog_density := 0.0012

@export_group("Night")
@export var night_sky_top := Color(0.012, 0.018, 0.045)
@export var night_sky_horizon := Color(0.1, 0.115, 0.18)
@export var night_ground_bottom := Color(0.03, 0.035, 0.05)
@export var night_moon_color := Color(0.62, 0.72, 1.0)
@export var night_moon_energy := 0.35
## At night most ambient light comes from this colour rather than the dark
## sky, so rooftops, edges and traversal surfaces stay readable.
@export var night_ambient_color := Color(0.3, 0.36, 0.52)
@export var night_ambient_energy := 0.75
@export var night_sky_contribution := 0.25
@export var night_fog_color := Color(0.05, 0.065, 0.1)
@export var night_fog_density := 0.0018
@export var night_exposure := 1.1
@export var night_glow_intensity := 0.35
@export var night_window_energy := 1.3
@export var night_glow_energy := 4.0

## True once toggled to night (the blend may still be on its way).
var night := false
## 0 = day, 1 = night.
var blend := 0.0

var _day_sun_basis: Basis
var _night_sun_basis: Basis
var _lights: Array[Light3D] = []
var _glow_materials: Array[StandardMaterial3D] = []
var _window_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	_day_sun_basis = sun.transform.basis
	# The moon: high in the south-west, so rooftops catch it from the side.
	_night_sun_basis = Basis.looking_at(Vector3(0.45, -0.72, 0.52).normalized(), Vector3.UP)
	for node in get_tree().get_nodes_in_group(&"night_lights"):
		_lights.append(node as Light3D)
	for node in get_tree().get_nodes_in_group(&"night_glow"):
		var mat := (node as GeometryInstance3D).material_override as StandardMaterial3D
		if mat != null and not _glow_materials.has(mat):
			_glow_materials.append(mat)
	for node in get_tree().get_nodes_in_group(&"city_lit_windows"):
		var mat := (node as GeometryInstance3D).material_override as StandardMaterial3D
		if mat != null:
			_window_materials.append(mat)
	environment.environment.glow_enabled = true
	night = start_at_night
	blend = 1.0 if night else 0.0
	_apply(blend)


func toggle() -> void:
	set_night(not night)


## Switches to night (or day), blending over transition_time unless `instant`.
func set_night(value: bool, instant := false) -> void:
	night = value
	if instant:
		blend = 1.0 if night else 0.0
		_apply(blend)
	changed.emit(night)


## "NIGHT" / "DAY" (for readouts).
func label() -> String:
	return "NIGHT" if night else "DAY"


func _process(delta: float) -> void:
	var target := 1.0 if night else 0.0
	if is_equal_approx(blend, target):
		return
	# Real time, so bullet time doesn't stretch the transition.
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	blend = move_toward(blend, target, real_delta / maxf(transition_time, 0.01))
	_apply(blend)


func _apply(t: float) -> void:
	var env := environment.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if sky != null:
		sky.sky_top_color = day_sky_top.lerp(night_sky_top, t)
		sky.sky_horizon_color = day_sky_horizon.lerp(night_sky_horizon, t)
		sky.ground_horizon_color = day_sky_horizon.lerp(night_sky_horizon, t)
		sky.ground_bottom_color = day_ground_bottom.lerp(night_ground_bottom, t)
	sun.light_color = day_sun_color.lerp(night_moon_color, t)
	sun.light_energy = lerpf(day_sun_energy, night_moon_energy, t)
	sun.transform.basis = _day_sun_basis.slerp(_night_sun_basis, t)
	env.ambient_light_color = night_ambient_color
	env.ambient_light_sky_contribution = lerpf(1.0, night_sky_contribution, t)
	env.ambient_light_energy = lerpf(day_ambient_energy, night_ambient_energy, t)
	env.fog_light_color = day_fog_color.lerp(night_fog_color, t)
	env.fog_density = lerpf(day_fog_density, night_fog_density, t)
	env.tonemap_exposure = lerpf(1.0, night_exposure, t)
	env.glow_intensity = night_glow_intensity * t
	# Night pieces fade in over the second half of the blend.
	var on := smoothstep(0.35, 1.0, t)
	for light in _lights:
		light.visible = on > 0.0
		light.light_energy = float(light.get_meta(&"night_energy", 1.0)) * on
	for mat in _glow_materials:
		mat.emission_energy_multiplier = night_glow_energy * on
	for mat in _window_materials:
		mat.emission_energy_multiplier = night_window_energy * on
