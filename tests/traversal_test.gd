extends SceneTree
## Deterministic traversal checks in a bare lab built in code (tools/city's
## kit, so ladders and windows are made exactly as in the city): wall-jump
## reach across measured gaps and heights, wall-jump -> rooftop and -> grapple,
## climbing (grab, up, down, sideways, off, top, bottom, from above), and the
## window regressions. Everything goes through the Input system like
## movement_test.gd, with the real player scene.
##
## Run headless:
##   godot --headless --path . -s res://tests/traversal_test.gd

const Kit := preload("res://tools/city/city_kit.gd")

const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"sprint", &"jump", &"crouch", &"traverse", &"grapple", &"bullet_time"]
const KEY_FOR := {&"move_forward": KEY_W, &"move_left": KEY_A, &"move_back": KEY_S,
		&"move_right": KEY_D, &"jump": KEY_SPACE, &"traverse": KEY_E, &"bullet_time": KEY_F,
		&"crouch": KEY_C}
const MOUSE_FOR := {&"grapple": MOUSE_BUTTON_RIGHT}

var player: Player
var settings: MovementSettings
var lab: Node3D
var kit: Kit
## Pieces rebuilt per case (alley walls, rooftops).
var temp: Node3D
var passed := 0
var failed := 0


func _initialize() -> void:
	lab = Node3D.new()
	lab.name = "Lab"
	root.add_child(lab)
	kit = Kit.new(lab)
	kit.box("Ground", -200.0, 200.0, -1.0, 0.0, -200.0, 200.0, Kit.PAVEMENT)
	_build_climb_lab()
	_build_window_lab()
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	settings = player.settings
	_run.call_deferred()


func _run() -> void:
	await _phys(20)
	await test_wall_to_wall()
	await test_wall_chain()
	await test_wall_jump_carry()
	await test_wall_jump_rooftop()
	await test_wall_jump_grapple()
	await test_edge_jump_beside_wall()
	await test_climb()
	await test_climb_down_from_above()
	await test_climb_no_accidents()
	await test_window_bottom()
	print("\n==== %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)


# --- Wall-jump ---------------------------------------------------------------

## Wall A (face x = 0, runnable along -Z) and wall B across a `width` m clear
## gap, both 14 m tall, 60 m long; runway from z = 12.
func _alley(width: float) -> void:
	_clear_temp()
	_temp_box(-1.0, 0.0, 0.0, 14.0, -60.0, 0.0)
	_temp_box(width, width + 1.0, 0.0, 14.0, -60.0, 0.0)
	await _phys(2)


## Sprint along wall A, jump into a wall-run, wall-jump after `ticks`, then
## steer: "forward" (keep holding W), "diag" (W + toward wall B) or "toward"
## (only toward B). `tap` = Space released straight away (a quick press).
## Returns {ok (a wall-run on B), height gained, speeds}.
func _wall_to_wall(style: String, tap: bool, ticks := 10) -> Dictionary:
	var out := {ok = false, ran = false, jumped = false, dy = 0.0, max_speed = 0.0, jump_speed = 0.0}
	await _place(Vector3(0.6, 0.05, 12.0), 0.0)
	var runs := []
	var on_run := func(n: Vector3) -> void: runs.append([n, player.global_position.y])
	player.wall_run_started.connect(on_run)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 1.0, 3.0)
	Input.action_press(&"jump")
	out.ran = await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(ticks)
	var jump_y := player.global_position.y
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state != Player.State.WALL_RUN, 0.3)
	out.jumped = player.last_action == &"wall_jump"
	out.jump_speed = player.horizontal_speed()
	if tap:
		await _phys(1)
		Input.action_release(&"jump")
	match style:
		"diag":
			Input.action_press(&"move_right")
		"toward":
			Input.action_release(&"move_forward")
			Input.action_press(&"move_right")
	var frames := 0
	while frames < 90 and runs.size() < 2 and not player.is_on_floor():
		out.max_speed = maxf(out.max_speed, player.horizontal_speed())
		frames += 1
		await physics_frame
	_release_all()
	player.wall_run_started.disconnect(on_run)
	out.ok = out.ran and out.jumped and runs.size() >= 2 and (runs[1][0] as Vector3).dot(Vector3.LEFT) > 0.9
	if out.ok:
		out.dy = runs[1][1] - jump_y
	return out


