extends RefCounted
## Static audit of the city as one traversal network.
##
## Collects every elevated walkable surface (tops of axis-aligned greybox
## blocks a body can stand on) and links them with the moves the player
## really has, using the player's own ParkourSensor and Grapple queries:
##   walk     - same height, touching
##   stairs   - a ramp / fire-escape flight from one to the other
##   ladder   - a climbable surface from one to the other (both ways)
##   grab     - jump from below and grab the edge (the real ledge probe)
##   jump     - a running jump across a gap (level, up a little, or down)
##   window   - E through a dive window
##   grapple  - an anchor in range and line of sight from a standing spot
## Wall-runs and wall-jumps are NOT modelled, so anything reachable here is
## reachable without them. The street (y = 0) is the start.
##
## Used by tests/city_test.gd (test_traversal_network) and, for a printed
## report, tools/city/audit_city.gd.

const STREET := -1

## Jump model (sprint 9.5 m/s, a held jump rises 1.35 m in 0.32 s, falls at
## 41.6 m/s^2), with a safety margin. Up to this far across for a grab onto a
## higher edge.
const RUN_SPEED := 9.5
const JUMP_UP_GAP := 3.0
const MARGIN := 1.0

class Surface:
	var index: int
	var path: String
	var district: String
	var rect: Rect2
	var top: float
	var bottom: float
	var important: bool
	var in_kinds := {}
	var out_to := {} # index -> kind (elevated destinations only)
	var reachable := false


var surfaces: Array[Surface] = []
## Adjacency: from index (or STREET) -> Array of [to index, kind].
var edges := {}
var anchor_sources := {} # anchor path -> number of surfaces (+ street) it's usable from

var _city: Node3D
var _space: PhysicsDirectSpaceState3D
var _sensor: ParkourSensor
var _grapple: Grapple
var _ramps: Array[GreyboxBlock] = []
var _ladders: Array[GreyboxBlock] = []


func _init(city: Node3D, sensor: ParkourSensor, grapple: Grapple) -> void:
	_city = city
	_sensor = sensor
	_grapple = grapple
	_space = city.get_world_3d().direct_space_state


func run() -> void:
	_collect()
	_link_walk_jump_grab()
	_link_ramps()
	_link_ladders()
	_link_windows()
	_link_grapples()
	_flood()


## Important surfaces not reachable from the street.
func unreachable() -> Array[Surface]:
	var out: Array[Surface] = []
	for s in surfaces:
		if s.important and not s.reachable:
			out.append(s)
	return out


## Important, reachable surfaces with nowhere to go but back down to the street.
func dead_ends() -> Array[Surface]:
	var out: Array[Surface] = []
	for s in surfaces:
		if s.important and s.reachable and s.out_to.is_empty():
			out.append(s)
	return out


## In and out edges of the surface whose path ends with `suffix` (debugging).
func why(suffix: String) -> String:
	var lines := PackedStringArray()
	for s in surfaces:
		if not s.path.ends_with(suffix):
			continue
		lines.append("%s  top %.2f rect %s reachable %s" % [s.path, s.top, s.rect, s.reachable])
		for from: int in edges:
			for e: Array in edges[from]:
				if e[0] == s.index:
					lines.append("  <- %s (%s)" % ["STREET" if from == STREET else surfaces[from].path, e[1]])
		for to: int in s.out_to:
			lines.append("  -> %s (%s)" % [surfaces[to].path, s.out_to[to]])
	return "
".join(lines)


func report() -> String:
	var lines := PackedStringArray()
	var by_district := {}
	for s in surfaces:
		if s.important:
			by_district.get_or_add(s.district, []).append(s)
	for d: String in by_district:
		var list: Array = by_district[d]
		var reach := list.filter(func(s: Surface) -> bool: return s.reachable).size()
		lines.append("%s: %d/%d surfaces reachable from the street" % [d, reach, list.size()])
		for s: Surface in list:
			var kinds := ", ".join(s.in_kinds.keys())
			var flag := "" if s.reachable else "  <-- UNREACHABLE"
			if s.reachable and s.out_to.is_empty():
				flag = "  <-- dead end (only back down)"
			lines.append("    %-58s %5.1f m  in: %s  out: %d%s" % [s.path.trim_prefix(d + "/"), s.top, kinds, s.out_to.size(), flag])
	return "\n".join(lines)


