extends RefCounted
## Authoring helpers for the city greybox (see build_city.gd).
##
## Every piece is placed by hand from world-space extents (x0..x1, y0..y1,
## z0..z1, in metres) and becomes an ordinary level node: GreyboxBlock,
## TraversalWindow, GrappleAnchor, Label3D or Marker3D. Nothing here is
## random; the helpers only save retyping the same box maths.
##
## Faces are named by the axis of their outward normal: "x+" is a face at
## x = `at` looking toward +X, "z-" a face at z = `at` looking toward -Z. The
## `u` range of a face runs along it (z for x-faces, x for z-faces).

# Visual language (see README "City greybox").
const RUN := Color(0.72, 0.45, 0.3) ## runnable wall surfaces (brick)
const ROOF := Color(0.42, 0.48, 0.58) ## rooftops, decks and platforms
const STEEL := Color(0.33, 0.47, 0.4) ## fire escapes, stairs, bridges
const LEDGE := Color(0.42, 0.6, 0.5) ## awnings and balconies (grabbable)
const FRAME := Color(0.96, 0.82, 0.3) ## dive window sills and headers
const GRAPPLE := Color(0.3, 0.62, 0.64) ## structures carrying a grapple anchor
const PROP := Color(0.36, 0.38, 0.4) ## dumpsters, AC units, vents, fences
const DARK := Color(0.2, 0.2, 0.22) ## doors, roll-up shutters
const ASPHALT := Color(0.2, 0.21, 0.23)
const PAVEMENT := Color(0.5, 0.5, 0.48)
const PLAZA := Color(0.6, 0.57, 0.52)
const MARKING := Color(0.86, 0.85, 0.8)
const FLOOR := Color(0.5, 0.45, 0.4) ## interior floors
const BACKDROP := Color(0.34, 0.36, 0.4)
const CLIMB := Color(0.95, 0.55, 0.12) ## climbable: ladders, drainpipes, scaffold ladders

## Physics layers of climbable pieces: world (1) + climbable (3). Only these
## can be climbed (see ParkourSensor.climb_mask).
const CLIMB_LAYERS := 1 | 4

## Standard storey height; ledges and roofs sit on multiples of it so the
## jump-and-grab reach (about 3.7 m from a floor) always lines up.
const STOREY := 3.5
## Depth of an awning with a balcony above it (see balcony()).
const CLIMB_AWNING := 2.6

var root: Node3D
var _stack: Array[Node3D] = []
var _facades: Array[Dictionary] = []
var _decor_material: ShaderMaterial
var _glow_materials := {}


func _init(scene_root: Node3D) -> void:
	root = scene_root
	_stack.append(root)