func test_wall_to_wall() -> void:
	_section("Wall-run -> wall-jump -> opposite wall (usable range)")
	var table := []
	for width: float in [2.0, 2.8, 3.5, 4.0, 5.0]:
		await _alley(width)
		for style: Array in [["forward", true], ["diag", true], ["forward", false], ["diag", false]]:
			var r := await _wall_to_wall(style[0], style[1])
			table.append([width, "%s-%s" % [style[0], "tap" if style[1] else "hold"], r.ok, r.dy])
	for row: Array in table:
		print("    %.1f m  %-12s %s" % [row[0], row[1], ("reaches wall B, %+.1f m" % row[3]) if row[2] else "falls short"])
	var ok_at := func(width: float, style: String) -> bool:
		return table.any(func(r: Array) -> bool: return is_equal_approx(r[0], width) and r[1] == style and r[2])
	_check("2.8 m alley (Needle Alley): a quick tap of Space while holding W reaches the other wall",
			ok_at.call(2.8, "forward-tap"))
	var all_ok := true
	for width: float in [2.0, 2.8, 3.5]:
		for style in ["forward-tap", "diag-tap", "forward-hold", "diag-hold"]:
			all_ok = all_ok and ok_at.call(width, style)
	_check("2 - 3.5 m clear: every input style works (tap or hold, W or W + toward)", all_ok)
	_check("4 m clear: W + toward the wall with Space held still works", ok_at.call(4.0, "diag-hold"))
	var none_5 := not table.any(func(r: Array) -> bool: return is_equal_approx(r[0], 5.0) and r[2])
	_check("5 m clear: out of reach for every style (no flying across the map)", none_5)
	var toward := await _wall_to_wall("toward", true)
	_check("steering only toward the other wall (not along it) doesn't start a run on it", not toward.ok)


## Wall-run -> wall-jump -> wall-run -> ... up a 2.8 m alley: every jump
## rises a normal jump's height, so a chain climbs, but only while the alley
## lasts (each wall-run keeps the pace along it, it never adds any).
func test_wall_chain() -> void:
	_section("Wall-jump chain up an alley (vertical)")
	await _alley(2.8)
	await _place(Vector3(0.6, 0.05, 12.0), 0.0)
	var runs := []
	var on_run := func(n: Vector3) -> void: runs.append([n, player.global_position.y, player.horizontal_speed()])
	player.wall_run_started.connect(on_run)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 1.0, 3.0)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	var peak := 0.0
	for i in 16:
		if player.state != Player.State.WALL_RUN:
			break
		await _phys(4)
		var toward := &"move_right" if player.wall_normal.x > 0.0 else &"move_left"
		Input.action_release(&"move_left" if toward == &"move_right" else &"move_right")
		await _tap(&"jump")
		Input.action_press(toward)
		var next := func() -> bool: return player.state == Player.State.WALL_RUN or player.is_on_floor()
		await _wait_until(next, 1.0)
		peak = maxf(peak, player.global_position.y)
	_release_all()
	player.wall_run_started.disconnect(on_run)
	var alternating := true
	for i in range(1, runs.size()):
		alternating = alternating and (runs[i][0] as Vector3).dot(runs[i - 1][0]) < -0.9
	var fastest := 0.0
	for r: Array in runs:
		fastest = maxf(fastest, r[2])
	print("    %d runs, starting at %s m" % [runs.size(), str(runs.map(func(r: Array) -> float: return snappedf(r[1], 0.1)))])
	_check("alternating wall-runs chain up a 2.8 m alley (4+ runs, gaining height)", runs.size() >= 4 and alternating
			and runs[3][1] > runs[0][1] + 2.0, "%d runs, peak %.1f m" % [runs.size(), peak])
	_check("the chain never adds speed along the alley", fastest <= settings.sprint_speed + 3.0 + 0.01,
			"fastest %.2f m/s at a run start" % fastest)
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)


func test_wall_jump_carry() -> void:
	_section("Wall-jump carry: consistent arc, no added speed, steering kept")
	await _alley(8.0)
	# Tap vs hold: the same full-height arc.
	var peaks := []
	for tap: bool in [true, false]:
		await _place(Vector3(0.6, 0.05, 12.0), 0.0)
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		await _wait_until(func() -> bool: return player.global_position.z < 1.0, 3.0)
		Input.action_press(&"jump")
		await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
		Input.action_release(&"jump")
		await _phys(10)
		Input.action_press(&"jump")
		await _wait_until(func() -> bool: return player.state != Player.State.WALL_RUN, 0.3)
		var y0 := player.global_position.y
		var speed0 := player.horizontal_speed()
		if tap:
			await _phys(1)
			Input.action_release(&"jump")
		var peak := y0
		var fastest := 0.0
		while player.velocity.y > 0.0 and not player.is_on_floor():
			peak = maxf(peak, player.global_position.y)
			fastest = maxf(fastest, player.horizontal_speed())
			await physics_frame
		peaks.append(peak - y0)
		_check("wall-jump (%s, holding W): no speed added during the carry" % ("tap" if tap else "hold"),
				fastest <= speed0 + 0.01, "%.2f -> max %.2f m/s" % [speed0, fastest])
		_release_all()
		await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	_check("tap and hold give the same arc (a normal jump's full height)", absf(peaks[0] - peaks[1]) < 0.05
			and absf(peaks[0] - settings.jump_height) < 0.08, "tap %.2f m, hold %.2f m" % [peaks[0], peaks[1]])
	# Steering straight back at the wall is ordinary air control.
	await _place(Vector3(0.6, 0.05, 12.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 1.0, 3.0)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(10)
	await _tap(&"jump")
	var away0 := player.velocity.x
	Input.action_release(&"move_forward")
	Input.action_press(&"move_left")
	await _phys(6)
	_check("steering back toward the wall during the carry slows the push as normal", away0 - player.velocity.x > 1.0,
			"%.2f -> %.2f m/s" % [away0, player.velocity.x])
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)


