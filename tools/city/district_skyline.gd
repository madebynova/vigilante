extends RefCounted
## SKYLINE (north, z -72..-35.5): the tall layer and the city's landmarks.
##
## West: the construction site - an unfinished frame (scaffold, a light shaft
## beside a brick lift core, beams, plank ramps, a site office with dive
## windows, a stair tower, slabs to 24.5 m) - and a tower crane whose
## machinery deck (30 m) is a ladder climb up the mast, a grapple hop from the
## top slab and a grapple hop from the Meridian tower's roof (38 m).
## The Meridian has a 10.5 m terrace along North Ave (stair from the street,
## brick flank above it). East: Spire Plaza and the Spire - a stepped landmark
## (28 / 42 / 56 m) whose deep setbacks leave room to grapple up level by
## level - then two towers stepping down toward the mid-rise roofs. The long
## skyline gap is Meridian -> Spire across Central Ave (~25 m, grapple).

const Kit := preload("res://tools/city/city_kit.gd")

const SITE := Color(0.62, 0.62, 0.6)
const MERIDIAN := Color(0.54, 0.58, 0.64)
const SPIRE := Color(0.8, 0.82, 0.86)
const TOWER_A := Color(0.58, 0.62, 0.68)
const TOWER_B := Color(0.5, 0.54, 0.6)
const WORK_LIGHT := Color(1.0, 0.9, 0.7)
const AVIATION := Color(1.0, 0.25, 0.18)


static func build(k: Kit) -> void:
	k.begin("Skyline")
	_construction_site(k)
	_crane(k)
	_meridian(k)
	_spire_plaza(k)
	_spire(k)
	_towers(k)
	k.start_marker("Start5", Vector3(21.0, 0.05, -37.0), 0.0)
	k.end()