## Starts a named group node; everything added until end() goes inside it.
func begin(group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	_add(node)
	_stack.append(node)
	return node


func end() -> void:
	_stack.pop_back()


func _add(node: Node) -> void:
	_stack.back().add_child(node, true)
	node.owner = root


# --- Boxes -------------------------------------------------------------------

## Axis-aligned box from world extents.
func box(node_name: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
		color: Color) -> GreyboxBlock:
	var b := GreyboxBlock.new()
	b.name = node_name
	b.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	b.color = color
	b.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	_add(b)
	return b


## Sloped slab (ramp or stair flight) whose walking surface runs from `a` up
## to `b`.
func ramp(node_name: String, a: Vector3, b: Vector3, width: float, color := STEEL,
		thickness := 0.25) -> GreyboxBlock:
	var fwd := (b - a).normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	var up := fwd.cross(side)
	var blk := GreyboxBlock.new()
	blk.name = node_name
	blk.size = Vector3(width, thickness, a.distance_to(b) + 0.1)
	blk.color = color
	blk.transform = Transform3D(Basis(side, up, fwd), (a + b) * 0.5 - up * thickness * 0.5)
	_add(blk)
	return blk


## Solid building mass with a walkable roof cap on top. Its facades get glass
## windows in dress_windows() unless `windows` is false.
func building(node_name: String, x0: float, x1: float, z0: float, z1: float, height: float,
		color: Color, base := 0.0, windows := true) -> void:
	box(node_name, x0, x1, base, height - 0.3, z0, z1, color)
	box(node_name + "Roof", x0, x1, height - 0.3, height, z0, z1, ROOF)
	if windows:
		register_facade(x0, x1, z0, z1, base, height - 0.3)


## Box against a face: `n0..n1` out from the face, `u0..u1` along it.
func face_box(node_name: String, face: String, at: float, n0: float, n1: float, u0: float,
		u1: float, y0: float, y1: float, color: Color) -> GreyboxBlock:
	match face:
		"x+":
			return box(node_name, at + n0, at + n1, y0, y1, u0, u1, color)
		"x-":
			return box(node_name, at - n1, at - n0, y0, y1, u0, u1, color)
		"z+":
			return box(node_name, u0, u1, y0, y1, at + n0, at + n1, color)
		_:
			return box(node_name, u0, u1, y0, y1, at - n1, at - n0, color)


## World point `n` out from a face at `u` along it.
func face_point(face: String, at: float, n: float, u: float, y: float) -> Vector3:
	match face:
		"x+":
			return Vector3(at + n, y, u)
		"x-":
			return Vector3(at - n, y, u)
		"z+":
			return Vector3(u, y, at + n)
		_:
			return Vector3(u, y, at - n)


## Runnable wall surface: a thin brick panel on a face. Wall-runs work on any
## tall flat wall; the panel marks the intended ones.
func run_panel(node_name: String, face: String, at: float, u0: float, u1: float, y0: float,
		y1: float) -> void:
	face_box(node_name, face, at, 0.0, 0.1, u0, u1, y0, y1, RUN)


## Awning: a 0.5 m thick slab out of a face whose top is at `top` (3.5 m is
## in jump-and-grab reach from the street).
func ledge_slab(node_name: String, face: String, at: float, u0: float, u1: float, depth: float,
		top: float) -> void:
	face_box(node_name, face, at, 0.0, depth, u0, u1, top - 0.5, top, LEDGE)


## Balcony with a solid front, 1.2 m deep and 1.2 m tall, top at `top`. Put
## it 3.5 m above a CLIMB_AWNING-deep awning: climbing onto the awning leaves
## you 0.4 m in front of the balcony's face, so a jump meets the face (not its
## underside) and grabs the top; from the balcony the roof 3.5 m higher is the
## next grab.
func balcony(node_name: String, face: String, at: float, u0: float, u1: float, top := 7.0) -> void:
	face_box(node_name, face, at, 0.0, 1.2, u0, u1, top - 1.2, top, LEDGE)


# --- Walls and windows -------------------------------------------------------

## Wall in the plane x = `at` (axis "x") or z = `at` (axis "z"), `t` thick,
## from u0 to u1 along it and y0 to y1. `holes` are openings:
## {u = centre, w = width, b = bottom, t = top, frame = Color (optional)};
## the pieces below and above an opening take `frame` (or the wall colour).
func wall(node_name: String, axis: String, at: float, t: float, u0: float, u1: float, y0: float,
		y1: float, color: Color, holes: Array = []) -> void:
	var sorted := holes.duplicate()
	sorted.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.u < q.u)
	var cursor := u0
	var i := 0
	for hole: Dictionary in sorted:
		var h0: float = hole.u - hole.w * 0.5
		var h1: float = hole.u + hole.w * 0.5
		var fc: Color = hole.get("frame", color)
		if h0 > cursor + 0.01:
			_wall_piece("%s%d" % [node_name, i], axis, at, t, cursor, h0, y0, y1, color)
			i += 1
		if hole.b > y0 + 0.01:
			_wall_piece("%sSill%d" % [node_name, i], axis, at, t, h0, h1, y0, hole.b, fc)
		if hole.t < y1 - 0.01:
			_wall_piece("%sHeader%d" % [node_name, i], axis, at, t, h0, h1, hole.t, y1, fc)
		cursor = h1
	if u1 > cursor + 0.01:
		_wall_piece("%s%d" % [node_name, i], axis, at, t, cursor, u1, y0, y1, color)


func _wall_piece(node_name: String, axis: String, at: float, t: float, a: float, b: float,
		y0: float, y1: float, color: Color) -> void:
	if axis == "x":
		box(node_name, at - t * 0.5, at + t * 0.5, y0, y1, a, b, color)
	else:
		box(node_name, a, b, y0, y1, at - t * 0.5, at + t * 0.5, color)


## Standard dive window opening for wall(): 1.6 m wide, 1.2 m tall, framed.
static func window_hole(u: float, sill: float) -> Dictionary:
	return {u = u, w = 1.6, b = sill, t = sill + 1.2, frame = FRAME}


