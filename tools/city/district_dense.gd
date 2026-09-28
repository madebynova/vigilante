extends RefCounted
## DENSE BLOCKS (centre, z -22.5..22.5 either side of Central Ave).
##
## West block: Needle Alley, a compact 14.5 m slot (2.8 m clear) between the
## avenue block and the Window Building, with brick on both walls and ledges
## that alternate across it on the way up; its west end opens into the hotel
## yard (a fire escape up the walk-up, an anchor on its roof edge). The Hotel
## (17.5 m) has a fire escape on North Ave whose third level has a dive window
## into a corridor right through the building, out over the yard; a catwalk
## joins its roof to the service tenement across the lane. South: the walk-up
## (fire escape on the lane, awning -> balcony -> roof on South St) and the
## Window Building, whose top floor has a dive window on every side.
## East block: the corner block (fire escape on South St, anchor facing the
## Window Building), a low annexe with a brick slot between them, and a
## stepped office (tower fire escape on East St) carrying the skybridge.

const Kit := preload("res://tools/city/city_kit.gd")

const HOTEL := Color(0.6, 0.56, 0.52)
const SAND := Color(0.7, 0.64, 0.54)
const STONE := Color(0.6, 0.58, 0.55)
const OCHRE := Color(0.66, 0.6, 0.5)
const WARM := Color(1.0, 0.82, 0.55)


static func build(k: Kit) -> void:
	k.begin("DenseBlocks")
	_hotel_block(k)
	_needle_alley(k)
	_window_block(k)
	_east_block(k)
	k.sign("SignNeedleAlley", Vector3(-5.6, 4.2, 0.0), "NEEDLE ALLEY", 48)
	k.start_marker("Start2", Vector3(-3.0, 0.05, -0.8), 90.0)
	k.end()


## North of Needle Alley: Hotel (x -35..-21) and a 3-storey block (x -21..-6.5).
static func _hotel_block(k: Kit) -> void:
	k.begin("Hotel")
	# Solid but for a corridor through its fourth storey (10.5 - 14 m, x
	# -26.5..-22.5), with a dive window at each end: in from the fire escape's
	# third level on North Ave, out over the hotel yard.
	k.box("Mass", -35.0, -21.0, 0.0, 10.5, -22.5, -1.5, HOTEL)
	k.box("MassW", -35.0, -26.5, 10.5, 14.0, -22.5, -1.5, HOTEL)
	k.box("MassE", -22.5, -21.0, 10.5, 14.0, -22.5, -1.5, HOTEL)
	k.box("MassUpper", -35.0, -21.0, 14.0, 17.2, -22.5, -1.5, HOTEL)
	k.box("MassRoof", -35.0, -21.0, 17.2, 17.5, -22.5, -1.5, Kit.ROOF)
	k.register_facade(-35.0, -21.0, -22.5, -1.5, 0.0, 17.2)
	var sill := 11.4
	k.wall("CorridorN", "z", -22.35, 0.3, -26.5, -22.5, 10.5, 14.0, HOTEL, [Kit.window_hole(-24.5, sill)])
	k.wall("CorridorS", "z", -1.65, 0.3, -26.5, -22.5, 10.5, 14.0, HOTEL, [Kit.window_hole(-24.5, sill)])
	k.dive_window("CorridorWindowN", "z", -22.35, -24.5, sill, Vector3(6.0, 4.5, 10.0))
	k.dive_window("CorridorWindowS", "z", -1.65, -24.5, sill, Vector3(6.0, 4.5, 10.0))
	k.night_light("CorridorLight", Vector3(-24.5, 13.3, -12.0), WARM, 1.4, 14.0)
	# A classic fire escape: no stair from the street, a drop ladder (or a
	# jump-and-grab at its first level) instead.
	k.fire_escape("FireEscape", "z-", -22.5, -33.0, -24.0, [3.5, 7.0, 10.5, 14.0, 17.5], false, true)
	# Sprint east along its second level (7 m), jump off the end and wall-run
	# the north face over North Ave: drop to the awning, wall-jump out and
	# grapple the Meridian terrace, or grapple up to the hotel roof.
	k.run_panel("NorthRunWall", "z-", -22.5, -27.0, -12.0, 7.0, 9.9)
	# The hotel's east wall rises 7 m above its neighbour's roof: a rooftop
	# wall-run that leaves you over North Ave, facing the Meridian terrace.
	k.run_panel("RoofRunWall", "x+", -21.0, -22.5, -1.5, 10.5, 17.4)
	k.door("BackDoor", "z+", -1.5, -31.0)
	k.water_tower("WaterTower", -31.0, -8.0, 17.5, "z+")
	k.anchor("AnchorHotelNorth", Vector3(-23.0, 18.0, -22.1))
	k.box("SignFrame", -22.4, -21.8, 17.5, 20.5, -17.0, -8.0, Kit.PROP)
	k.sign("Sign", Vector3(-21.75, 19.0, -12.5), "HOTEL", 160, Vector3.RIGHT)
	k.roof_hut("RoofHut", -27.0, -24.5, -16.0, -13.0, 17.5, HOTEL, "z+")
	k.vent("Vent", -32.0, -14.5, 17.5)
	k.vent("Vent", -24.0, -4.5, 17.5)
	# Roof to roof over the West Service Lane: the service tenement is the same
	# height.
	k.catwalk("CatwalkToTenement", Vector3(-41.0, 17.5, -18.9), Vector3(-35.0, 17.5, -18.9))
	k.end()

	k.begin("AvenueBlock")
	k.building("Mass", -21.0, -6.5, -22.5, -1.5, 10.5, SAND)
	k.ledge_slab("AvenueAwning", "x+", -6.5, -20.0, -4.0, Kit.CLIMB_AWNING, 3.5)
	k.balcony("AvenueBalcony", "x+", -6.5, -17.0, -7.0)
	k.ledge_slab("NorthAwning", "z-", -22.5, -19.0, -8.5, 2.2, 3.5)
	k.door("Door", "x+", -6.5, -12.0)
	k.ac_unit("RoofAC", -15.0, -12.0, 10.5)
	k.ac_unit("RoofAC", -10.0, -6.0, 10.5, false)
	k.vent("Vent", -18.5, -9.0, 10.5)
	k.roof_hut("RoofHut", -12.0, -9.5, -20.0, -17.0, 10.5, SAND, "z+")
	k.end()