## Wall A plus a rooftop across a `gap` m gap whose top is `height` m up.
func _rooftop(gap: float, height: float) -> void:
	_clear_temp()
	_temp_box(-1.0, 0.0, 0.0, 14.0, -60.0, 0.0)
	_temp_box(gap, gap + 10.0, 0.0, height, -40.0, 0.0)
	await _phys(2)


## Wall-run A, wall-jump after `ticks`, steer W + toward the roof, grab or
## land, climb up. Returns the final feet height (or -1 if never on a roof).
func _wall_jump_to_roof(ticks: int, toward_only: bool) -> float:
	await _place(Vector3(0.6, 0.05, 12.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 1.0, 3.0)
	Input.action_press(&"jump")
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(ticks)
	await _tap(&"jump")
	if toward_only:
		Input.action_release(&"move_forward")
	Input.action_press(&"move_right")
	var hang_or_land := func() -> bool:
		return player.state == Player.State.LEDGE_HANG or (player.is_on_floor() and player.state == Player.State.MOVE)
	await _wait_until(hang_or_land, 2.0)
	if player.state == Player.State.LEDGE_HANG:
		_release_all()
		await _phys(4)
		await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
	_release_all()
	await _phys(5)
	return player.global_position.y if ran else -1.0


func test_wall_jump_rooftop() -> void:
	_section("Wall-run -> wall-jump -> rooftop (gap x height)")
	var reached := {}
	for gap: float in [2.0, 3.0, 4.0]:
		for height: float in [3.5, 4.5, 5.5, 6.5]:
			await _rooftop(gap, height)
			var best := -1.0
			for ticks in [4, 12]:
				for toward_only: bool in [false, true]:
					var y := await _wall_jump_to_roof(ticks, toward_only)
					if absf(y - height) < 0.1:
						best = y
			reached[Vector2(gap, height)] = best > 0.0
			print("    gap %.1f m, roof %.1f m: %s" % [gap, height, "reached" if best > 0.0 else "out of reach"])
	var all_45 := true
	for gap: float in [2.0, 3.0, 4.0]:
		all_45 = all_45 and reached[Vector2(gap, 3.5)] and reached[Vector2(gap, 4.5)]
	_check("2 - 4 m gaps: roofs up to 4.5 m reachable (a standing jump-and-grab tops out at 3.7 m)", all_45)
	var none_55 := true
	for gap: float in [2.0, 3.0, 4.0]:
		none_55 = none_55 and not reached[Vector2(gap, 5.5)] and not reached[Vector2(gap, 6.5)]
	_check("5.5 m+ roofs stay out of reach from a ground-level wall-run (chain up an alley or grapple)", none_55)


func test_wall_jump_grapple() -> void:
	_section("Wall-run -> wall-jump -> grapple")
	_clear_temp()
	_temp_box(-1.0, 0.0, 0.0, 14.0, -60.0, 0.0)
	_temp_box(6.0, 18.0, 0.0, 12.0, -40.0, -20.0)
	var anchor := GrappleAnchor.new()
	anchor.position = Vector3(12.0, 12.5, -20.4)
	temp.add_child(anchor)
	await _phys(2)
	await _place(Vector3(0.6, 0.05, 12.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 1.0, 3.0)
	Input.action_press(&"jump")
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(10)
	await _tap(&"jump")
	var jumped := player.last_action == &"wall_jump"
	await _phys(6)
	var r := await _grapple_to(anchor)
	_check("wall-jump, then grapple from the air to a 12 m roof no jump reaches", ran and jumped and r.seen and r.arrived
			and absf(r.landed.y - 12.0) < 0.1, "%s" % r)


## Sprinting along a wall on a deck, off its end, Space pressed a moment
## later (coyote time): that press is a jump, and the wall-run starts on the
## way up - never an instant wall-jump from the edge.
func test_edge_jump_beside_wall() -> void:
	_section("Space just off an edge beside a runnable wall")
	_clear_temp()
	_temp_box(-1.0, 0.0, 0.0, 14.0, -60.0, 0.0)
	_temp_box(0.0, 3.0, 0.0, 3.0, -10.0, 0.0)
	await _phys(2)
	var events := []
	var on_run := func(_n: Vector3) -> void: events.append(&"wall_run")
	var on_end := func(jumped: bool) -> void: events.append(&"wall_jump" if jumped else &"wall_run_end")
	player.wall_run_started.connect(on_run)
	player.wall_run_finished.connect(on_end)
	await _place(Vector3(0.6, 3.05, -1.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -10.4, 2.0)
	var off := not player.is_on_floor() or player.global_position.z < -10.35
	Input.action_press(&"jump")
	await _phys(2)
	var did_jump := player.last_action == &"jump" or player.state == Player.State.WALL_RUN
	var up := player.velocity.y
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.4)
	_release_all()
	player.wall_run_started.disconnect(on_run)
	player.wall_run_finished.disconnect(on_end)
	_check("the press is a jump (full rise), then the wall-run starts; no wall-jump off the edge", off and did_jump
			and up > settings.jump_velocity() - 1.0 and ran and not events.has(&"wall_jump"), "%s up %.2f %s" % [events, up, player.last_action])
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)


# --- Climb -------------------------------------------------------------------

## Climb lab around x -100..-76: a 6 m block with a ladder up its east face to
## the roof, a wide climbable panel on its south face that ends 1.2 m above the
## ground, a plain (not climbable) north and west face, and a 9 m grapple
## tower east of the ladder.
func _build_climb_lab() -> void:
	kit.begin("ClimbLab")
	kit.building("Block", -100.0, -90.0, -10.0, 0.0, 6.0, Kit.ROOF)
	kit.ladder("Ladder", "x+", -90.0, -5.0, 0.0, 6.0)
	var panel := kit.face_box("Panel", "z+", 0.0, 0.0, 0.15, -99.0, -93.0, 1.2, 5.2, Kit.CLIMB)
	panel.collision_layer = Kit.CLIMB_LAYERS
	kit.building("Tower", -80.0, -76.0, -8.0, -2.0, 9.0, Kit.GRAPPLE)
	kit.anchor("TowerAnchor", Vector3(-79.6, 9.5, -5.0))
	kit.end()


func test_climb() -> void:
	_section("Climb: grab, up, down, sideways, off")
	var starts := []
	var ends := []
	var on_start := func(n: Vector3) -> void: starts.append(n)
	var on_end := func(reason: StringName) -> void: ends.append(reason)
	player.climb_started.connect(on_start)
	player.climb_finished.connect(on_end)

	# E at the foot of the ladder: grab it (no jump). The prompt says so.
	await _place(Vector3(-89.4, 0.05, -5.0), 90.0)
	var hint := player.prompt.hint_text()
	await _place(Vector3(-86.0, 0.05, -5.0), 90.0)
	var far_hint := player.prompt.hint_text()
	await _place(Vector3(-89.4, 0.05, -5.0), -90.0)
	var away_hint := player.prompt.hint_text()
	_check("prompt 'E CLIMB' only facing a ladder within reach", hint == "E CLIMB" and far_hint == "" and away_hint == "",
			"'%s' / far '%s' / facing away '%s'" % [hint, far_hint, away_hint])
	await _place(Vector3(-89.4, 0.05, -5.0), 90.0)
	await _tap(&"traverse")
	await _phys(2)
	_check("E facing the ladder: grabs it", player.state == Player.State.CLIMB and starts.size() == 1
			and (starts[0] as Vector3).is_equal_approx(Vector3.RIGHT), "%s %s" % [Player.State.keys()[player.state], starts])
	# W climbs up at climb speed.
	Input.action_press(&"move_forward")
	var y0 := player.global_position.y
	await _phys(30)
	var rate := (player.global_position.y - y0) / 0.5
	_check("W climbs up at %.1f m/s" % player.climb_up_speed, absf(rate - player.climb_up_speed) < 0.2, "%.2f m/s" % rate)
	# Keep going: pulled up onto the roof at the top.
	var top := await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 5.0)
	_release_all()
	await _phys(5)
	_check("at the top, holding W pulls up onto the roof (6 m)", top and ends.has(&"top")
			and absf(player.global_position.y - 6.0) < 0.1, "%s %s" % [player.global_position, ends])

	# Space at the foot to grab, S at the bottom steps off.
	ends.clear()
	await _place(Vector3(-89.4, 0.05, -5.0), 90.0)
	await _tap(&"jump")
	await _phys(2)
	var grabbed := player.state == Player.State.CLIMB
	Input.action_press(&"move_forward")
	await _phys(40)
	Input.action_release(&"move_forward")
	var high := player.global_position.y
	Input.action_press(&"move_back")
	var down := await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 3.0)
	_release_all()
	await _phys(20)
	_check("Space facing the ladder grabs it too; S climbs down and steps off at the bottom", grabbed and high > 1.2
			and down and ends == [&"bottom"] and player.is_on_floor() and player.global_position.y < 0.1,
			"high %.2f, %s at %s" % [high, ends, player.global_position])

	# Space on the ladder jumps away from it; it can't be re-grabbed at once.
	ends.clear()
	starts.clear()
	await _place(Vector3(-89.4, 0.05, -5.0), 90.0)
	await _tap(&"traverse")
	Input.action_press(&"move_forward")
	await _phys(40)
	await _tap(&"jump")
	var away := player.velocity.x
	await _phys(10)
	_check("Space: jumps away from the surface (push off + a normal jump's rise)", ends == [&"jump"]
			and away > player.climb_jump_push - 0.5 and player.state == Player.State.MOVE and starts.size() == 1,
			"%s, %.2f m/s off" % [ends, away])
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)

	# C lets go and drops.
	ends.clear()
	await _place(Vector3(-89.4, 0.05, -5.0), 90.0)
	await _tap(&"traverse")
	Input.action_press(&"move_forward")
	await _phys(50)
	Input.action_release(&"move_forward")
	await _tap(&"crouch")
	await _phys(3)
	_check("C lets go: drops off", ends == [&"drop"] and player.state == Player.State.MOVE and not player.is_on_floor(), str(ends))
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)

	# Jump into the ladder from a run-up, holding toward it: grabs in the air.
	ends.clear()
	starts.clear()
	await _place(Vector3(-86.0, 0.05, -5.0), 90.0)
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return player.global_position.x < -87.8, 2.0)
	await _tap(&"jump")
	var caught := await _wait_until(func() -> bool: return player.state == Player.State.CLIMB, 1.0)
	_release_all()
	_check("jumping into the ladder holding toward it: grabs it mid-air", caught and player.global_position.y > 0.3,
			"feet %.2f" % player.global_position.y)
	await _tap(&"crouch")
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)

	# Sideways on the wide panel, stopping at its edge; S off its bottom (in the air) lets go.
	await _place(Vector3(-96.0, 0.05, 0.6), 0.0)
	Input.action_press(&"move_forward")
	await _phys(4)
	Input.action_press(&"jump") # held: a tap is only a short hop, and the panel starts 1.2 m up
	var on_panel := await _wait_until(func() -> bool: return player.state == Player.State.CLIMB, 1.0)
	_release_all()
	Input.action_press(&"move_right")
	await _phys(40)
	var moved := player.global_position.x - -96.0
	await _phys(120)
	var edge_x := player.global_position.x
	Input.action_release(&"move_right")
	_check("A / D climbs sideways, stopping at the surface's edge", on_panel and moved > 0.8
			and edge_x < -93.0 + 0.1 and player.state == Player.State.CLIMB, "moved %.2f, stopped at x %.2f" % [moved, edge_x])
	ends.clear()
	Input.action_press(&"move_back")
	var let_go := await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 3.0)
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	_check("S past the bottom of a surface that ends in the air lets go (a short drop)", let_go and ends == [&"drop"]
			and player.is_on_floor(), str(ends))

	# Grapple straight off a climb.
	var anchor := lab.get_node("ClimbLab/TowerAnchor") as GrappleAnchor
	await _place(Vector3(-89.4, 0.05, -5.0), 90.0)
	await _tap(&"traverse")
	Input.action_press(&"move_forward")
	await _phys(30)
	Input.action_release(&"move_forward")
	ends.clear()
	var r := await _grapple_to(anchor)
	_check("grapple from a climb: lets go, pulled across onto the tower (9 m)", ends.has(&"grapple") and r.arrived
			and absf(r.landed.y - 9.0) < 0.1, "%s %s" % [ends, r])
	player.climb_started.disconnect(on_start)
	player.climb_finished.disconnect(on_end)