## Dive window (E only, from either side) on the sill of an opening at `u`
## along the wall at `at` (axis as in wall(), wall 0.3 thick). The approach
## zone is generous so mid-jump approaches register too.
func dive_window(node_name: String, axis: String, at: float, u: float, sill: float,
		zone := Vector3(8.0, 4.5, 10.0)) -> TraversalWindow:
	var w := TraversalWindow.new()
	w.name = node_name
	w.collision_layer = 0
	w.collision_mask = 2
	w.monitorable = false
	if axis == "z":
		w.transform = Transform3D(Basis(), Vector3(u, sill, at))
	else:
		w.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(at, sill, u))
	_add(w)
	var shape := CollisionShape3D.new()
	shape.name = "ApproachZone"
	var box_shape := BoxShape3D.new()
	box_shape.size = zone
	shape.shape = box_shape
	shape.position = Vector3(0.0, 0.3, 0.0)
	w.add_child(shape)
	shape.owner = root
	return w


# --- Traversal structures ----------------------------------------------------

## Fire escape on a face. Each level has a walkway along the face and a
## landing at both ends; stair flights on the outer strip all climb toward u1,
## so between flights you walk back along the walkway. The top level can sit
## flush with the roof to step off onto it. Every level is a 0.5 m slab, so its
## outer edge is a grabbable ledge like an awning (the first level, 3.5 m, is a
## jump-and-grab from the street) and there is 3 m of head room under each.
## `ground_stair` false leaves out the flight from the street. `drop_ladder`
## hangs a climbable ladder from the outer edge of the first level's u0
## landing down to the street. `roof_ladder_to` (a roof height above the top
## level) runs a ladder up the face from the top walkway's u1 end to that roof.
func fire_escape(node_name: String, face: String, at: float, u0: float, u1: float,
		levels: Array, ground_stair := true, drop_ladder := false, roof_ladder_to := 0.0) -> void:
	const WALK := 1.2
	const OUTER := 1.1
	const LANDING := 1.4
	const SLAB := 0.5
	begin(node_name)
	var prev := 0.0
	for i in levels.size():
		var y: float = levels[i]
		face_box("Walkway%d" % (i + 1), face, at, 0.0, WALK, u0, u1, y - SLAB, y, STEEL)
		face_box("LandingA%d" % (i + 1), face, at, WALK, WALK + OUTER, u0, u0 + LANDING, y - SLAB, y, STEEL)
		face_box("LandingB%d" % (i + 1), face, at, WALK, WALK + OUTER, u1 - LANDING, u1, y - SLAB, y, STEEL)
		if i > 0 or ground_stair:
			var a := face_point(face, at, WALK + OUTER * 0.5, u0 + LANDING, prev)
			var b := face_point(face, at, WALK + OUTER * 0.5, u1 - LANDING, y)
			ramp("Flight%d" % (i + 1), a, b, OUTER)
		prev = y
	if drop_ladder:
		ladder("DropLadder", face, _out(face, at, WALK + OUTER), u0 + LANDING * 0.5, 0.0, levels[0])
	if roof_ladder_to > levels[-1]:
		ladder("RoofLadder", face, at, u1 - 0.6, levels[-1], roof_ladder_to)
	end()


## The plane `n` metres out from a face at `at` (as a face coordinate).
static func _out(face: String, at: float, n: float) -> float:
	return at + n if face.ends_with("+") else at - n


## Climbable ladder or drainpipe: a thin orange strip `w` wide centred at `u`
## along a face, from y0 to y1. It is the only kind of surface the player can
## climb, so it reads as deliberate. Run it flush up to a walking surface (a
## roof, a landing) to pull up onto at the top; E at that edge climbs down onto
## it. Keep it off faces meant for wall-runs (it juts out 0.15 m).
func ladder(node_name: String, face: String, at: float, u: float, y0: float, y1: float,
		w := 0.9) -> GreyboxBlock:
	var b := face_box(node_name, face, at, 0.0, 0.15, u - w * 0.5, u + w * 0.5, y0, y1, CLIMB)
	b.collision_layer = CLIMB_LAYERS
	return b


## Grapple anchor. Place it 0.5 m above a walking surface and about 0.4 m in
## from the edge it is pulled over (see GrappleAnchor).
func anchor(node_name: String, pos: Vector3) -> GrappleAnchor:
	var a := GrappleAnchor.new()
	a.name = node_name
	a.position = pos
	_add(a)
	return a


# --- Props ---------------------------------------------------------------------