## Needle Alley (x -21..-6.5): 2.8 m clear between the avenue block (north)
## and the walk-up wing / light well / Window Building (south), open to
## Central Ave and to the hotel yard. Brick on both walls for wall-run ->
## wall-jump chains. Ledges alternate across it on the way up, each a jump
## across and up from the last: south 3.5 m (drainpipe or a jump-and-grab from
## the alley), north 7 m (the avenue block's roof is a grab above it), south
## 10.5 m in front of the Window Building's north window (E in; its roof is a
## grab above). A route up, not a ladder: the wall-runs, the hotel yard and
## the roofs either side all join it.
static func _needle_alley(k: Kit) -> void:
	k.begin("NeedleAlley")
	k.run_panel("WallNorth", "z+", -1.5, -21.0, -6.5, 0.0, 10.0)
	k.run_panel("WallSouth", "z-", 1.5, -21.0, -6.5, 0.0, 10.0)
	# Each ledge overlaps the next along the alley by about a metre: stand on
	# its end, face across, jump and grab (0.8 m across, 3.5 m up).
	k.ledge_slab("LedgeS1", "z-", 1.4, -21.0, -16.5, 1.0, 3.5)
	k.ladder("PipeS1", "z-", 0.4, -20.4, 0.0, 3.5, 0.7)
	k.ledge_slab("LedgeN2", "z+", -1.4, -17.5, -12.0, 1.0, 7.0)
	k.ledge_slab("LedgeS3", "z-", 1.4, -12.8, -8.5, 1.1, 10.5)
	k.night_light("AlleyLight", Vector3(-14.0, 5.0, 0.0), WARM, 1.2, 10.0)
	k.end()