func test_climb_down_from_above() -> void:
	_section("Descent: E at the roof edge above the ladder, climb down")
	var ids := _record_traversals()
	var ends := []
	var on_end := func(reason: StringName) -> void: ends.append(reason)
	player.climb_finished.connect(on_end)
	await _place(Vector3(-90.6, 6.05, -5.0), -90.0) # on the roof by its east edge, facing over the ladder
	var hint := player.prompt.hint_text()
	await _tap(&"traverse")
	var mounted := await _wait_until(func() -> bool: return player.state == Player.State.CLIMB, 2.0)
	var y_on := player.global_position.y
	_check("prompt 'E CLIMB DOWN' at the edge above it", hint == "E CLIMB DOWN", "'%s'" % hint)
	_check("E at the edge: swings over onto the ladder below (no fall)", mounted and ids.has(&"climb_on")
			and y_on > 3.5 and y_on < 4.5, "%s feet %.2f" % [ids, y_on])
	Input.action_press(&"move_back")
	var down := await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 4.0)
	_release_all()
	_check("S climbs all the way down and steps off", down and ends == [&"bottom"] and player.global_position.y < 0.1,
			"%s %s" % [ends, player.global_position])
	# Without a climbable surface below, E at an edge does nothing.
	ids.clear()
	await _place(Vector3(-99.4, 6.05, -5.0), 90.0) # west edge: plain wall below
	var plain_hint := player.prompt.hint_text()
	await _tap(&"traverse")
	await _phys(20)
	_check("E at an edge with only a plain wall below: no prompt, nothing happens", ids.is_empty()
			and plain_hint == "" and player.state == Player.State.MOVE and player.global_position.y > 5.9, "%s '%s'" % [ids, plain_hint])
	# Hanging from the roof edge above the ladder (caught mid-fall), S climbs
	# down onto it instead of dropping.
	ends.clear()
	_release_all()
	player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(-89.4, 4.1, -5.0)))
	Input.action_press(&"move_forward")
	var hung := await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 0.5)
	_release_all()
	await _phys(5)
	Input.action_press(&"move_back")
	await _phys(3)
	var onto := player.state == Player.State.CLIMB
	var down_from_hang := await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 4.0)
	_release_all()
	_check("hanging above the ladder: S climbs down it instead of dropping", hung and onto and down_from_hang
			and ends == [&"bottom"], "hung %s, climbing %s, %s" % [hung, onto, ends])
	_stop_recording()
	player.climb_finished.disconnect(on_end)


