extends RefCounted
## SERVICE / ALLEY DISTRICT (west, x -66..-41, z -22.5..22.5).
##
## A loading yard ringed by three fire escapes (the walk-up's, the north
## tenement's to its roof, the south tenement's), with a raised loading deck
## between them (the anchor down Needle Alley's line). North of the yard: a
## walk-up whose fire escape tops out beside the taller tenement's brick flank
## - sprint along it, jump the gap, wall-run, wall-jump across the slot onto
## the next roof, grapple up the tenement; a catwalk joins the tenement's roof
## to the hotel's across the lane. South: a low workshop (a bin in the corner
## is the step up) and a second tenement with a 2.8 m brick slot between them
## (wall-run, wall-jump, grab the workshop roof).

const Kit := preload("res://tools/city/city_kit.gd")

const SVC_A := Color(0.52, 0.55, 0.5)
const SVC_B := Color(0.46, 0.48, 0.46)
const SVC_C := Color(0.58, 0.56, 0.5)


static func build(k: Kit) -> void:
	k.begin("ServiceDistrict")
	_north_row(k)
	_yard(k)
	_south_row(k)
	_lane(k)
	k.sign("Sign", Vector3(-45.0, 4.0, 0.0), "SERVICE YARD", 48)
	k.start_marker("Start3", Vector3(-55.0, 0.05, -1.0), 0.0)
	k.end()


## Tenement (x -49..-41, 17.5 m), walk-up (x -60..-49, 10.5 m), the roof
## beyond the gap (x -66..-52, 11 m) and a shed.
static func _north_row(k: Kit) -> void:
	k.begin("NorthRow")
	k.building("Tenement", -49.0, -41.0, -22.5, -6.0, 17.5, SVC_A)
	# Its west flank: brick all the way down in the slot, above the walk-up's
	# roof where they touch.
	k.run_panel("TenementFlank", "x-", -49.0, -22.5, -12.0, 0.0, 17.4)
	k.run_panel("TenementFlankUpper", "x-", -49.0, -12.0, -6.0, 10.5, 17.4)
	k.box("LoadingDock", -41.0, -39.0, 0.0, 1.2, -20.0, -10.0, Color(0.55, 0.55, 0.52))
	k.face_box("Shutter", "x+", -41.0, 0.0, 0.05, -18.0, -14.0, 1.2, 4.4, Kit.DARK)
	k.roof_hut("TenementRoofHut", -45.0, -42.5, -12.0, -9.0, 17.5, SVC_A, "z-")
	# From the yard to its roof (and level to level with the walk-up's).
	k.fire_escape("TenementFireEscape", "z+", -6.0, -48.8, -41.2, [3.5, 7.0, 10.5, 14.0, 17.5])
	k.vent("Vent", -47.0, -14.0, 17.5)
	k.anchor("AnchorTenementWest", Vector3(-48.6, 18.0, -19.0))
	# Faces North Ave and the construction site: pulled to from the site's
	# beams and its office's south window.
	k.anchor("AnchorTenementNorth", Vector3(-45.0, 18.0, -22.1))

	k.building("WalkUp", -60.0, -49.0, -12.0, -6.0, 10.5, SVC_B)
	k.fire_escape("WalkUpFireEscape", "z+", -6.0, -59.0, -51.0, [3.5, 7.0, 10.5])
	k.building("GapRoof", -66.0, -52.0, -22.5, -15.5, 11.0, SVC_C)
	k.ladder("GapRoofLadder", "z-", -22.5, -58.0, 0.0, 11.0) # a way up from North Ave
	k.ac_unit("GapRoofAC", -61.0, -19.0, 11.0)
	k.vent("Vent", -55.0, -17.5, 11.0)
	k.building("Shed", -66.0, -60.0, -12.0, -6.0, 4.0, SVC_B)
	k.end()


## Loading yard z -6..6 with a raised deck (9 m) joining the two fire escapes.
static func _yard(k: Kit) -> void:
	k.begin("Yard")
	for p: Vector2 in [Vector2(-53.7, -2.7), Vector2(-48.3, -2.7), Vector2(-53.7, 2.7), Vector2(-48.3, 2.7)]:
		k.box("DeckLeg", p.x - 0.2, p.x + 0.2, 0.0, 8.6, p.y - 0.2, p.y + 0.2, Kit.GRAPPLE)
	k.box("LoadingDeck", -54.0, -48.0, 8.6, 9.0, -3.0, 3.0, Kit.STEEL)
	k.anchor("AnchorYardDeck", Vector3(-48.4, 9.5, 0.0))
	k.box("Container", -65.8, -63.3, 0.0, 2.6, -4.0, 2.0, Color(0.55, 0.3, 0.22))
	k.box("Pallets", -62.0, -60.8, 0.0, 1.2, 3.0, 4.2, Color(0.55, 0.45, 0.32))
	k.dumpster("Dumpster", -42.0, 2.0)
	k.dumpster("Dumpster", -58.0, 4.5)
	k.box("Forklift", -46.0, -44.0, 0.0, 2.1, -1.5, 0.0, Color(0.8, 0.62, 0.2))
	k.end()


## Workshop (x -66..-53, 4.5 m) and tenement (x -50..-41, 14 m).
static func _south_row(k: Kit) -> void:
	k.begin("SouthRow")
	k.building("Workshop", -66.0, -53.0, 9.0, 22.5, 4.5, SVC_C)
	k.face_box("ShutterA", "z-", 9.0, 0.0, 0.05, -63.0, -59.0, 0.0, 3.2, Kit.DARK)
	k.face_box("ShutterB", "z-", 9.0, 0.0, 0.05, -58.0, -54.0, 0.0, 3.2, Kit.DARK)
	k.run_panel("SlotWallW", "x+", -53.0, 9.0, 22.5, 0.0, 4.4)
	# A step up in the yard's corner: from its lid the workshop roof is a grab.
	k.dumpster("Dumpster", -64.5, 8.2)
	k.box("Skylight", -63.0, -60.0, 4.5, 5.0, 13.0, 18.0, Color(0.55, 0.62, 0.66))
	k.building("Tenement", -50.0, -41.0, 6.0, 22.5, 14.0, SVC_A)
	k.run_panel("SlotWallE", "x-", -50.0, 6.0, 22.5, 0.0, 13.9)
	k.fire_escape("TenementFireEscape", "z-", 6.0, -49.0, -42.0, [3.5, 7.0, 10.5, 14.0])
	k.ac_unit("TenementRoofAC", -45.0, 16.0, 14.0, false)
	k.vent("Vent", -48.0, 11.0, 14.0)
	k.door("Door", "x+", -41.0, 12.0)
	k.end()


## West Service Lane (x -41..-35): service clutter kept to the edges.
static func _lane(k: Kit) -> void:
	k.begin("Lane")
	k.dumpster("Dumpster", -39.8, 15.0, false)
	k.dumpster("Dumpster", -36.2, -12.0, false)
	k.box("UtilityBox", -40.9, -40.2, 0.0, 1.6, 18.5, 19.7, Kit.PROP)
	k.end()