## The hotel yard (x -35..-21, z -1.5..5.5, where the alley's west half used
## to be), south of Needle Alley: the walk-up (x -35..-21 behind the yard,
## with a wing x -21..-18 along the alley), a light well, the Window Building
## (x -15..-6.5).
static func _window_block(k: Kit) -> void:
	k.begin("WalkUp")
	k.building("Mass", -35.0, -21.0, 5.5, 22.5, 10.5, STONE)
	k.building("Wing", -21.0, -18.0, 1.5, 22.5, 10.5, STONE)
	k.fire_escape("FireEscape", "x-", -35.0, 7.0, 15.0, [3.5, 7.0, 10.5])
	# Hotel yard: a fire escape up the walk-up, an anchor on its roof edge (a
	# grapple out of the hotel corridor's south window), bins.
	k.fire_escape("YardFireEscape", "z-", 5.5, -34.0, -26.0, [3.5, 7.0, 10.5])
	k.anchor("AnchorWalkUpYard", Vector3(-23.5, 11.0, 5.9))
	k.dumpster("Dumpster", -28.5, -0.8)
	# South St facade: awning -> balcony -> roof (kept west of the grapple line
	# from the safehouse loft at x -27.1).
	k.ledge_slab("StreetAwning", "z+", 22.5, -34.0, -29.2, Kit.CLIMB_AWNING, 3.5)
	k.balcony("StreetBalcony", "z+", 22.5, -33.0, -29.5)
	k.ledge_slab("StreetAwningE", "z+", 22.5, -25.0, -19.0, 2.2, 3.5)
	k.door("Door", "z+", 22.5, -22.0)
	k.roof_hut("RoofHut", -33.0, -30.5, 15.0, 18.0, 10.5, STONE, "x+")
	k.ac_unit("RoofAC", -26.0, 9.5, 10.5)
	# A raised plant room: vault onto it, or use it as a step.
	k.box("PlantRoom", -30.0, -26.5, 10.5, 11.7, 12.0, 15.0, STONE.darkened(0.12))
	k.vent("Vent", -23.0, 18.5, 10.5)
	# Grapple target from the safehouse loft's front window.
	k.anchor("AnchorWalkUpSouth", Vector3(-27.1, 11.0, 22.1))
	k.end()

	k.begin("WindowBuilding")
	var sill := 11.4
	k.box("Mass", -15.0, -6.5, 0.0, 10.4, 1.5, 22.5, OCHRE)
	k.register_facade(-15.0, -6.5, 1.5, 22.5, 0.0, 10.4)
	k.box("TopFloor", -15.0, -6.5, 10.4, 10.5, 1.5, 22.5, Kit.FLOOR)
	k.wall("WallW", "x", -14.85, 0.3, 1.5, 22.5, 10.5, 13.7, OCHRE, [Kit.window_hole(12.0, sill)])
	k.wall("WallE", "x", -6.65, 0.3, 1.5, 22.5, 10.5, 13.7, OCHRE, [Kit.window_hole(12.0, sill)])
	k.wall("WallN", "z", 1.65, 0.3, -14.7, -6.8, 10.5, 13.7, OCHRE, [Kit.window_hole(-10.75, sill)])
	k.wall("WallS", "z", 22.35, 0.3, -14.7, -6.8, 10.5, 13.7, OCHRE, [Kit.window_hole(-10.75, sill)])
	k.box("Roof", -15.0, -6.5, 13.7, 14.0, 1.5, 22.5, Kit.ROOF)
	# Drainpipe from Central Ave to the roof (away from the alley's run wall).
	k.ladder("RoofLadder", "x+", -6.5, 2.4, 0.0, 14.0)
	k.dive_window("WindowWest", "x", -14.85, 12.0, sill)
	k.dive_window("WindowEast", "x", -6.65, 12.0, sill)
	k.dive_window("WindowNorth", "z", 1.65, -10.75, sill)
	k.dive_window("WindowSouth", "z", 22.35, -10.75, sill)
	k.night_light("TopFloorLight", Vector3(-10.75, 13.1, 12.0), WARM, 1.6, 14.0)
	k.box("Column", -11.0, -10.5, 10.5, 13.7, 6.75, 7.25, OCHRE)
	k.box("Column", -11.0, -10.5, 10.5, 13.7, 16.75, 17.25, OCHRE)
	k.box("Crates", -14.2, -12.8, 10.5, 11.5, 19.5, 21.5, Color(0.55, 0.45, 0.32))
	k.ledge_slab("AvenueAwningN", "x+", -6.5, 3.0, 10.0, 2.2, 3.5)
	k.ledge_slab("AvenueAwningS", "x+", -6.5, 14.0, 21.0, 2.2, 3.5)
	k.door("Door", "x+", -6.5, 12.0)
	k.end()