func test_climb_no_accidents() -> void:
	_section("Climb: never by accident, never on plain walls")
	var starts := []
	var on_start := func(n: Vector3) -> void: starts.append(n)
	player.climb_started.connect(on_start)
	# Walking and sprinting into the ladder don't grab it.
	await _place(Vector3(-84.0, 0.05, -5.0), 90.0)
	Input.action_press(&"move_forward")
	await _phys(90)
	Input.action_press(&"sprint")
	await _phys(30)
	_release_all()
	_check("walking / sprinting into a ladder doesn't grab it", starts.is_empty() and player.state == Player.State.MOVE)
	# Plain wall: E and jumping into it never climb.
	await _place(Vector3(-95.0, 0.05, -10.6), 0.0) # north face is plain
	await _tap(&"traverse")
	await _phys(5)
	Input.action_press(&"move_forward")
	await _tap(&"jump")
	await _phys(60)
	_release_all()
	_check("E or a jump into a plain wall never climbs it", starts.is_empty(), str(starts))
	player.climb_started.disconnect(on_start)


# --- Windows -----------------------------------------------------------------

## Window lab around z 100: three rooms (open at the back, z 94) built with
## the city kit: a dive window with its sill 0.9 m above the floor on both
## sides, a dive window whose sill is 1.35 m above the street outside (0.9 m
## above the room's raised floor), and a plain window.
func _build_window_lab() -> void:
	kit.begin("WindowLab")
	_window_room("Dive", 0.0, 0.9, 0.0)
	_window_room("DiveHigh", 20.0, 1.35, 0.45)
	_window_room("Plain", 40.0, 0.9, 0.0).dive_window = false
	kit.end()


