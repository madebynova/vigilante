extends SceneTree
## Builds the city greybox scene (res://scenes/city/city_greybox.tscn) from
## the hand-placed layout in the district_*.gd files.
##
##   godot --headless --path . -s res://tools/city/build_city.gd
##
## The layout is authored here as code so the numbers that matter for
## traversal (storey heights, gap widths, anchor positions) stay readable and
## easy to adjust together. Re-running overwrites the scene, so make layout
## changes here rather than in the editor.
##
## Map: ~132 x 142 m playable, X east, Z south (north is -Z).
##   South  (z  33..70)  Safehouse district: safehouse, parking lot, plaza, walk-ups
##   Middle (z -22..22)  Service yard (west) | Dense blocks (centre) | Mid-rise roofs (east)
##   North  (z -72..-36) Skyline: construction site + crane, Meridian tower, Spire, towers
## Streets: Central Ave (x 0, N-S), North Ave (z -29), South St (z 28),
## West Service Lane (x -38), East St (x 31).

const Kit := preload("res://tools/city/city_kit.gd")
const Safehouse := preload("res://tools/city/district_safehouse.gd")
const Dense := preload("res://tools/city/district_dense.gd")
const Service := preload("res://tools/city/district_service.gd")
const Midrise := preload("res://tools/city/district_midrise.gd")
const Skyline := preload("res://tools/city/district_skyline.gd")

const OUT := "res://scenes/city/city_greybox.tscn"


func _initialize() -> void:
	var city := Node3D.new()
	city.name = "CityGreybox"
	var k := Kit.new(city)
	_environment(k)
	_streets(k)
	_backdrop(k)
	Safehouse.build(k)
	Dense.build(k)
	Service.build(k)
	Midrise.build(k)
	Skyline.build(k)
	k.dress_windows()

	var packed := PackedScene.new()
	var err := packed.pack(city)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
		err = ResourceSaver.save(packed, OUT)
	var blocks := city.find_children("*", "GreyboxBlock", true, false).size()
	var anchors := city.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n is GrappleAnchor).size()
	var windows := city.find_children("*", "TraversalWindow", true, false).size()
	var lights := city.find_children("*", "Light3D", true, false).size()
	print("city greybox: %d blocks, %d grapple anchors, %d dive windows, %d lights -> %s (%s)" % [
			blocks, anchors, windows, lights, OUT, error_string(err)])
	city.free()
	quit(0 if err == OK else 1)


func _environment(k: Kit) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.5, 0.72)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.8)
	sky_mat.ground_horizon_color = Color(0.7, 0.74, 0.8)
	# Neutral below the horizon: from high up you can see past the backdrop.
	sky_mat.ground_bottom_color = Color(0.46, 0.48, 0.52)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	# A little haze so the skyline layers read at a distance.
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.74, 0.8)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	k._add(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis(Vector3(0.81915206, 0, 0.57357645), Vector3(0.45198438, 0.6156615, -0.6455006),
			Vector3(-0.35312894, 0.7880107, 0.5043204)), Vector3.ZERO)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	k._add(sun)

	# Day / night (N toggles, via the debug HUD): drives the sky, sun, ambient
	# light and the city's night lights.
	var day_night := DayNight.new()
	day_night.name = "DayNight"
	day_night.environment = world_env
	day_night.sun = sun
	k._add(day_night)


