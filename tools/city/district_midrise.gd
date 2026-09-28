extends RefCounted
## MID-RISE ROOFTOP DISTRICT (east, x 36.5..66, z -22.5..22.5).
##
## A loop of 10.5-17.5 m roofs to run at speed: the skybridge lands on the
## first; a 3 m gap up to a roof 3.5 m higher (jump and grab); a 3 m drop-gap;
## then a 9 m gap no jump clears, with the tall block's brick flank alongside
## it for a wall-run across. The tall block (24.5 m) also forms a brick slot
## with a low roof on its west side. A service passage along the east edge
## keeps every ground-level gap open to the streets. The loop doesn't stop at
## the south gap roof: grapple across South St to the tall walk-up (its north
## edge anchor), or take its fire escape down.

const Kit := preload("res://tools/city/city_kit.gd")

const MID_A := Color(0.74, 0.7, 0.62)
const MID_B := Color(0.66, 0.62, 0.58)
const MID_C := Color(0.7, 0.66, 0.6)
const MID_D := Color(0.6, 0.6, 0.62)


static func build(k: Kit) -> void:
	k.begin("MidriseDistrict")
	# North row.
	k.building("BridgeBlock", 36.5, 48.0, -22.5, -4.0, 14.0, MID_A)
	k.ac_unit("BridgeBlockAC", 42.0, -15.0, 14.0)
	k.roof_hut("BridgeBlockHut", 44.0, 46.5, -21.0, -18.5, 14.0, MID_A, "z+")
	k.vent("Vent", 38.5, -20.5, 14.0)
	k.ledge_slab("BridgeBlockAwning", "x-", 36.5, -20.0, -9.0, 2.2, 3.5)
	k.door("Door", "x-", 36.5, -14.5)
	k.building("HighRoof", 51.0, 66.0, -22.5, -11.0, 17.5, MID_B)
	k.water_tower("WaterTower", 61.0, -17.0, 17.5, "x-")
	k.vent("Vent", 53.0, -13.0, 17.5)
	k.anchor("AnchorHighRoofNorth", Vector3(56.0, 18.0, -22.1))
	# Middle / south: the 9 m gap between these two, along the tall block.
	k.building("GapRoofN", 53.0, 62.0, -8.0, 4.0, 15.5, MID_C)
	k.ac_unit("GapRoofNAC", 59.0, -4.0, 15.5, false)
	k.vent("Vent", 55.0, 2.0, 15.5)
	k.building("GapRoofS", 53.0, 62.0, 13.0, 22.5, 15.5, MID_C.darkened(0.06))
	k.ac_unit("GapRoofSAC", 59.0, 18.0, 15.5, false)
	# Both roofs by the 9 m gap can also be reached from the street: a fire
	# escape on South St (ladder up its last 1.5 m) and a drainpipe on the
	# service passage.
	k.fire_escape("GapRoofSFireEscape", "z+", 22.5, 53.5, 61.5, [3.5, 7.0, 10.5, 14.0], true, false, 15.5)
	k.ladder("GapRoofNLadder", "x+", 62.0, -2.0, 0.0, 15.5)
	k.building("TallBlock", 44.0, 53.0, -1.0, 22.5, 24.5, MID_D)
	k.run_panel("TallFlankE", "x+", 53.0, -1.0, 22.5, 15.5, 24.4)
	k.run_panel("TallFlankW", "x-", 44.0, -1.0, 22.5, 0.0, 21.0)
	k.anchor("AnchorTallWest", Vector3(44.4, 25.0, 8.0))
	k.roof_hut("TallHut", 47.0, 50.0, 15.0, 18.0, 24.5, MID_D, "z-")
	k.building("LowRoof", 36.5, 41.0, -1.0, 22.5, 10.5, MID_B)
	k.run_panel("LowRoofFlank", "x+", 41.0, -1.0, 22.5, 0.0, 10.4)
	k.fire_escape("LowRoofFireEscape", "x-", 36.5, 4.0, 12.0, [3.5, 7.0, 10.5])
	k.ledge_slab("LowRoofAwning", "z+", 22.5, 37.0, 40.5, 2.2, 3.5)
	k.door("LowRoofDoor", "x-", 36.5, 16.0)
	# Service passage along the east edge (x 62..66): bins, nothing else.
	k.dumpster("Dumpster", 64.0, 8.0, false)
	k.dumpster("Dumpster", 64.0, -9.5, false)
	k.sign("Sign", Vector3(38.0, 17.0, -8.0), "MID-RISE ROOFS", 48)
	k.end()