# --- Surfaces ----------------------------------------------------------------

func _collect() -> void:
	for node in _city.find_children("*", "GreyboxBlock", true, false):
		var b := node as GreyboxBlock
		var path := String(_city.get_path_to(b))
		if path.begins_with("Backdrop") or path.begins_with("Streets"):
			continue
		if (b.collision_layer & 4) != 0:
			_ladders.append(b)
			continue
		if not b.global_basis.is_equal_approx(Basis()):
			_ramps.append(b)
			continue
		var top := b.global_position.y + b.size.y * 0.5
		if top < 2.4 or b.size.x < 0.55 or b.size.z < 0.55 or b.size.x * b.size.z < 2.0:
			continue
		var r := Rect2(b.global_position.x - b.size.x * 0.5, b.global_position.z - b.size.z * 0.5, b.size.x, b.size.z)
		if not _standable(r, top):
			continue
		var s := Surface.new()
		s.index = surfaces.size()
		s.path = path
		s.district = path.get_slice("/", 0)
		s.rect = r
		s.top = top
		s.bottom = b.global_position.y - b.size.y * 0.5
		s.important = _is_important(path, r)
		surfaces.append(s)


static func _is_important(path: String, r: Rect2) -> bool:
	var leaf := path.get_file()
	for minor in ["Hut", "AC", "Tank", "Planter", "Crates", "Skylight", "Column", "Leg", "Sign", "Hook",
			"Counterweight", "Container", "Kiosk", "Tree", "Car", "Cabin", "Pallets", "Forklift", "Dumpster",
			"Vent", "Pipe", "Plant", "Parapet", "Fountain", "Bench", "Statue", "Lamp", "Mast", "Beacon", "Rail",
			"Penthouse", "Helipad", "Jib", "Pile", "Office", "Van", "Shed", "Hoarding", "Workbench", "Lockers", "Table"]:
		if leaf.contains(minor):
			return false
	return r.size.x * r.size.y >= 4.0


func _standable(r: Rect2, top: float) -> bool:
	for p in _samples(r, 1.5, 0.35):
		if _sensor.has_clearance(Vector3(p.x, top, p.y), 1.7, 0.3):
			return true
	return false