## Waist-high rooftop AC unit (vaultable).
func ac_unit(node_name: String, x: float, z: float, y: float, along_x := true) -> void:
	var hx := 1.0 if along_x else 0.6
	var hz := 0.6 if along_x else 1.0
	box(node_name, x - hx, x + hx, y, y + 1.2, z - hz, z + hz, PROP)


## Dumpster: 1.3 m tall, a step up toward ledges.
func dumpster(node_name: String, x: float, z: float, along_x := true) -> void:
	var hx := 1.0 if along_x else 0.65
	var hz := 0.65 if along_x else 1.0
	box(node_name, x - hx, x + hx, 0.0, 1.3, z - hz, z + hz, Color(0.28, 0.36, 0.3))


## Roof-access hut (stair head) with a door on one face.
func roof_hut(node_name: String, x0: float, x1: float, z0: float, z1: float, y: float,
		color: Color, door_face := "z-") -> void:
	box(node_name, x0, x1, y, y + 2.6, z0, z1, color)
	var at: float = {"x+": x1, "x-": x0, "z+": z1, "z-": z0}[door_face]
	var mid := (z0 + z1) * 0.5 if door_face.begins_with("x") else (x0 + x1) * 0.5
	face_box(node_name + "Door", door_face, at, 0.0, 0.05, mid - 0.55, mid + 0.55, y, y + 2.1, DARK)


## Parked car: body plus cabin, long axis along z unless `along_x`.
func car(node_name: String, x: float, z: float, color: Color, along_x := false) -> void:
	var hl := 2.1
	var hw := 0.9
	if along_x:
		box(node_name, x - hl, x + hl, 0.0, 0.9, z - hw, z + hw, color)
		box(node_name + "Cabin", x - 1.1, x + 1.0, 0.9, 1.5, z - 0.8, z + 0.8, color.darkened(0.25))
	else:
		box(node_name, x - hw, x + hw, 0.0, 0.9, z - hl, z + hl, color)
		box(node_name + "Cabin", x - 0.8, x + 0.8, 0.9, 1.5, z - 1.1, z + 1.0, color.darkened(0.25))


## Street lamp: a pole with a head, a bulb that glows and a light that shines
## at night.
func lamp(node_name: String, x: float, z: float) -> void:
	box(node_name, x - 0.12, x + 0.12, 0.0, 6.0, z - 0.12, z + 0.12, PROP)
	box(node_name + "Head", x - 0.35, x + 0.35, 6.0, 6.25, z - 0.35, z + 0.35, Color(0.9, 0.86, 0.7))
	night_glow(node_name + "Bulb", x - 0.25, x + 0.25, 5.9, 6.0, z - 0.25, z + 0.25, Color(1.0, 0.86, 0.6))
	night_light(node_name + "Light", Vector3(x, 5.6, z), Color(1.0, 0.84, 0.6), 2.2, 13.0)


## Water tower on legs, teal because it carries a grapple anchor on its rim
## (facing `anchor_face`), so it reads as a grapple destination from afar.
func water_tower(node_name: String, cx: float, cz: float, base: float, anchor_face := "z+") -> void:
	begin(node_name)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lx: float = cx + sx * 1.2
			var lz: float = cz + sz * 1.2
			box("Leg", lx - 0.15, lx + 0.15, base, base + 2.5, lz - 0.15, lz + 0.15, GRAPPLE)
	box("Tank", cx - 1.6, cx + 1.6, base + 2.5, base + 5.5, cz - 1.6, cz + 1.6, GRAPPLE)
	var top := base + 5.5
	var p := face_point(anchor_face, {"x+": cx + 1.6, "x-": cx - 1.6, "z+": cz + 1.6, "z-": cz - 1.6}[anchor_face],
			-0.4, cz if anchor_face.begins_with("x") else cx, top + 0.5)
	anchor("Anchor", p)
	end()


## District / street sign, always upright. It turns to the viewer unless
## `facing` (a horizontal direction) fixes it to a facade.
func sign(node_name: String, pos: Vector3, text: String, font_size := 64,
		facing := Vector3.ZERO) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	if facing == Vector3.ZERO:
		label.position = pos
	else:
		label.transform = Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), pos)
	label.text = text
	label.font_size = font_size
	label.outline_size = 16
	label.pixel_size = 0.008
	if facing == Vector3.ZERO:
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.modulate = Color(1.0, 0.97, 0.88)
	_add(label)
	return label


