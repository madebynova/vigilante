extends RefCounted
## SAFEHOUSE DISTRICT (south, z 33.5..70): the start area and future base.
##
## The safehouse is a two-storey brick workshop: street door and interior on
## the ground floor, a loft above (inner stair up), roof reached by an outside
## stair. Its walled courtyard repeats the proven playground route 4 at the
## same proportions: run off the loading deck along the courtyard wall,
## wall-jump, E in through the loft's back window, E out of the front window
## high over South St, grapple across to the dense block. West: parking lot
## with a billboard catwalk. East: the corner building, a small plaza, a row
## of walk-ups (fire escape, climbable facade) and a back lot with a water tank.

const Kit := preload("res://tools/city/city_kit.gd")

const SAFE := Color(0.5, 0.3, 0.26)
const CORNER := Color(0.62, 0.55, 0.5)
const ROW_A := Color(0.6, 0.54, 0.5)
const ROW_B := Color(0.55, 0.5, 0.47)
const ROW_C := Color(0.64, 0.6, 0.56)
const DINER := Color(0.66, 0.6, 0.52)


static func build(k: Kit) -> void:
	k.begin("SafehouseDistrict")
	_safehouse(k)
	_courtyard(k)
	_corner_building(k)
	_parking_lot(k)
	_plaza_and_diner(k)
	_walkups(k)
	_back_lot(k)
	k.sign("Sign", Vector3(-21.0, 4.6, 35.4), "SAFEHOUSE", 56)
	k.start_marker("Start1", Vector3(-21.0, 0.05, 42.0), 0.0)
	k.end()


## x -30..-16, z 36..46. Ground floor 0..3.5, loft floor at 3.8, roof at 7.7.
static func _safehouse(k: Kit) -> void:
	k.begin("Safehouse")
	# Ground floor: street door (north), back door to the courtyard (south).
	k.wall("GroundN", "z", 36.15, 0.3, -30, -16, 0.0, 3.5, SAFE, [{u = -21.0, w = 3.0, b = 0.0, t = 2.8}])
	k.wall("GroundS", "z", 45.85, 0.3, -30, -16, 0.0, 3.5, SAFE, [{u = -24.0, w = 1.6, b = 0.0, t = 2.4}])
	k.wall("GroundW", "x", -29.85, 0.3, 36.3, 45.7, 0.0, 3.5, SAFE)
	k.wall("GroundE", "x", -16.15, 0.3, 36.3, 45.7, 0.0, 3.5, SAFE)
	# Loft floor with a stairwell along the east wall; the inner stair climbs
	# north from the back of the room to a landing by the loft's front.
	k.box("LoftFloor", -30, -17.8, 3.5, 3.8, 36, 46, Kit.FLOOR)
	k.box("LoftLanding", -17.8, -16, 3.5, 3.8, 36, 37.5, Kit.FLOOR)
	k.ramp("InnerStair", Vector3(-17.05, 0.0, 45.4), Vector3(-17.05, 3.8, 37.5), 1.5, Kit.FLOOR)
	# Base furniture (vaultable): workbench, table, lockers.
	k.box("Workbench", -29.5, -26.5, 0.0, 0.9, 43.8, 45.5, Kit.PROP)
	k.box("Table", -25.0, -23.0, 0.0, 0.8, 40.0, 42.0, Color(0.45, 0.36, 0.28))
	k.box("Lockers", -29.6, -29.0, 0.0, 2.2, 37.0, 40.0, Kit.PROP)
	# Loft: dive windows front and back, lined up for a straight run through.
	k.wall("LoftN", "z", 36.15, 0.3, -30, -16, 3.5, 7.4, SAFE, [Kit.window_hole(-27.1, 4.7)])
	k.wall("LoftS", "z", 45.85, 0.3, -30, -16, 3.5, 7.4, SAFE, [Kit.window_hole(-27.1, 4.7)])
	k.wall("LoftW", "x", -29.85, 0.3, 36.3, 45.7, 3.5, 7.4, SAFE)
	k.wall("LoftE", "x", -16.15, 0.3, 36.3, 45.7, 3.5, 7.4, SAFE)
	k.box("Roof", -30, -16, 7.4, 7.7, 36, 46, Kit.ROOF)
	k.dive_window("LoftBackWindow", "z", 45.85, -27.1, 4.7)
	k.dive_window("LoftFrontWindow", "z", 36.15, -27.1, 4.7, Vector3(6.0, 4.5, 10.0))
	# Street side: awning over the door; outside stair up the west wall to the roof.
	k.face_box("DoorAwning", "z-", 36.0, 0.0, 2.2, -23.0, -19.0, 3.0, 3.5, Kit.LEDGE)
	k.ramp("RoofStair", Vector3(-30.7, 0.0, 33.6), Vector3(-30.7, 7.7, 44.0), 1.4)
	k.box("RoofStairLanding", -31.4, -30.0, 7.45, 7.7, 44.0, 46.0, Kit.STEEL)
	k.roof_hut("RoofHut", -20.0, -17.5, 42.5, 45.5, 7.7, SAFE, "z-")
	k.ac_unit("RoofAC", -24.5, 43.5, 7.7)
	# Grapple home: from the dense block's roofs across South St.
	k.anchor("AnchorSafehouseRoof", Vector3(-22.0, 8.2, 36.4))
	k.night_light("GroundLight", Vector3(-23.0, 2.9, 41.0), Color(1.0, 0.8, 0.52), 1.3, 9.0)
	k.night_light("LoftLight", Vector3(-24.0, 6.8, 41.0), Color(1.0, 0.8, 0.52), 1.3, 10.0)
	# The east wall is one side of the safehouse passage (wall-to-wall with the
	# corner building).
	k.run_panel("PassageWallW", "x+", -16.0, 36.0, 46.0, 0.0, 7.6)
	k.end()