## Up to ~30 points spread over `r` (inset), `step` apart.
static func _samples(r: Rect2, step: float, inset: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x0 := r.position.x + inset
	var x1 := r.end.x - inset
	var z0 := r.position.y + inset
	var z1 := r.end.y - inset
	if x1 < x0:
		x0 = r.get_center().x
		x1 = x0
	if z1 < z0:
		z0 = r.get_center().y
		z1 = z0
	var nx := maxi(int((x1 - x0) / step) + 1, 1)
	var nz := maxi(int((z1 - z0) / step) + 1, 1)
	var sx := maxi(1, int(ceil(nx / 6.0)))
	var sz := maxi(1, int(ceil(nz / 6.0)))
	for i in range(0, nx, sx):
		for j in range(0, nz, sz):
			var fx := 0.5 if nx == 1 else i / float(nx - 1)
			var fz := 0.5 if nz == 1 else j / float(nz - 1)
			out.append(Vector2(x0 + (x1 - x0) * fx, z0 + (z1 - z0) * fz))
	return out


# --- Edges -------------------------------------------------------------------

func _add_edge(from: int, to: int, kind: String) -> void:
	if from == to:
		return
	edges.get_or_add(from, []).append([to, kind])
	surfaces[to].in_kinds[kind] = true
	if from != STREET:
		surfaces[from].out_to[to] = kind


func _link_walk_jump_grab() -> void:
	for a in surfaces:
		for b in surfaces:
			if a == b:
				continue
			var gap := _rect_gap(a.rect, b.rect)
			var dy := b.top - a.top
			if absf(dy) < 0.06 and gap < 0.35:
				if _clear_hop(a, b):
					_add_edge(a.index, b.index, "walk")
			elif dy < -0.06 and gap < 0.35:
				if _clear_hop(a, b):
					_add_edge(a.index, b.index, "drop")
			elif dy <= 0.2 and gap <= _jump_reach(dy):
				if _has_runway(a, b) and _clear_hop(a, b):
					_add_edge(a.index, b.index, "jump")
			elif dy > 0.2 and dy <= 3.75 and gap <= JUMP_UP_GAP and _can_grab(a.top, a.rect, b, gap):
				_add_edge(a.index, b.index, "grab" if gap < 1.2 else "jump")
	# From the street: jump and grab any edge in reach with open ground below it.
	for b in surfaces:
		if b.top <= 3.75 and _can_grab(0.0, Rect2(), b, 0.0):
			_add_edge(STREET, b.index, "grab")


## Nearest points of `a` and `b` (xz), each pulled `inset` into its own rect.
static func _facing_points(a: Rect2, b: Rect2, inset: float) -> Array[Vector2]:
	var cb := b.get_center()
	var pa := Vector2(clampf(cb.x, a.position.x + inset, maxf(a.end.x - inset, a.position.x + inset)),
			clampf(cb.y, a.position.y + inset, maxf(a.end.y - inset, a.position.y + inset)))
	var pb := Vector2(clampf(pa.x, b.position.x + inset, maxf(b.end.x - inset, b.position.x + inset)),
			clampf(pa.y, b.position.y + inset, maxf(b.end.y - inset, b.position.y + inset)))
	pa = Vector2(clampf(pb.x, a.position.x + inset, maxf(a.end.x - inset, a.position.x + inset)),
			clampf(pb.y, a.position.y + inset, maxf(a.end.y - inset, a.position.y + inset)))
	return [pa, pb]


## A walk, drop or jump from `a` to `b` has head room where it lands and
## nothing (a wall, a roof) in the way of the body on the way.
func _clear_hop(a: Surface, b: Surface) -> bool:
	var pts := _facing_points(a.rect, b.rect, 0.35)
	var land := Vector3(pts[1].x, b.top, pts[1].y)
	if not _sensor.has_clearance(land + Vector3.UP * 0.05, 1.7, 0.3):
		return false
	var from := Vector3(pts[0].x, a.top + 1.2, pts[0].y)
	var to := land + Vector3.UP * 1.2
	if a.top > b.top:
		to.y = maxf(to.y, a.top + 0.6) # dropping: over whatever lip, then down
	return _ray(from, to).is_empty() and _ray(to, land + Vector3.UP * 0.3).is_empty()


## Longest running jump across a gap to a surface `dy` higher (dy <= 0.2).
static func _jump_reach(dy: float) -> float:
	var fall := sqrt(maxf(2.0 * (1.35 - dy), 0.0) / 41.6)
	return minf(RUN_SPEED * (0.32 + fall) - MARGIN, 6.5)


## A little room on `a` to run at `b` (the side facing it is at least 2 m long).
func _has_runway(a: Surface, _b: Surface) -> bool:
	return a.rect.size.x >= 2.0 or a.rect.size.y >= 2.0


## True if a body at `from_top` next to `b` - standing on `from_rect`, on open
## street when from_rect is empty, or in the air over a gap up to `gap` wide
## from it - can jump and grab b's edge, checked with the real ledge probe at a
## few points along b's edges.
func _can_grab(from_top: float, from_rect: Rect2, b: Surface, gap: float) -> bool:
	for side in 4:
		for f in [0.2, 0.5, 0.8]:
			var edge: Vector2
			var out: Vector2
			match side:
				0:
					edge = Vector2(b.rect.position.x, b.rect.position.y + b.rect.size.y * f)
					out = Vector2.LEFT
				1:
					edge = Vector2(b.rect.end.x, b.rect.position.y + b.rect.size.y * f)
					out = Vector2.RIGHT
				2:
					edge = Vector2(b.rect.position.x + b.rect.size.x * f, b.rect.position.y)
					out = Vector2.UP
				_:
					edge = Vector2(b.rect.position.x + b.rect.size.x * f, b.rect.end.y)
					out = Vector2.DOWN
			var stand := edge + out * 0.75
			var feet := Vector3(stand.x, from_top, stand.y)
			if from_rect.size != Vector2.ZERO and not from_rect.grow(0.05).has_point(stand):
				# In the air over the gap: must be within a jump of from_rect, with a
				# clear line from its edge.
				if _point_gap(from_rect, stand) > gap + 0.05 or gap < 1.2:
					continue
				var launch := _facing_points(from_rect, Rect2(stand, Vector2.ZERO), 0.3)[0]
				if not _ray(Vector3(launch.x, from_top + 1.2, launch.y), feet + Vector3.UP * 1.2).is_empty():
					continue
			elif not _sensor.has_clearance(feet + Vector3.UP * 0.05, 1.7, 0.3):
				continue
			for lift: float in [1.15, 1.35]:
				var ledge := _sensor.detect_ledge(feet + Vector3.UP * lift, Vector3(-out.x, 0.0, -out.y))
				if ledge != null and absf(ledge.top_y - b.top) < 0.12:
					return true
	return false


func _link_ramps() -> void:
	for ramp in _ramps:
		var fwd := ramp.global_basis.z.normalized()
		var up := ramp.global_basis.y.normalized()
		var p := ramp.global_position + up * ramp.size.y * 0.5
		var a := p + fwd * (ramp.size.z * 0.5 - 0.05)
		var b := p - fwd * (ramp.size.z * 0.5 - 0.05)
		var lo := a if a.y < b.y else b
		var hi := b if a.y < b.y else a
		var from := _surface_at(lo, 0.7)
		var to := _surface_at(hi, 0.7)
		if to == STREET or from == to:
			continue
		_add_edge(from, to, "stairs")
		if from != STREET:
			_add_edge(to, from, "stairs")


func _link_ladders() -> void:
	for l in _ladders:
		var top := l.global_position.y + l.size.y * 0.5
		var bottom := l.global_position.y - l.size.y * 0.5
		var c := l.global_position
		var hi := _surface_near(Vector3(c.x, top, c.z), l, 0.9)
		var lo := _surface_near(Vector3(c.x, bottom, c.z), l, 1.2)
		if hi == STREET or hi == lo:
			continue
		_add_edge(lo, hi, "ladder")
		if lo != STREET:
			_add_edge(hi, lo, "ladder")


func _link_windows() -> void:
	for node in _city.find_children("*", "TraversalWindow", true, false):
		var w := node as TraversalWindow
		for side: float in [1.0, -1.0]:
			# Where the player can stand to press E (within reach, lined up).
			var sources := {}
			for d: float in [0.8, 1.6, 2.6]:
				var p := w.to_global(Vector3(0.0, 0.3, side * d))
				var floor_hit := _ray(p, p + Vector3.DOWN * 1.8)
				if floor_hit.is_empty():
					continue
				var feet: Vector3 = floor_hit.position
				if not w.feet_in_reach(feet):
					continue
				sources[_surface_at(feet, 0.4)] = true
			# Or jump at it from a surface about sill height across a gap and press
			# E in the air (the light-well dive), with a clear line to the opening.
			var front := w.to_global(Vector3(0.0, 0.0, side * 1.0))
			for a in surfaces:
				if absf(a.top - w.global_position.y) > 1.2:
					continue
				var near := _facing_points(a.rect, Rect2(Vector2(front.x, front.z), Vector2.ZERO), 0.3)[0]
				var launch := Vector3(near.x, a.top + 1.0, near.y)
				if launch.distance_to(front + Vector3.UP * 0.6) > 4.5 or w.side_of(launch) != side:
					continue
				if w.through_direction(launch).dot((front - launch).normalized() * Vector3(1, 0, 1)) < 0.7:
					continue
				if _ray(launch, front + Vector3.UP * 0.6).is_empty():
					sources[a.index] = true
			if sources.is_empty():
				continue
			# Where the dive ends: the floor beyond, or whatever is below it.
			var land := w.to_global(Vector3(0.0, 0.5, -side * w.landing_distance))
			var hit := _ray(land, land + Vector3.DOWN * 40.0)
			var dest := STREET if hit.is_empty() else _surface_at(hit.position, 0.6)
			for s: int in sources:
				if dest != STREET:
					_add_edge(s, dest, "window")


func _link_grapples() -> void:
	for node in _city.find_children("*", "Node3D", true, false):
		var anchor := node as GrappleAnchor
		if anchor == null:
			continue
		var a := anchor.global_position
		var landing := -2
		for s in surfaces:
			if absf(s.top - (a.y - 0.5)) < 0.15 and s.rect.grow(1.0).has_point(Vector2(a.x, a.z)):
				landing = s.index
				break
		var path := String(_city.get_path_to(anchor))
		if landing == -2:
			anchor_sources[path] = -1 # lands on nothing we know
			continue
		var count := 0
		for s in surfaces:
			if s.index == landing or s.rect.get_center().distance_to(Vector2(a.x, a.z)) > _grapple.max_range + 20.0:
				continue
			if _grapple_from(s.rect, s.top, a):
				_add_edge(s.index, landing, "grapple")
				count += 1
		# From the street: a coarse ring of spots around the anchor.
		for r: float in [8.0, 14.0, 20.0, 26.0]:
			for i in 12:
				var ang := TAU * i / 12.0
				var p := Vector3(a.x + cos(ang) * r, 0.05, a.z + sin(ang) * r)
				if _street_spot(p) and _grapple_ok(p + Vector3.UP * 1.2, a):
					_add_edge(STREET, landing, "grapple")
					count += 1
					break
			if edges.has(STREET) and edges[STREET].any(func(e: Array) -> bool: return e[0] == landing and e[1] == "grapple"):
				break
		anchor_sources[path] = count


func _grapple_from(r: Rect2, top: float, a: Vector3) -> bool:
	for p in _samples(r, 2.0, 0.45):
		var feet := Vector3(p.x, top, p.y)
		if not _sensor.has_clearance(feet + Vector3.UP * 0.05, 1.7, 0.3):
			continue
		if _grapple_ok(feet + Vector3.UP * 1.2, a):
			return true
	return false


func _grapple_ok(chest: Vector3, a: Vector3) -> bool:
	var d := chest.distance_to(a)
	return d <= _grapple.max_range and d >= _grapple.min_range and _grapple.has_line_of_sight(chest, a)


func _street_spot(p: Vector3) -> bool:
	var hit := _ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.5)
	return not hit.is_empty() and (hit.position as Vector3).y < 0.1 and _sensor.has_clearance(p, 1.7, 0.3)