## x 6.5..25.5 between Central Ave and East St.
static func _east_block(k: Kit) -> void:
	k.begin("EastBlock")
	k.building("Corner", 6.5, 17.0, 2.0, 22.5, 14.0, STONE)
	k.ledge_slab("CornerAwning", "x-", 6.5, 4.0, 20.0, 2.2, 3.5)
	k.run_panel("SlotWallW", "x+", 17.0, 2.0, 22.5, 0.0, 13.9)
	# From South St straight to its roof.
	k.fire_escape("CornerFireEscape", "z+", 22.5, 8.0, 16.0, [3.5, 7.0, 10.5, 14.0])
	k.door("CornerDoor", "x-", 6.5, 12.0)
	k.roof_hut("CornerRoofHut", 13.0, 15.5, 18.0, 20.5, 14.0, STONE, "x-")
	k.ac_unit("CornerRoofAC", 12.0, 8.0, 14.0)
	k.vent("Vent", 9.0, 16.0, 14.0)
	# Faces the Window Building's east window across the avenue.
	k.anchor("AnchorCornerWest", Vector3(6.9, 14.5, 12.0))

	k.building("Annexe", 20.0, 25.5, 2.0, 22.5, 7.0, SAND)
	k.run_panel("SlotWallE", "x-", 20.0, 2.0, 22.5, 0.0, 6.9)
	k.fire_escape("AnnexeFireEscape", "x+", 25.5, 6.0, 14.0, [3.5, 7.0])
	k.ledge_slab("AnnexeAwning", "z+", 22.5, 20.5, 25.0, 2.2, 3.5)
	k.door("AnnexeDoor", "z+", 22.5, 22.75)

	k.dumpster("Dumpster", 12.0, 0.0)
	k.dumpster("Dumpster", 22.0, 0.0)

	# Stepped office: lower mass 14 m, tower 24.5 m on its north-east part.
	k.building("Office", 6.5, 25.5, -22.5, -2.0, 14.0, OCHRE)
	k.building("OfficeTower", 13.0, 25.5, -22.5, -9.0, 24.5, OCHRE.darkened(0.08), 14.0)
	# Run north along the tower on the lower roof, off the edge over North Ave,
	# then grapple the Spire's base.
	k.run_panel("TowerRunWall", "x-", 13.0, -22.5, -9.0, 14.0, 24.4)
	k.ledge_slab("NorthAwning", "z-", -22.5, 8.0, 24.0, 2.2, 3.5)
	# East St: a fire escape all the way up the tower's face to its roof.
	k.fire_escape("TowerFireEscape", "x+", 25.5, -21.0, -12.0, [3.5, 7.0, 10.5, 14.0, 17.5, 21.0, 24.5])
	k.door("Lobby", "x-", 6.5, -12.0, 2.4, 2.8)
	k.roof_hut("OfficeRoofHut", 7.0, 9.5, -6.0, -3.5, 14.0, OCHRE, "x+")
	k.ac_unit("OfficeRoofAC", 18.0, -5.5, 14.0)
	k.vent("Vent", 10.0, -15.0, 14.0)
	k.anchor("AnchorOfficeTower", Vector3(19.0, 25.0, -8.6))
	# Skybridge over East St to the mid-rise roofs (same 14 m level).
	k.box("Skybridge", 25.5, 36.5, 13.7, 14.0, -7.5, -4.5, Kit.STEEL)
	k.box("SkybridgeRailN", 25.5, 36.5, 14.0, 15.0, -7.5, -7.3, Kit.STEEL)
	k.box("SkybridgeRailS", 25.5, 36.5, 14.0, 15.0, -4.7, -4.5, Kit.STEEL)
	k.box("SkybridgeBeam", 25.5, 36.5, 13.0, 13.7, -6.3, -5.7, Kit.STEEL)
	k.start_marker("Start4", Vector3(23.5, 14.05, -6.0), -90.0)
	k.end()