## Walled courtyard behind the safehouse: the playground route-4 layout.
static func _courtyard(k: Kit) -> void:
	k.begin("Courtyard")
	k.box("RunWall", -30.6, -30.0, 0.0, 7.8, 46.0, 61.5, Kit.RUN)
	k.box("LoadingDeck", -30.0, -26.0, 0.0, 3.8, 59.0, 64.0, Kit.ROOF)
	# Pulled to from the billboard catwalk across the lot: straight into the
	# courtyard wall-run.
	k.anchor("AnchorLoadingDeck", Vector3(-29.6, 4.3, 62.8))
	k.ramp("DeckRamp", Vector3(-17.0, 0.0, 62.5), Vector3(-26.0, 3.8, 62.5), 3.0)
	k.building("GeneratorShed", -20.0, -14.5, 49.0, 55.0, 3.2, Kit.PROP)
	k.box("Van", -24.0, -22.0, 0.0, 2.2, 53.0, 58.5, Color(0.42, 0.46, 0.52))
	k.box("Crates", -15.5, -13.5, 0.0, 1.2, 60.0, 62.0, Color(0.55, 0.45, 0.32))
	k.end()


## x -13..-6.5, z 36..58: three storeys, climbable from Central Ave
## (awning -> balcony -> roof); its west wall faces the safehouse passage.
static func _corner_building(k: Kit) -> void:
	k.begin("CornerBuilding")
	k.building("Mass", -13.0, -6.5, 36.0, 58.0, 10.5, CORNER)
	k.run_panel("PassageWallE", "x-", -13.0, 36.0, 58.0, 0.0, 10.4)
	k.ledge_slab("Awning", "x+", -6.5, 39.0, 55.0, Kit.CLIMB_AWNING, 3.5)
	k.balcony("Balcony", "x+", -6.5, 42.0, 52.0)
	k.door("Door", "x+", -6.5, 56.5)
	k.ac_unit("RoofAC", -9.5, 50.0, 10.5, false)
	k.end()