func _flood() -> void:
	var queue: Array[int] = [STREET]
	var seen := {STREET: true}
	while not queue.is_empty():
		var i: int = queue.pop_back()
		if i != STREET:
			surfaces[i].reachable = true
		for e: Array in edges.get(i, []):
			if not seen.has(e[0]):
				seen[e[0]] = true
				queue.append(e[0])


# --- Helpers -----------------------------------------------------------------

## Surface whose top is at p.y (within 0.15) and whose rect is within `reach`
## of p; STREET if p is at street level and nothing else fits.
func _surface_at(p: Vector3, reach: float) -> int:
	var best := STREET
	var best_d := INF
	for s in surfaces:
		if absf(s.top - p.y) > 0.15:
			continue
		var d := _point_gap(s.rect, Vector2(p.x, p.z))
		if d <= reach and d < best_d:
			best = s.index
			best_d = d
	return best


## Like _surface_at, measured from the edge of block `l` (a ladder).
func _surface_near(p: Vector3, l: GreyboxBlock, reach: float) -> int:
	var lr := Rect2(l.global_position.x - l.size.x * 0.5, l.global_position.z - l.size.z * 0.5, l.size.x, l.size.z)
	var best := STREET
	var best_d := INF
	for s in surfaces:
		if absf(s.top - p.y) > 0.12:
			continue
		var d := _rect_gap(s.rect, lr)
		if d <= reach and d < best_d:
			best = s.index
			best_d = d
	return best


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


static func _point_gap(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()


static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, 0.0), b.position.x - a.end.x)
	var dz := maxf(maxf(a.position.y - b.end.y, 0.0), b.position.y - a.end.y)
	return Vector2(dx, dz).length()