## x -60..-40, z -66..-46: an unfinished concrete frame, a traversal
## landmark with several ways up, across and out (no set path):
##   - Scaffold on the south face: a drop ladder or a jump-and-grab from the
##     forecourt to level 1, flights to level 2 (7 m, beside the open corner)
##     and level 3 (10.5 m, onto floor 3).
##   - A 4 m light shaft (x -50..-46, z -60..-50) open from the ground up to
##     slab 5, beside a brick lift core: sprint in, wall-run the core, wall-jump
##     across and grab a floor edge (3.5 m from the ground, 7 m from floor 1).
##   - Floors 1-3 have the shaft; floor 2 has an unfinished south-west corner;
##     floor 4 (14 m) is only half poured: two steel beams span its open bay,
##     out to the south edge (jump off, grapple the service tenement).
##   - A finished site office on floor 4 with dive windows south (grapple the
##     tenement) and east (grapple the Meridian terrace).
##   - Plank ramps: forecourt -> floor 1, floor 3 -> floor 4. The stair tower
##     on the east face reaches every level; floors 5-7 step up to 24.5 m.
static func _construction_site(k: Kit) -> void:
	k.begin("ConstructionSite")
	# Floors 1-3: everything but the shaft and the lift core (floor 2 also
	# lacks its south-west corner).
	for i in 3:
		var y := Kit.STOREY * (i + 1)
		var n := i + 1
		if n == 2:
			k.box("Slab2West", -60.0, -50.0, y - 0.3, y, -66.0, -54.0, SITE)
			k.box("Slab2WestS", -54.0, -50.0, y - 0.3, y, -54.0, -46.0, SITE)
		else:
			k.box("Slab%dWest" % n, -60.0, -50.0, y - 0.3, y, -66.0, -46.0, SITE)
		k.box("Slab%dNorth" % n, -50.0, -44.0, y - 0.3, y, -66.0, -60.0, SITE)
		k.box("Slab%dSouth" % n, -50.0, -44.0, y - 0.3, y, -50.0, -46.0, SITE)
		k.box("Slab%dEast" % n, -44.0, -40.0, y - 0.3, y, -66.0, -46.0, SITE)
		# A 0.6 m edge beam under the slab edge on the shaft side: a grabbable lip
		# for the wall-jump across (top a hair below the slab's, no z-fighting).
		k.box("ShaftEdge%d" % n, -50.4, -50.0, y - 0.6, y - 0.02, -60.0, -50.0, SITE.darkened(0.15))
	# The lift core: brick, runnable along the shaft; its top is part of floor 4.
	k.box("LiftCore", -46.0, -44.0, 0.0, 14.0, -60.0, -50.0, Kit.RUN)
	# Floor 4 (14 m): north half, east strip and the office floor; the south-west
	# bay is open with two beams across it.
	k.box("Slab4NorthW", -60.0, -50.0, 13.7, 14.0, -66.0, -56.0, SITE)
	k.box("Slab4NorthC", -50.0, -44.0, 13.7, 14.0, -66.0, -60.0, SITE)
	k.box("Slab4NorthE", -44.0, -40.0, 13.7, 14.0, -66.0, -56.0, SITE)
	k.box("Slab4East", -44.0, -40.0, 13.7, 14.0, -56.0, -46.0, SITE)
	k.box("Slab4Office", -46.0, -44.0, 13.7, 14.0, -50.0, -46.0, SITE)
	k.box("BeamEW", -60.0, -46.0, 13.6, 14.0, -49.3, -48.7, Kit.STEEL)
	k.box("BeamNS", -55.3, -54.7, 13.6, 14.0, -56.0, -46.0, Kit.STEEL)
	# Floors 5-7 step back toward the stair tower.
	k.box("Slab5", -54.0, -40.0, 17.2, 17.5, -66.0, -52.0, SITE)
	k.box("Slab6", -54.0, -40.0, 20.7, 21.0, -66.0, -52.0, SITE)
	k.box("Slab7", -50.0, -40.0, 24.2, 24.5, -66.0, -52.0, SITE)
	for x: float in [-59.7, -50.0, -40.3]:
		for z: float in [-65.7, -56.0, -46.3]:
			if x == -50.0 and z == -56.0:
				continue # the shaft
			k.box("Column", x - 0.3, x + 0.3, 0.0, 17.2, z - 0.3, z + 0.3, SITE.darkened(0.1))
	for x: float in [-53.7, -47.0, -40.3]:
		for z: float in [-65.7, -52.3]:
			k.box("ColumnUpper", x - 0.3, x + 0.3, 17.5, 20.7, z - 0.3, z + 0.3, SITE.darkened(0.1))
	for x: float in [-49.7, -40.3]:
		for z: float in [-65.7, -52.3]:
			k.box("ColumnTop", x - 0.3, x + 0.3, 21.0, 24.2, z - 0.3, z + 0.3, SITE.darkened(0.1))
	# Site office on floor 4: walls, a door from the east strip, dive windows
	# south (over the forecourt) and east (toward the Meridian terrace).
	var sill := 14.9
	var office := SITE.lightened(0.1)
	k.wall("OfficeS", "z", -46.15, 0.3, -46.0, -40.0, 14.0, 17.2, office, [Kit.window_hole(-43.0, sill)])
	k.wall("OfficeE", "x", -40.15, 0.3, -49.7, -46.3, 14.0, 17.2, office, [Kit.window_hole(-48.0, sill)])
	k.wall("OfficeW", "x", -45.85, 0.3, -49.7, -46.3, 14.0, 17.2, office)
	k.wall("OfficeN", "z", -49.85, 0.3, -46.0, -40.0, 14.0, 17.2, office, [{u = -41.8, w = 1.6, b = 14.0, t = 16.4}])
	k.box("OfficeRoof", -46.0, -40.0, 17.2, 17.5, -50.0, -46.0, Kit.ROOF)
	k.dive_window("OfficeWindowS", "z", -46.15, -43.0, sill, Vector3(6.0, 4.5, 10.0))
	k.dive_window("OfficeWindowE", "x", -40.15, -48.0, sill, Vector3(6.0, 4.5, 10.0))
	# Scaffold on the south face; the corner beside it is open above floor 1.
	k.fire_escape("Scaffold", "z+", -46.0, -60.0, -51.0, [3.5, 7.0, 10.5], false, true)
	# Work lights (night): the shaft, floor 4's open bay, the top slabs, the forecourt.
	k.night_light("WorkLightShaft", Vector3(-48.0, 6.2, -55.0), WORK_LIGHT, 1.8, 11.0)
	k.night_light("WorkLightBay", Vector3(-53.0, 16.5, -51.0), WORK_LIGHT, 1.8, 12.0)
	k.night_light("WorkLightTop", Vector3(-45.0, 26.5, -59.0), WORK_LIGHT, 1.8, 12.0)
	k.night_light("WorkLightFore", Vector3(-50.0, 3.0, -42.0), WORK_LIGHT, 1.6, 10.0)
	k.night_light("OfficeLight", Vector3(-43.0, 16.6, -48.0), Color(1.0, 0.82, 0.55), 1.4, 9.0)
	for p: Vector3 in [Vector3(-48.0, 6.6, -55.0), Vector3(-53.0, 16.9, -51.0), Vector3(-45.0, 26.9, -59.0)]:
		k.night_glow("WorkLamp", p.x - 0.2, p.x + 0.2, p.y - 0.15, p.y + 0.15, p.z - 0.2, p.z + 0.2, WORK_LIGHT)
	# Plank ramps: forecourt -> floor 1, floor 3 -> floor 4 (under the EW beam).
	var plank := Color(0.55, 0.45, 0.32)
	# Each ends exactly on the edge of the slab it climbs to, like a fire-escape
	# flight: the controller has no step-up, so even a 3 cm lip there blocks.
	k.ramp("PlankRamp1", Vector3(-43.0, 0.0, -39.6), Vector3(-43.0, 3.5, -46.0), 1.6, plank, 0.2)
	k.ramp("PlankRamp4", Vector3(-58.0, 10.5, -46.6), Vector3(-58.0, 14.0, -56.0), 1.6, plank, 0.2)
	k.fire_escape("StairTower", "x+", -40.0, -64.0, -50.0, [3.5, 7.0, 10.5, 14.0, 17.5, 21.0, 24.5])
	k.box("MaterialPile", -58.0, -55.0, 0.0, 1.2, -41.5, -39.5, plank)
	k.box("SiteOffice", -64.0, -61.0, 0.0, 2.6, -46.0, -40.0, Color(0.7, 0.62, 0.3))
	# Hoarding along North Ave: a street-level runnable wall, with a gate.
	k.box("HoardingW", -64.0, -54.0, 0.0, 3.0, -38.2, -38.0, Kit.RUN)
	k.box("HoardingE", -46.0, -36.0, 0.0, 3.0, -38.2, -38.0, Kit.RUN)
	k.sign("Sign", Vector3(-50.0, 4.2, -37.5), "CONSTRUCTION SITE", 48)
	k.end()