func _window_room(room: String, cx: float, sill: float, inner_floor: float) -> TraversalWindow:
	kit.wall(room + "Wall", "z", 100.0, 0.3, cx - 6.0, cx + 6.0, 0.0, sill + 2.7, Kit.ROOF, [Kit.window_hole(cx, sill)])
	kit.box(room + "Roof", cx - 6.0, cx + 6.0, sill + 2.7, sill + 3.0, 94.0, 100.15, Kit.ROOF)
	kit.box(room + "SideW", cx - 6.3, cx - 6.0, 0.0, sill + 2.7, 94.0, 100.15, Kit.ROOF)
	kit.box(room + "SideE", cx + 6.0, cx + 6.3, 0.0, sill + 2.7, 94.0, 100.15, Kit.ROOF)
	if inner_floor > 0.0:
		kit.box(room + "Floor", cx - 6.0, cx + 6.0, 0.0, inner_floor, 94.0, 99.85, Kit.FLOOR)
	return kit.dive_window(room, "z", 100.0, cx, sill)


## Standing right at the bottom of a window (touching the wall under the sill,
## or 0.8 m out), every way in but E: jump (tap / held), crouch-jump,
## crouch-walk, sprint in, sprint-jump, jump spam. None may get the player to
## the other side, through the opening or the wall.
func test_window_bottom() -> void:
	_section("Window bottom: no way through but E, and E never clips the wall")
	var ids := _record_traversals()
	var leaks := []
	var tried := 0
	for room: String in ["Dive", "DiveHigh", "Plain"]:
		var w := lab.get_node("WindowLab/" + room) as TraversalWindow
		for side: float in [1.0, -1.0]:
			for dist: float in [0.52, 0.8]:
				for seq: String in ["jump", "jump_hold", "jump_crouch", "crouch_walk", "sprint", "sprint_jump", "jump_spam"]:
					ids.clear()
					tried += 1
					if await _window_attempt(w, side, dist, seq):
						leaks.append("%s side %+d at %.2f m, %s -> %s %s" % [room, side, dist, seq, player.global_position, ids])
	_check("%d non-E attempts at the bottom of dive and plain windows, both sides: none gets through" % tried,
			leaks.is_empty(), str(leaks.slice(0, 4)))
	_stop_recording()

	# E right under the sill (touching the wall): the move rises in front of the
	# wall first and never passes through the wall below the opening. Dives keep
	# their slow time.
	for case: Array in [["Dive", 1.0], ["Dive", -1.0], ["DiveHigh", 1.0], ["DiveHigh", -1.0], ["Plain", 1.0]]:
		var w := lab.get_node("WindowLab/" + case[0]) as TraversalWindow
		var r := await _window_e(w, case[1], 0.52)
		var slow_ok: bool = r.slow or not w.dive_window
		_check("%s window, side %+d: E touching the wall under the sill goes through, never below the sill line%s"
				% [case[0], case[1], ", slow time on" if w.dive_window else ""], r.through and r.lowest >= -0.3 and slow_ok,
				"lowest %.2f m at the wall, %s" % [r.lowest, r])
	# From further out the approved dive path is unchanged (no extra rise).
	var dive := lab.get_node("WindowLab/Dive") as TraversalWindow
	var far := await _window_e(dive, 1.0, 2.8)
	_check("E from 2.8 m: dives through as before", far.through and far.slow and far.lowest >= -0.3, "%s" % far)
	# Plain window: sprinting or jumping into it does nothing; E climbs through.
	var plain := lab.get_node("WindowLab/Plain") as TraversalWindow
	ids = _record_traversals()
	await _place(plain.to_global(Vector3(0.0, 0.0, 8.0)) * Vector3(1, 0, 1) + Vector3(0, 0.05, 0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(90)
	_release_all()
	var sprint_ids := ids.duplicate()
	var plain_r := await _window_e(plain, 1.0, 1.2)
	_stop_recording()
	_check("plain window: sprinting into it does nothing, E climbs through", sprint_ids.is_empty() and plain_r.through,
			"sprint %s, E %s" % [sprint_ids, plain_r])


## One non-E attempt at window `w` from `side`, `dist` from the wall. True if
## the player ends up on the other side.
func _window_attempt(w: TraversalWindow, side: float, dist: float, seq: String) -> bool:
	var through := w.through_direction(w.to_global(Vector3(0.0, 0.0, side)))
	var yaw := atan2(-through.x, -through.z)
	var start := w.to_global(Vector3(0.0, 0.0, side * (dist + (4.0 if seq.begins_with("sprint") else 0.0))))
	start.y = _floor_under(w, side) + 0.05
	await _place(start, rad_to_deg(yaw))
	Input.action_press(&"move_forward")
	match seq:
		"jump":
			await _phys(3)
			await _tap(&"jump")
			await _phys(70)
		"jump_hold":
			await _phys(3)
			Input.action_press(&"jump")
			await _phys(70)
		"jump_crouch":
			await _phys(3)
			await _tap(&"jump")
			await _phys(6)
			Input.action_press(&"crouch")
			await _phys(70)
		"crouch_walk":
			Input.action_press(&"crouch")
			await _phys(90)
		"sprint":
			Input.action_press(&"sprint")
			await _phys(80)
		"sprint_jump":
			Input.action_press(&"sprint")
			await _wait_until(func() -> bool: return w.distance_to_wall(player.global_position) < 1.6, 2.0)
			await _tap(&"jump")
			await _phys(70)
		"jump_spam":
			for i in 5:
				await _tap(&"jump")
				await _phys(12)
	_release_all()
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
	await _phys(3)
	return w.side_of(player.global_position) != side and w.distance_to_wall(player.global_position) > 0.3


## E at window `w` from `side`, `dist` from the wall on the floor there;
## follows the move. `lowest` is the lowest feet height (window local) while
## the body is at the wall on the way in.
func _window_e(w: TraversalWindow, side: float, dist: float) -> Dictionary:
	var out := {through = false, lowest = INF, slow = false}
	var through := w.through_direction(w.to_global(Vector3(0.0, 0.0, side)))
	var start := w.to_global(Vector3(0.0, 0.0, side * dist))
	start.y = _floor_under(w, side) + 0.05
	await _place(start, rad_to_deg(atan2(-through.x, -through.z)))
	player.bullet_time.reset()
	var on_slow := func() -> void: out.slow = true
	player.bullet_time.started.connect(on_slow)
	await _tap(&"traverse")
	var frames := 0
	while frames < 150 and not (frames > 5 and player.state == Player.State.MOVE):
		var local := w.to_local(player.global_position)
		var near_side: bool = local.z * side >= 0.0
		if near_side and absf(local.z) <= w.wall_thickness * 0.5 + 0.3:
			out.lowest = minf(out.lowest, local.y)
		frames += 1
		await physics_frame
	player.bullet_time.started.disconnect(on_slow)
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	await _phys(3)
	out.through = w.side_of(player.global_position) != side and player.is_on_floor()
	player.bullet_time.reset()
	return out


## Floor height (world) just in front of window `w` on `side`.
func _floor_under(w: TraversalWindow, side: float) -> float:
	var p := w.to_global(Vector3(0.0, 0.0, side * 1.0))
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 3.0, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return 0.0 if hit.is_empty() else (hit.position as Vector3).y


# --- Helpers -----------------------------------------------------------------

func _temp_box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	if temp == null:
		temp = Node3D.new()
		lab.add_child(temp)
	var b := GreyboxBlock.new()
	b.size = Vector3(x1 - x0, y1 - y0, z1 - z0)
	b.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	b.color = Kit.RUN
	temp.add_child(b)


func _clear_temp() -> void:
	if temp != null:
		temp.free()
		temp = null


func _grapple_to(anchor: GrappleAnchor) -> Dictionary:
	var out := {seen = false, arrived = false, landed = Vector3.ZERO, on_floor = false}
	_aim_at(anchor.global_position)
	await _phys(2)
	out.seen = player.grapple.target == anchor
	var done := [false]
	var on_finish := func(arrived: bool) -> void:
		out.arrived = arrived
		done[0] = true
	player.grapple_finished.connect(on_finish)
	await _tap(&"grapple")
	await _wait_until(func() -> bool: return done[0], 5.0)
	player.grapple_finished.disconnect(on_finish)
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	await _phys(5)
	out.landed = player.global_position
	out.on_floor = player.is_on_floor()
	return out


## Points the camera (and so the grapple aim) straight at `point`.
func _aim_at(point: Vector3) -> void:
	var cam := player.camera
	var d := point - cam.global_position
	cam.yaw = atan2(-d.x, -d.z)
	cam.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(cam.min_pitch_degrees), deg_to_rad(cam.max_pitch_degrees))


var _traversal_log: Array[StringName] = []
var _traversal_cb: Callable


func _record_traversals() -> Array[StringName]:
	_traversal_log.clear()
	_traversal_cb = func(id: StringName) -> void: _traversal_log.append(id)
	player.traversal_started.connect(_traversal_cb)
	return _traversal_log


func _stop_recording() -> void:
	player.traversal_started.disconnect(_traversal_cb)


func _place(pos: Vector3, yaw_degrees: float) -> void:
	_release_all()
	player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), pos))
	player.camera.pitch = deg_to_rad(-12.0)
	await _phys(8)


func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func _mouse_button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)


func _key_event(action: StringName, pressed: bool) -> void:
	if MOUSE_FOR.has(action):
		_mouse_button(MOUSE_FOR[action], pressed)
		return
	var event := InputEventKey.new()
	event.physical_keycode = KEY_FOR[action]
	event.pressed = pressed
	Input.parse_input_event(event)


## Press and release, held across at least one physics tick like a real keypress.
func _tap(action: StringName) -> void:
	_key_event(action, true)
	await process_frame
	await physics_frame
	await physics_frame
	_key_event(action, false)


func _phys(n: int) -> void:
	for i in n:
		await physics_frame


## Waits (game time) until cond() is true; returns false on timeout.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var frames := int(timeout * 60.0)
	while frames > 0:
		if cond.call():
			return true
		frames -= 1
		await physics_frame
	return cond.call()


func _section(title: String) -> void:
	print("\n-- %s --" % title)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])