func _streets(k: Kit) -> void:
	k.begin("Streets")
	# Pavement everywhere; it ends at the outer edge of the backdrop so walking
	# out of the city is a fall (and a respawn), never an endless plain.
	k.box("Ground", -80, 80, -1.0, 0.0, -86, 84, Kit.PAVEMENT)
	var road := 0.02
	k.box("CentralAve", -4, 4, 0.0, road, -72, 70, Kit.ASPHALT)
	k.box("NorthAveW", -66, -4, 0.0, road, -33, -25, Kit.ASPHALT)
	k.box("NorthAveE", 4, 66, 0.0, road, -33, -25, Kit.ASPHALT)
	k.box("SouthStW", -66, -4, 0.0, road, 25, 31, Kit.ASPHALT)
	k.box("SouthStE", 4, 66, 0.0, road, 25, 31, Kit.ASPHALT)
	k.box("WestServiceLane", -41, -35, 0.0, road, -25, 25, Kit.ASPHALT)
	k.box("EastSt", 28, 34, 0.0, road, -25, 25, Kit.ASPHALT)
	# Centre line on Central Ave, broken at the two intersections.
	var z := -70.0
	while z < 68.0:
		if not (z > -36.0 and z < -22.0) and not (z > 22.0 and z < 34.0):
			k.box("CentreLine", -0.08, 0.08, road, road + 0.01, z, z + 3.0, Color(0.86, 0.78, 0.36))
		z += 6.0
	# Zebra crossings around the Central Ave / North Ave intersection: the
	# main crossroads, the most recognisable spot at street level.
	for i in 8:
		var x := -3.4 + i * 0.95
		k.box("CrossingN", x, x + 0.5, road, road + 0.01, -35.2, -33.4, Kit.MARKING)
		k.box("CrossingS", x, x + 0.5, road, road + 0.01, -24.6, -22.8, Kit.MARKING)
	for i in 8:
		var zz := -32.4 + i * 0.95
		k.box("CrossingW", -6.2, -4.4, road, road + 0.01, zz, zz + 0.5, Kit.MARKING)
		k.box("CrossingE", 4.4, 6.2, road, road + 0.01, zz, zz + 0.5, Kit.MARKING)
	# Street lamps along Central Ave: at the kerb, clear of the awnings, the
	# alley mouths and the window-building's dive line.
	for lz in [-60.0, -44.0, 23.5, 60.0]:
		k.lamp("LampW", -4.6, lz)
	for lz in [-54.0, -38.0, -8.0, 33.0, 46.0, 62.0]:
		k.lamp("LampE", 4.6, lz)
	k.end()


## Plain tall blocks closing the playable area on all sides: the city carries
## on beyond them, but they have no anchors or ledges. Their city-facing
## faces get glass windows, so the skyline lights up at night.
func _backdrop(k: Kit) -> void:
	k.begin("Backdrop")
	var c := Kit.BACKDROP
	var c2 := c.lightened(0.05)
	for b: Array in [
			# West band (faces +x), east band (faces -x).
			["West1", -80, -66, 34, -86, -50, c, "x+"], ["West2", -80, -66, 22, -50, -20, c2, "x+"],
			["West3", -80, -66, 28, -20, 10, c, "x+"], ["West4", -80, -66, 18, 10, 40, c2, "x+"],
			["West5", -80, -66, 24, 40, 84, c, "x+"],
			["East1", 66, 80, 30, -86, -55, c2, "x-"], ["East2", 66, 80, 40, -55, -25, c, "x-"],
			["East3", 66, 80, 20, -25, 5, c2, "x-"], ["East4", 66, 80, 26, 5, 35, c, "x-"],
			["East5", 66, 80, 18, 35, 84, c2, "x-"],
			# North band; the block ending Central Ave is a pale civic facade that
			# closes the view up the avenue.
			["North1", -66, -35, 45, -86, -72, c, "z+"], ["North2", -35, -6.5, 32, -86, -72, c2, "z+"],
			["NorthCivic", -6.5, 6.5, 26, -86, -72, Color(0.66, 0.64, 0.6), "z+"],
			["North3", 6.5, 40, 50, -86, -72, c, "z+"], ["North4", 40, 66, 36, -86, -72, c2, "z+"],
			# South band.
			["South1", -66, -20, 16, 70, 84, c2, "z-"], ["South2", -20, 20, 22, 70, 84, c, "z-"],
			["South3", 20, 66, 14, 70, 84, c2, "z-"]]:
		k.box(b[0], b[1], b[2], 0, b[3], b[4], b[5], b[6])
		k.register_facade(b[1], b[2], b[4], b[5], 0.0, b[3], [b[7]], 3.5)
	k.end()