## x -66..-33, z 33.5..70: open asphalt, parked cars, a billboard catwalk.
static func _parking_lot(k: Kit) -> void:
	k.begin("ParkingLot")
	k.box("Asphalt", -66, -33, 0.0, 0.02, 33.5, 70, Color(0.24, 0.25, 0.27))
	for i in 10:
		var x := -64.0 + i * 3.0
		k.box("StallLine", x - 0.07, x + 0.07, 0.02, 0.03, 40.0, 45.0, Kit.MARKING)
		k.box("StallLine", x - 0.07, x + 0.07, 0.02, 0.03, 56.0, 61.0, Kit.MARKING)
	k.car("CarA", -59.5, 42.5, Color(0.55, 0.2, 0.18))
	k.car("CarB", -50.5, 42.5, Color(0.3, 0.34, 0.42))
	k.car("CarC", -41.5, 58.5, Color(0.7, 0.68, 0.62))
	k.car("CarD", -56.5, 58.5, Color(0.25, 0.3, 0.26))
	k.car("CarE", -47.5, 58.5, Color(0.5, 0.48, 0.44))
	k.lamp("Lamp", -45.0, 50.0)
	k.lamp("Lamp", -58.0, 50.0)
	# Billboard on stilts: a catwalk at 9 m with an anchor, a vantage over
	# the lot and the safehouse.
	k.box("BillboardPostW", -52.3, -51.7, 0.0, 9.0, 66.7, 67.3, Kit.GRAPPLE)
	k.box("BillboardPostE", -44.3, -43.7, 0.0, 9.0, 66.7, 67.3, Kit.GRAPPLE)
	k.box("BillboardCatwalk", -54.0, -42.0, 8.7, 9.0, 65.0, 67.0, Kit.STEEL)
	k.box("BillboardPanel", -54.0, -42.0, 9.0, 14.0, 67.0, 67.4, Color(0.85, 0.8, 0.7))
	k.ladder("BillboardLadder", "z-", 65.0, -52.8, 0.0, 9.0)
	k.anchor("AnchorBillboard", Vector3(-48.0, 9.5, 65.6))
	var flood := SpotLight3D.new()
	flood.name = "BillboardFlood"
	flood.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.45, 1.0).normalized(), Vector3.UP), Vector3(-48.0, 8.0, 63.5))
	flood.light_color = Color(1.0, 0.92, 0.78)
	flood.light_energy = 3.0
	flood.spot_range = 12.0
	flood.spot_angle = 40.0
	flood.visible = false
	flood.set_meta(&"night_energy", 3.0)
	k._add(flood)
	flood.add_to_group(&"night_lights", true)
	k.sign("Sign", Vector3(-48.0, 3.0, 50.0), "PARKING", 48)
	k.end()


## Corner plaza (x 6.5..22, z 33.5..50) and the diner behind it.
static func _plaza_and_diner(k: Kit) -> void:
	k.begin("CornerPlaza")
	k.box("Paving", 6.5, 22.0, 0.0, 0.02, 33.5, 50.0, Kit.PLAZA)
	k.box("StatuePlinth", 12.5, 15.5, 0.0, 1.2, 40.0, 43.0, Color(0.58, 0.56, 0.52))
	k.box("Statue", 13.5, 14.5, 1.2, 4.2, 41.0, 42.0, Color(0.38, 0.36, 0.3))
	for p: Vector2 in [Vector2(9, 37), Vector2(19, 37), Vector2(9, 47), Vector2(19, 47)]:
		k.box("Planter", p.x - 1.0, p.x + 1.0, 0.0, 0.8, p.y - 1.0, p.y + 1.0, Color(0.46, 0.5, 0.4))
	k.box("Kiosk", 17.0, 20.0, 0.0, 2.6, 40.5, 42.5, Kit.PROP)
	k.box("KioskRoof", 16.5, 20.5, 2.6, 2.9, 40.0, 43.0, Kit.LEDGE)
	k.end()
	k.begin("Diner")
	k.building("Mass", 6.5, 22.0, 50.0, 68.0, 7.0, DINER)
	k.ledge_slab("Awning", "z-", 50.0, 9.0, 19.0, 2.2, 3.5)
	# East side: a ledge across from the walk-ups' plaza wall - wall-run it,
	# wall-jump across, grab the ledge, then the roof above.
	k.ledge_slab("SideLedge", "x+", 22.0, 50.5, 55.0, 1.0, 3.5)
	k.door("Door", "z-", 50.0, 14.0)
	k.night_glow("Neon", 11.0, 17.0, 3.7, 4.3, 49.85, 49.95, Color(0.95, 0.35, 0.45))
	k.vent("Vent", 8.5, 65.5, 7.0)
	k.ac_unit("RoofAC", 11.0, 60.0, 7.0)
	k.ac_unit("RoofAC", 17.0, 63.0, 7.0, false)
	k.end()