## Marker the debug HUD's number keys jump to (named Start1..Start5).
func start_marker(node_name: String, pos: Vector3, yaw_degrees: float) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	m.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), pos)
	_add(m)
	m.add_to_group(&"playground_start", true)
	return m


# --- Scenery (no collision) -----------------------------------------------------

## Box drawn like the greybox but with no collision: doors, trims and glow
## pieces that must never snag a player running along a facade.
func decor_box(node_name: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
		color: Color) -> MeshInstance3D:
	if _decor_material == null:
		_decor_material = ShaderMaterial.new()
		_decor_material.shader = load("res://scripts/level/greybox_grid.gdshader")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = mesh
	m.material_override = _decor_material
	m.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	_add(m)
	m.set_instance_shader_parameter(&"tint", color)
	return m


## Street door on a face (scenery): says "people use this building" without
## adding anything to trip over.
func door(node_name: String, face: String, at: float, u: float, width := 1.4, height := 2.4,
		y0 := 0.0) -> void:
	var p0 := face_point(face, at, 0.0, u - width * 0.5, y0)
	var p1 := face_point(face, at, 0.04, u + width * 0.5, y0 + height)
	decor_box(node_name, p0.x, p1.x, p0.y, p1.y, p0.z, p1.z, DARK)


# --- Rooftop kit -----------------------------------------------------------------

## Waist-high roof vent (vaultable).
func vent(node_name: String, x: float, z: float, y: float) -> void:
	box(node_name, x - 0.45, x + 0.45, y, y + 0.9, z - 0.45, z + 0.45, PROP)


## Low wall along a roof edge (0.9 m, vaultable). Only on edges no route uses:
## a parapet stops edge grabs and grapple hops over it.
func parapet(node_name: String, face: String, at: float, u0: float, u1: float, top: float) -> void:
	face_box(node_name, face, at, -0.3, 0.0, u0, u1, top, top + 0.9, ROOF.darkened(0.15))


## Railed catwalk from `a` to `b` (world points on its centre line, same
## height, along x or z), `width` wide, walking surface at a.y.
func catwalk(node_name: String, a: Vector3, b: Vector3, width := 1.4) -> void:
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var h := width * 0.5
	if along_x:
		box(node_name, minf(a.x, b.x), maxf(a.x, b.x), a.y - 0.3, a.y, a.z - h, a.z + h, STEEL)
		box(node_name + "RailA", minf(a.x, b.x), maxf(a.x, b.x), a.y, a.y + 1.0, a.z - h, a.z - h + 0.1, STEEL)
		box(node_name + "RailB", minf(a.x, b.x), maxf(a.x, b.x), a.y, a.y + 1.0, a.z + h - 0.1, a.z + h, STEEL)
	else:
		box(node_name, a.x - h, a.x + h, a.y - 0.3, a.y, minf(a.z, b.z), maxf(a.z, b.z), STEEL)
		box(node_name + "RailA", a.x - h, a.x - h + 0.1, a.y, a.y + 1.0, minf(a.z, b.z), maxf(a.z, b.z), STEEL)
		box(node_name + "RailB", a.x + h - 0.1, a.x + h, a.y, a.y + 1.0, minf(a.z, b.z), maxf(a.z, b.z), STEEL)


# --- Night -----------------------------------------------------------------------