## Tower crane beside the site: mast (a ladder up its south face, through a
## hatch in the deck), machinery deck at 30 m, a walkable jib out over the site.
static func _crane(k: Kit) -> void:
	k.begin("Crane")
	k.box("Mast", -35.0, -33.0, 0.0, 29.6, -60.0, -58.0, Kit.GRAPPLE)
	k.ladder("MastLadder", "z+", -58.0, -34.0, 0.0, 30.0)
	k.box("Deck", -37.0, -31.0, 29.6, 30.0, -62.0, -57.85, Kit.GRAPPLE)
	k.box("DeckW", -37.0, -34.8, 29.6, 30.0, -57.85, -56.0, Kit.GRAPPLE)
	k.box("DeckE", -33.2, -31.0, 29.6, 30.0, -57.85, -56.0, Kit.GRAPPLE)
	k.box("Jib", -58.0, -37.0, 30.0, 31.0, -59.6, -58.4, Kit.GRAPPLE)
	k.box("CounterJib", -31.0, -29.5, 30.0, 31.0, -59.6, -58.4, Kit.GRAPPLE)
	k.box("Counterweight", -30.5, -29.5, 28.5, 30.0, -60.0, -58.0, Kit.PROP)
	k.box("HookCable", -56.05, -55.95, 22.0, 30.0, -59.05, -58.95, Kit.PROP)
	k.box("Hook", -56.4, -55.6, 21.2, 22.0, -59.4, -58.6, Kit.PROP)
	k.anchor("AnchorCraneDeck", Vector3(-36.6, 30.5, -61.0))
	k.night_glow("JibLight", -58.0, -57.6, 31.0, 31.3, -59.2, -58.8, AVIATION)
	k.night_glow("CabLight", -31.2, -30.8, 31.0, 31.3, -59.2, -58.8, AVIATION)
	k.night_light("CraneLight", Vector3(-34.0, 31.5, -59.0), WORK_LIGHT, 1.5, 9.0)
	k.end()