## Row of walk-ups along South St (z 36..54): 10.5 / 14 / 10.5 / 17.5 m.
## Roof to roof: step up (grab), drop, then a grapple to the tall end.
static func _walkups(k: Kit) -> void:
	k.begin("WalkUps")
	k.building("WalkUpA", 25.0, 36.0, 36.0, 54.0, 10.5, ROW_A)
	k.run_panel("PlazaWall", "x-", 25.0, 36.0, 54.0, 0.0, 10.4)
	k.door("DoorA", "z-", 36.0, 30.5)
	k.vent("Vent", 33.5, 51.0, 10.5)
	k.building("WalkUpB", 36.0, 46.0, 36.0, 54.0, 14.0, ROW_B)
	k.fire_escape("FireEscapeB", "z-", 36.0, 37.0, 45.0, [3.5, 7.0, 10.5, 14.0])
	k.roof_hut("RoofHutB", 42.0, 44.5, 48.0, 51.0, 14.0, ROW_B, "z-")
	k.door("DoorB", "z-", 36.0, 41.0)
	k.building("WalkUpC", 46.0, 57.0, 36.0, 54.0, 10.5, ROW_C)
	k.ledge_slab("AwningC", "z-", 36.0, 47.0, 56.0, Kit.CLIMB_AWNING, 3.5)
	k.balcony("BalconyC", "z-", 36.0, 48.5, 54.5)
	k.door("DoorC", "z-", 36.0, 51.5)
	k.ac_unit("RoofAC", 30.0, 46.0, 10.5)
	k.ac_unit("RoofAC", 52.0, 48.0, 10.5, false)
	k.building("WalkUpD", 57.0, 66.0, 36.0, 54.0, 17.5, ROW_B.darkened(0.1))
	k.anchor("AnchorWalkUpD", Vector3(57.4, 18.0, 45.0))
	# Or climb to the tall end: a ladder up from WalkUpC's roof.
	k.ladder("LadderD", "x-", 57.0, 50.0, 10.5, 17.5)
	# Across South St from the mid-rise gap roof: the loop between districts.
	k.anchor("AnchorWalkUpDNorth", Vector3(61.5, 18.0, 36.4))
	k.door("DoorD", "z-", 36.0, 61.5)
	k.end()


## Behind the walk-ups: a fenced court and a water tank on stilts.
static func _back_lot(k: Kit) -> void:
	k.begin("BackLot")
	k.box("Court", 27.0, 45.0, 0.0, 0.02, 57.0, 68.0, Color(0.36, 0.44, 0.5))
	var fence := Color(0.45, 0.47, 0.48)
	k.box("FenceN1", 27.0, 34.0, 0.0, 3.5, 57.0, 57.15, fence)
	k.box("FenceN2", 38.0, 45.0, 0.0, 3.5, 57.0, 57.15, fence)
	k.box("FenceS", 27.0, 45.0, 0.0, 3.5, 67.85, 68.0, fence)
	k.box("FenceW", 27.0, 27.15, 0.0, 3.5, 57.15, 67.85, fence)
	k.box("FenceE", 44.85, 45.0, 0.0, 3.5, 57.15, 67.85, fence)
	for p: Vector2 in [Vector2(50.7, 58.7), Vector2(54.3, 58.7), Vector2(50.7, 62.3), Vector2(54.3, 62.3)]:
		k.box("TankLeg", p.x - 0.2, p.x + 0.2, 0.0, 10.0, p.y - 0.2, p.y + 0.2, Kit.GRAPPLE)
	k.box("Tank", 50.0, 55.0, 10.0, 14.0, 58.0, 63.0, Kit.GRAPPLE)
	k.night_glow("TankLight", 52.3, 52.7, 14.0, 14.3, 60.3, 60.7, Color(1.0, 0.3, 0.2))
	k.anchor("AnchorTank", Vector3(52.5, 14.5, 58.4))
	k.dumpster("Dumpster", 24.0, 57.0, false)
	k.end()