## Light that only shines at night (DayNight switches the "night_lights"
## group on and scales it by `energy`). No shadows: cheap enough for dozens.
func night_light(node_name: String, pos: Vector3, color := Color(1.0, 0.82, 0.55), energy := 1.6,
		light_range := 11.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = node_name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	l.visible = false
	l.set_meta(&"night_energy", energy)
	_add(l)
	l.add_to_group(&"night_lights", true)
	return l


## Emissive piece (lamp bulb, beacon, lit sign) that glows at night: dark by
## day, DayNight raises the shared material's emission for the "night_glow"
## group. Scenery only.
func night_glow(node_name: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
		color: Color) -> MeshInstance3D:
	var key := color.to_html()
	if not _glow_materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.darkened(0.35)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.0
		_glow_materials[key] = mat
	var mesh := BoxMesh.new()
	mesh.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = mesh
	m.material_override = _glow_materials[key]
	m.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	_add(m)
	m.add_to_group(&"night_glow", true)
	return m


# --- Facade windows ----------------------------------------------------------------

## Remembers a building mass (or a backdrop block) for dress_windows().
## `faces` limits which faces get windows (all four by default).
func register_facade(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float,
		faces: Array = ["x-", "x+", "z-", "z+"], spacing := 2.8) -> void:
	_facades.append({x0 = x0, x1 = x1, z0 = z0, z1 = z1, y0 = y0, y1 = y1, faces = faces, spacing = spacing})


## Glass windows on every registered facade (scenery, no collision): rows per
## storey, skipping any spot with something in front of the wall (fire
## escapes, awnings, ladders, run panels, doors, neighbours). About a third
## light up at night (DayNight drives the "city_lit_windows" material).
## Call once, after everything else is built.
func dress_windows() -> void:
	var boxes: Array[AABB] = []
	for n in root.find_children("*", "GreyboxBlock", true, false):
		var b := n as GreyboxBlock
		boxes.append(_to_root(b) * AABB(-b.size * 0.5, b.size))
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh is BoxMesh:
			var s: Vector3 = (m.mesh as BoxMesh).size
			boxes.append(_to_root(m) * AABB(-s * 0.5, s))
	# Real openings (dive windows) sit in the wall plane: keep glass off them.
	for n in root.find_children("*", "TraversalWindow", true, false):
		var w := n as TraversalWindow
		var half := Vector3(w.opening_width * 0.5 + 0.4, 0.0, w.wall_thickness * 0.5 + 1.0)
		boxes.append(_to_root(w) * AABB(Vector3(-half.x, -0.4, -half.z), Vector3(half.x * 2.0, w.opening_height + 0.8, half.z * 2.0)))
	var lit := PackedFloat32Array()
	var dark := PackedFloat32Array()
	for f: Dictionary in _facades:
		var mass := AABB(Vector3(f.x0, f.y0, f.z0), Vector3(f.x1 - f.x0, f.y1 - f.y0, f.z1 - f.z0))
		var near: Array[AABB] = []
		for bx in boxes:
			if bx.grow(1.0).intersects(mass) and not mass.grow(0.01).encloses(bx):
				near.append(bx)
		for face: String in f.faces:
			var along_x := face.begins_with("z")
			var u0: float = f.x0 if along_x else f.z0
			var u1: float = f.x1 if along_x else f.z1
			var at: float = {"x-": f.x0, "x+": f.x1, "z-": f.z0, "z+": f.z1}[face]
			var spacing: float = f.spacing
			var count := int((u1 - u0 - 1.6) / spacing)
			if count < 1:
				continue
			var start: float = (u0 + u1) * 0.5 - (count - 1) * spacing * 0.5
			var y: float = f.y0 + 1.0
			while y + 1.7 <= f.y1 - 0.4:
				for i in count:
					var u: float = start + i * spacing
					var a := face_point(face, at, 0.02, u - 0.75, y - 0.1)
					var b := face_point(face, at, 0.7, u + 0.75, y + 1.8)
					var front := AABB(Vector3(minf(a.x, b.x), a.y, minf(a.z, b.z)),
							Vector3(absf(b.x - a.x), b.y - a.y, absf(b.z - a.z)))
					if near.any(func(bx: AABB) -> bool: return bx.intersects(front)):
						continue
					var c := face_point(face, at, 0.02, u, y + 0.85)
					var entry := PackedFloat32Array([c.x, c.y, c.z, 0.0 if along_x else 1.0])
					if hash(Vector3i(roundi(c.x * 4.0), roundi(c.y * 4.0), roundi(c.z * 4.0))) % 100 < 34:
						lit.append_array(entry)
					else:
						dark.append_array(entry)
				y += STOREY
	begin("FacadeWindows")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.11, 0.14, 0.19)
	glass.roughness = 0.25
	glass.metallic = 0.35
	var lit_glass := glass.duplicate() as StandardMaterial3D
	lit_glass.emission_enabled = true
	lit_glass.emission = Color(1.0, 0.7, 0.38)
	lit_glass.emission_energy_multiplier = 0.0
	_window_set("Dark", dark, glass)
	var lit_node := _window_set("Lit", lit, lit_glass)
	lit_node.add_to_group(&"city_lit_windows", true)
	end()
	print("facade windows: %d (%d lit at night)" % [floori((lit.size() + dark.size()) / 4.0), floori(lit.size() / 4.0)])


func _window_set(node_name: String, windows: PackedFloat32Array, material: Material) -> FacadeWindows:
	var node := FacadeWindows.new()
	node.name = node_name
	node.windows = windows
	node.material_override = material
	_add(node)
	return node


func _to_root(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