## Meridian tower (x -28..-10, z -68..-46, 38 m) with a 10.5 m terrace wing.
static func _meridian(k: Kit) -> void:
	k.begin("Meridian")
	k.building("Tower", -28.0, -10.0, -68.0, -46.0, 38.0, MERIDIAN)
	k.building("Terrace", -28.0, -10.0, -46.0, -40.0, 10.5, MERIDIAN.lightened(0.08))
	k.run_panel("TerraceRunWall", "z+", -46.0, -28.0, -10.0, 10.5, 37.9)
	k.fire_escape("TerraceStair", "z+", -40.0, -27.0, -19.0, [3.5, 7.0, 10.5])
	k.box("TerracePlanter", -17.0, -13.0, 10.5, 11.3, -44.5, -43.0, Color(0.46, 0.5, 0.4))
	k.anchor("AnchorTerrace", Vector3(-14.0, 11.0, -40.4))
	k.anchor("AnchorMeridianWest", Vector3(-27.6, 38.5, -59.0))
	k.anchor("AnchorMeridianEast", Vector3(-10.4, 38.5, -55.0))
	k.building("Penthouse", -24.0, -16.0, -67.0, -62.0, 41.5, MERIDIAN.darkened(0.1), 38.0)
	# Parapets only where no anchor or route crosses the edge.
	k.parapet("ParapetN", "z-", -68.0, -28.0, -10.0, 38.0)
	k.parapet("ParapetS", "z+", -46.0, -26.5, -11.5, 38.0)
	k.door("Door", "z+", -40.0, -13.0, 2.4, 2.8)
	k.ac_unit("RoofAC", -14.0, -50.0, 38.0)
	k.sign("Sign", Vector3(-19.0, 14.0, -40.0), "MERIDIAN", 64)
	k.end()


## x 6.5..34, z -46..-35.5 in front of the Spire.
static func _spire_plaza(k: Kit) -> void:
	k.begin("SpirePlaza")
	k.box("Paving", 6.5, 34.0, 0.0, 0.02, -46.0, -35.5, Kit.PLAZA)
	k.box("FountainBasin", 17.0, 25.0, 0.0, 0.6, -43.0, -39.0, Color(0.58, 0.6, 0.62))
	k.box("FountainColumn", 20.3, 21.7, 0.6, 3.0, -41.7, -40.3, Color(0.7, 0.72, 0.74))
	for p: Vector2 in [Vector2(9.5, -38.5), Vector2(31.0, -38.5), Vector2(9.5, -44.0), Vector2(31.0, -44.0)]:
		k.box("Planter", p.x - 1.2, p.x + 1.2, 0.0, 0.8, p.y - 1.2, p.y + 1.2, Color(0.46, 0.5, 0.4))
	k.box("Bench", 12.0, 15.0, 0.0, 0.5, -37.0, -36.4, Color(0.45, 0.36, 0.28))
	k.box("Bench", 27.0, 30.0, 0.0, 0.5, -37.0, -36.4, Color(0.45, 0.36, 0.28))
	k.sign("Sign", Vector3(21.0, 4.5, -38.5), "SPIRE PLAZA", 56)
	k.end()


## The Spire: base 22x24 to 28 m, mid 14x15 to 42 m, crown 8x7 to 56 m, mast
## to 70 m. Each setback leaves an 8 m deep terrace in front of the next
## level: far enough back to grapple its edge.
static func _spire(k: Kit) -> void:
	k.begin("Spire")
	k.building("Base", 10.0, 32.0, -70.0, -46.0, 28.0, SPIRE)
	k.building("Mid", 14.0, 28.0, -69.0, -54.0, 42.0, SPIRE.darkened(0.04), 28.0)
	k.building("Crown", 17.0, 25.0, -69.0, -62.0, 56.0, SPIRE.darkened(0.08), 42.0)
	k.box("Mast", 20.4, 21.6, 56.0, 70.0, -66.1, -64.9, Kit.PROP)
	k.box("Beacon", 20.2, 21.8, 70.0, 70.6, -66.3, -64.7, Color(0.95, 0.35, 0.25))
	k.night_glow("BeaconGlow", 20.3, 21.7, 70.6, 70.9, -66.2, -64.8, AVIATION)
	k.night_light("BeaconLight", Vector3(21.0, 71.5, -65.5), AVIATION, 3.0, 18.0)
	k.parapet("BaseParapetW", "x-", 10.0, -69.5, -47.0, 28.0)
	k.parapet("BaseParapetN", "z-", -70.0, 10.5, 31.5, 28.0)
	k.door("Door", "z+", -46.0, 15.5, 3.0, 3.2)
	k.anchor("AnchorSpireBase", Vector3(21.0, 28.5, -46.4))
	k.anchor("AnchorSpireBaseEast", Vector3(31.6, 28.5, -58.0))
	k.anchor("AnchorSpireMid", Vector3(21.0, 42.5, -54.4))
	k.anchor("AnchorSpireMidWest", Vector3(14.4, 42.5, -61.0))
	k.anchor("AnchorSpireCrown", Vector3(21.0, 56.5, -62.4))
	k.end()


## Tower east of the Spire (35 m) and a lower one (26 m) facing the mid-rise roofs.
static func _towers(k: Kit) -> void:
	k.begin("Towers")
	k.building("TowerEast", 38.0, 50.0, -68.0, -50.0, 35.0, TOWER_A)
	k.box("Helipad", 40.0, 48.0, 35.0, 35.05, -63.0, -55.0, Kit.MARKING)
	k.anchor("AnchorTowerEastWest", Vector3(38.4, 35.5, -58.0))
	k.anchor("AnchorTowerEastEast", Vector3(49.6, 35.5, -58.0))
	k.parapet("EastParapetN", "z-", -68.0, 38.5, 49.5, 35.0)
	k.parapet("EastParapetS", "z+", -50.0, 38.5, 49.5, 35.0)
	k.door("DoorEast", "z+", -50.0, 44.0)
	k.building("TowerLow", 52.0, 66.0, -62.0, -40.0, 26.0, TOWER_B)
	k.water_tower("WaterTower", 61.0, -56.0, 26.0, "z+")
	k.anchor("AnchorTowerLowSouth", Vector3(58.0, 26.5, -40.4))
	k.ac_unit("RoofAC", 56.0, -46.0, 26.0)
	k.door("DoorLow", "x-", 52.0, -45.0)
	# A small park between the plaza and the low tower.
	for p: Vector2 in [Vector2(38.0, -40.0), Vector2(44.0, -44.0), Vector2(47.0, -38.5)]:
		k.box("TreeTrunk", p.x - 0.25, p.x + 0.25, 0.0, 2.5, p.y - 0.25, p.y + 0.25, Color(0.4, 0.32, 0.24))
		k.box("TreeCrown", p.x - 1.5, p.x + 1.5, 2.5, 5.0, p.y - 1.5, p.y + 1.5, Color(0.3, 0.46, 0.3))
	k.end()
