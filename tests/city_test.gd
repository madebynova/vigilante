extends SceneTree
## City greybox checks. Drives the real city scene (scenes/main/city_main.tscn)
## through the Input system like movement_test.gd, playing the intended
## traversal routes with the movement exactly as it is, then sweeps the whole
## map: every grapple anchor pulled to from a real standing spot, the camera
## at many spots and angles, ground-level connectivity (no pits to get stuck
## in) and open space (nothing large and empty).
##
## Run headless:
##   godot --headless --path . -s res://tests/city_test.gd
## Also save screenshots (needs a window, so no --headless):
##   godot --path . -s res://tests/city_test.gd -- --shots=C:/some/dir

const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"sprint", &"jump", &"crouch", &"traverse", &"grapple", &"bullet_time"]
const KEY_FOR := {&"move_forward": KEY_W, &"move_left": KEY_A, &"move_back": KEY_S,
		&"move_right": KEY_D, &"jump": KEY_SPACE, &"traverse": KEY_E, &"bullet_time": KEY_F}
const MOUSE_FOR := {&"grapple": MOUSE_BUTTON_RIGHT}
const Audit := preload("res://tools/city/traversal_audit.gd")
const SPAWN := Vector3(-21.0, 0.05, 42.0)

var player: Player
var settings: MovementSettings
var city: Node3D
var shots_dir := ""
var passed := 0
var failed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
	var main: Node = load("res://scenes/main/city_main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	settings = player.settings
	city = main.get_node("CityGreybox")
	# The routes here are the city's, not the mission's: keep the mission (its
	# pickup zones and finish slow-motion) out of the way. tests/game_test.gd
	# plays the mission itself.
	var mission := main.get_node_or_null("Mission")
	if mission != null:
		mission.process_mode = Node.PROCESS_MODE_DISABLED
	_run.call_deferred()


func _run() -> void:
	await _phys(30)
	await test_spawn()
	await test_streets()
	await test_safehouse_route()
	await test_window_building()
	await test_needle_alley()
	await test_service_route()
	await test_slot_walljump_grab()
	await test_midrise()
	await test_facade_climb()
	await test_rooftop_run_grapple()
	await test_skyline_chain()
	await test_grapple_release()
	await test_fire_escapes()
	await test_ladders()
	await test_construction_site()
	await test_hotel_corridor()
	await test_network_links()
	await test_all_anchors()
	test_traversal_network()
	await test_day_night()
	await test_district_keys()
	await test_camera_collision()
	test_ground_connectivity()
	test_open_space()
	print("\n==== %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)


# --- Routes ------------------------------------------------------------------

func test_spawn() -> void:
	_section("Spawn / safehouse")
	_check("player on floor after spawn", player.is_on_floor())
	_check("spawned inside the safehouse", player.global_position.distance_to(SPAWN) < 0.2
			and _ray_hits(SPAWN + Vector3.UP, SPAWN + Vector3.UP * 6.0), str(player.global_position))
	var door := _ray_hits(SPAWN + Vector3.UP, SPAWN + Vector3.UP + Vector3.FORWARD * 8.0)
	_check("facing the open street door", not door)
	await _shot("city_01_spawn")
	# Out through the door onto South St.
	_hold_yaw(0.0)
	Input.action_press(&"move_forward")
	var out := await _wait_until(func() -> bool: return player.global_position.z < 33.0, 3.0)
	_release_all()
	_check("walks out of the door onto the street", out and player.is_on_floor(), str(player.global_position))
	# Inner stair up to the loft and back down.
	var up := await _walk_to([Vector3(-17.05, 0, 45.0), Vector3(-17.05, 0, 37.0), Vector3(-20.0, 0, 38.5)], false)
	_check("inner stair climbs to the loft (3.8 m)", up and absf(player.global_position.y - 3.8) < 0.1,
			str(player.global_position))
	await _place(Vector3(-24.0, 0.05, 33.0), 90.0)
	var roof := await _walk_to([Vector3(-30.7, 0, 33.0), Vector3(-30.7, 0, 45.0),
			Vector3(-27.0, 0, 44.5)], false)
	_check("outside stair reaches the safehouse roof (7.7 m)", roof and absf(player.global_position.y - 7.7) < 0.1,
			str(player.global_position))


func test_streets() -> void:
	_section("Street level")
	for run: Array in [["Central Ave", Vector3(1.8, 0.05, 64.0), 0.0, 120.0],
			["North Ave", Vector3(-62.0, 0.05, -27.0), -90.0, 124.0],
			["South St", Vector3(62.0, 0.05, 27.0), 90.0, 124.0],
			["West Service Lane", Vector3(-38.0, 0.05, 23.0), 0.0, 44.0],
			["East St", Vector3(31.0, 0.05, -23.0), 180.0, 44.0]]:
		var r := await _sprint_line(run[1], run[2], run[3])
		_check("sprint the length of %s unobstructed" % run[0], r.distance >= run[3] - 0.5 and r.slowest > settings.sprint_speed - 0.3,
				"%.1f m, slowest %.2f m/s" % [r.distance, r.slowest])
	await _shot("city_02_street")


## Section-4 layout at the safehouse: deck -> wall-run -> wall-jump -> E in
## through the loft's back window -> E out of the front window (slow time) ->
## grapple across South St onto the walk-up.
func test_safehouse_route() -> void:
	_section("Safehouse: wall-run -> window -> window -> grapple")
	var ids := _record_traversals()
	await _place(Vector3(-29.4, 3.85, 63.5), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 59.4, 3.0)
	Input.action_press(&"jump")
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _wait_until(func() -> bool: return player.global_position.z < 53.5, 1.0)
	Input.action_press(&"jump")
	var prompt := await _wait_until(func() -> bool: return player.prompt.hint_text() != "", 1.0)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.has(&"window_dive") and player.state == Player.State.MOVE, 2.0)
	_release_all()
	await _phys(10)
	var p := player.global_position
	_check("courtyard wall-run -> wall-jump -> E dives into the loft", ran and prompt and ids.has(&"window_dive")
			and player.is_on_floor() and absf(p.y - 3.8) < 0.1 and p.z > 36.3 and p.z < 45.7, "%s %s" % [ids, p])
	_stop_recording()
	await _shot("city_03_loft")
	var r := await _dive_out_and_grapple(Vector3(-27.1, 3.85, 38.3), 0.0, _anchor("DenseBlocks/WalkUp/AnchorWalkUpSouth"))
	_check("E out of the front window: airborne over South St, slow time on", r.dove and r.airborne and r.slow,
			"%s" % r)
	_check("grapple across the street -> onto the walk-up roof (10.5 m)", r.arrived and absf(r.pos.y - 10.5) < 0.1,
			"%s" % r)


## Window Building: jump the light well from the walk-up roof, E mid-air in
## through the west window, out of the east window over Central Ave (slow
## time), grapple across onto the corner block. Also its other two windows.
func test_window_building() -> void:
	_section("Window Building: rooftop -> jump -> window -> window -> grapple")
	var ids := _record_traversals()
	await _place(Vector3(-24.0, 10.55, 12.0), -90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.x > -18.6, 2.0)
	Input.action_press(&"jump")
	var close := await _wait_until(func() -> bool: return player.global_position.x > -17.7 and not player.is_on_floor(), 1.0)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.has(&"window_dive") and player.state == Player.State.MOVE, 2.0)
	_release_all()
	await _phys(10)
	var p := player.global_position
	_check("sprint-jump across the light well, E mid-air: in through the west window", close and ids.has(&"window_dive")
			and player.is_on_floor() and absf(p.y - 10.5) < 0.1 and p.x > -14.7, "%s %s" % [ids, p])
	_stop_recording()
	var corner := _anchor("DenseBlocks/EastBlock/AnchorCornerWest")
	var r := await _dive_out_and_grapple(Vector3(-9.0, 10.55, 12.0), -90.0, corner)
	_check("E out of the east window: airborne over Central Ave, slow time on", r.dove and r.airborne and r.slow, "%s" % r)
	_check("grapple across the avenue -> onto the corner block (14 m)", r.arrived and absf(r.pos.y - 14.0) < 0.1, "%s" % r)
	await _shot("city_04_window_building")

	# North window: out over Needle Alley straight onto the roof opposite.
	await _place(Vector3(-10.75, 10.55, 4.6), 0.0)
	Input.action_press(&"move_forward")
	await _phys(2)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.global_position.z < -1.6 and player.is_on_floor(), 3.0)
	_release_all()
	p = player.global_position
	_check("north window dives out over the alley onto the roof opposite (10.5 m)", absf(p.y - 10.5) < 0.1 and p.z < -1.5, str(p))
	# South window: out over South St, grapple home to the safehouse roof.
	var home := _anchor("SafehouseDistrict/Safehouse/AnchorSafehouseRoof")
	r = await _dive_out_and_grapple(Vector3(-10.75, 10.55, 19.4), 180.0, home, false)
	_check("south window -> grapple home onto the safehouse roof (7.7 m)", r.dove and r.airborne and r.arrived
			and absf(r.pos.y - 7.7) < 0.1, "%s" % r)


## Yard -> fire escape -> roof -> sprint along the tenement -> wall-run over the
## gap -> wall-jump across the slot -> next roof -> grapple up the tenement.
func test_service_route() -> void:
	_section("Service yard: fire escape -> roof -> wall-run -> wall-jump -> roof -> grapple")
	await _place(Vector3(-58.5, 0.05, -1.5), 0.0)
	var climbed := await _walk_to([Vector3(-58.5, 0, -4.25), Vector3(-52.0, 0, -4.25), Vector3(-52.0, 0, -5.4),
			Vector3(-58.3, 0, -5.4), Vector3(-58.3, 0, -4.25), Vector3(-52.0, 0, -4.25), Vector3(-52.0, 0, -5.4),
			Vector3(-58.3, 0, -5.4), Vector3(-58.3, 0, -4.25), Vector3(-52.0, 0, -4.25), Vector3(-52.0, 0, -5.4),
			Vector3(-52.0, 0, -8.0)], false, 30.0)
	_check("walk up the fire escape's three flights onto the roof (10.5 m)", climbed and player.is_on_floor()
			and absf(player.global_position.y - 10.5) < 0.1, str(player.global_position))
	await _shot("city_05_fire_escape_top")
	await _place(Vector3(-49.7, 10.55, -6.6), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -11.4, 2.0)
	Input.action_press(&"jump")
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(16)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state != Player.State.WALL_RUN, 0.3)
	var jumped := player.last_action == &"wall_jump"
	Input.action_press(&"move_left")
	await _wait_until(func() -> bool: return player.is_on_floor() or player.state == Player.State.LEDGE_HANG, 2.0)
	var grabbed := player.state == Player.State.LEDGE_HANG
	if grabbed:
		_release_all()
		await _phys(4)
		await _tap(&"jump")
		await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	await _phys(5)
	var p := player.global_position
	_check("wall-run over the gap along the tenement, wall-jump onto the next roof (11 m)", ran and jumped
			and player.is_on_floor() and absf(p.y - 11.0) < 0.1 and p.x < -52.0, "%s grabbed=%s" % [p, grabbed])
	var r := await _grapple_to(_anchor("ServiceDistrict/NorthRow/AnchorTenementWest"))
	_check("grapple from that roof up onto the tenement (17.5 m)", r.arrived and absf(r.landed.y - 17.5) < 0.1, "%s" % r)


## Ground wall-run in a brick slot, wall-jump, grab a roof no jump reaches
## (the playground route-2 pattern), in the service district.
func test_slot_walljump_grab() -> void:
	_section("Service slot: wall-run -> wall-jump -> grab the workshop roof")
	await _place(Vector3(-50.7, 0.05, 7.0), 180.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z > 11.0, 2.0)
	Input.action_press(&"jump")
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(12)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state != Player.State.WALL_RUN, 0.3)
	Input.action_press(&"move_right") # facing south, right is west: toward the workshop
	var grab_or_land := func() -> bool: return player.state == Player.State.LEDGE_HANG or (player.is_on_floor() and player.global_position.y > 4.0)
	var grabbed := await _wait_until(grab_or_land, 2.0)
	_release_all()
	if player.state == Player.State.LEDGE_HANG:
		await _phys(4)
		await _tap(&"jump")
		await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	await _phys(10)
	_check("slot wall-run -> wall-jump -> grab -> on the workshop roof (4.5 m)", ran and grabbed and player.is_on_floor()
			and absf(player.global_position.y - 4.5) < 0.1, str(player.global_position))
	await _place(Vector3(-52.0, 0.05, 15.0), 90.0)
	Input.action_press(&"move_forward")
	await _phys(20)
	Input.action_press(&"jump")
	await _phys(60)
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	_check("a plain jump from the ground can't reach that roof", player.global_position.y < 0.1, str(player.global_position))


func test_midrise() -> void:
	_section("Mid-rise roofs")
	await _place(Vector3(23.5, 14.05, -6.0), -90.0)
	var crossed := await _walk_to([Vector3(40.0, 0, -6.0)], true)
	_check("skybridge over East St at 14 m", crossed and absf(player.global_position.y - 14.0) < 0.1, str(player.global_position))
	# 3 m gap to a roof 3.5 m higher: sprint, jump, grab, climb.
	await _place(Vector3(44.5, 14.05, -17.0), -90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.x > 47.5, 2.0)
	Input.action_press(&"jump")
	var hang := await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 1.5)
	_release_all()
	await _phys(4)
	await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	await _phys(10)
	_check("3 m gap up to a roof 3.5 m higher: jump, grab, climb (17.5 m)", hang and absf(player.global_position.y - 17.5) < 0.1,
			str(player.global_position))
	# 3 m drop-gap.
	var dropped := await _run_and_land(Vector3(58.0, 17.55, -14.0), 180.0, func() -> bool: return player.global_position.z > -11.4)
	_check("3 m gap down to the next roof (15.5 m)", dropped and absf(player.global_position.y - 15.5) < 0.1
			and player.global_position.z > -8.0, str(player.global_position))
	# 9 m gap: no jump (even with a ledge grab) clears it; a wall-run along the tall block does.
	var runs := []
	var on_run := func(normal: Vector3) -> void: runs.append(normal)
	player.wall_run_started.connect(on_run)
	var across := await _run_and_land(Vector3(53.7, 15.55, -0.5), 180.0, func() -> bool: return player.global_position.z > 3.6)
	player.wall_run_started.disconnect(on_run)
	_check("wall-run across the 9 m gap along the tall block", across and runs.size() == 1
			and absf(player.global_position.y - 15.5) < 0.1 and player.global_position.z > 13.0, "%s runs %d" % [player.global_position, runs.size()])
	await _shot("city_06_midrise")
	var plain := await _run_and_land(Vector3(58.0, 15.55, -0.5), 180.0, func() -> bool: return player.global_position.z > 3.6)
	_check("the same gap away from the wall is too far to jump (or grab)", plain and player.global_position.y < 1.0, str(player.global_position))


## Avenue facade: awning -> balcony -> roof, each a jump-and-grab.
func test_facade_climb() -> void:
	_section("Facade climb: awning -> balcony -> roof")
	await _place(Vector3(-2.0, 0.05, -12.0), 90.0)
	var heights := []
	for i in 3:
		Input.action_press(&"move_forward")
		Input.action_press(&"jump")
		var grabbing := func() -> bool: return player.state == Player.State.LEDGE_HANG or player.state == Player.State.TRAVERSAL
		var hung := await _wait_until(grabbing, 1.2)
		Input.action_release(&"jump")
		if hung and player.state == Player.State.LEDGE_HANG:
			Input.action_release(&"move_forward")
			await _phys(4)
			await _tap(&"jump")
		await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
		_release_all()
		await _phys(6)
		heights.append(snappedf(player.global_position.y, 0.01))
	_check("street -> awning (3.5) -> balcony (7) -> roof (10.5)", heights == [3.5, 7.0, 10.5], str(heights))


## Rooftop wall-runs that end in the air, then a grapple.
func test_rooftop_run_grapple() -> void:
	_section("Rooftop wall-run -> grapple")
	for case: Array in [
			["hotel flank -> over North Ave -> Meridian terrace (10.5)", Vector3(-20.3, 10.55, -9.0), -14.5,
				"Skyline/Meridian/AnchorTerrace", 10.5],
			["office tower flank -> over North Ave -> Spire base (28)", Vector3(12.3, 14.05, -8.5), -15.0,
				"Skyline/Spire/AnchorSpireBase", 28.0]]:
		await _place(case[1], 0.0)
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		var jump_at: float = case[2]
		await _wait_until(func() -> bool: return player.global_position.z < jump_at, 2.0)
		Input.action_press(&"jump")
		var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
		await _wait_until(func() -> bool: return player.state != Player.State.WALL_RUN, 1.5)
		var off := player.state == Player.State.MOVE and not player.is_on_floor()
		_release_all()
		var r := await _grapple_to(_anchor(case[3]))
		_check("%s" % case[0], ran and off and r.arrived and absf(r.landed.y - case[4]) < 0.1, "ran %s off %s %s" % [ran, off, r])


## Construction site -> crane -> Meridian -> across Central Ave -> Spire.
func test_skyline_chain() -> void:
	_section("Skyline chain")
	await _place(Vector3(-41.0, 24.55, -61.0), -90.0)
	var steps := [["top slab -> crane deck (30)", "Skyline/Crane/AnchorCraneDeck", 30.0, Vector3.INF],
			["crane deck -> Meridian roof (38)", "Skyline/Meridian/AnchorMeridianWest", 38.0, Vector3(-33.0, 0, -60.0)],
			["Meridian -> across Central Ave -> Spire mid terrace (42), ~25 m", "Skyline/Spire/AnchorSpireMidWest", 42.0, Vector3(-11.5, 0, -61.0)],
			["Spire mid -> Spire crown (56)", "Skyline/Spire/AnchorSpireCrown", 56.0, Vector3(21.0, 0, -55.0)]]
	for step: Array in steps:
		if step[3] != Vector3.INF:
			await _walk_to([step[3]], false)
		var r := await _grapple_to(_anchor(step[1]))
		_check(step[0], r.arrived and absf(r.landed.y - step[2]) < 0.1, "%s" % r)
	await _shot("city_07_crown")
	# Back down: the Spire base's terrace up to the mid level.
	await _place(Vector3(21.0, 28.05, -46.8), 0.0)
	var back := await _grapple_to(_anchor("Skyline/Spire/AnchorSpireMid"))
	_check("Spire base terrace -> mid (42)", back.arrived and absf(back.landed.y - 42.0) < 0.1, "%s" % back)


## Grapple -> let go mid-pull -> the kept momentum carries on: from the
## safehouse roof across South St, released short of the anchor, over the
## walk-up's edge and running on.
func test_grapple_release() -> void:
	_section("Grapple -> release -> keep moving")
	var anchor := _anchor("DenseBlocks/WalkUp/AnchorWalkUpSouth")
	await _place(Vector3(-27.1, 7.75, 40.0), 0.0)
	_aim_at(anchor.global_position)
	await _phys(2)
	await _tap(&"grapple")
	await _wait_until(func() -> bool: return player.state == Player.State.GRAPPLE and player.global_position.y > 10.6, 3.0)
	var pulled := player.velocity
	var released_at := player.global_position
	await _tap(&"grapple")
	var kept := player.velocity
	Input.action_press(&"move_forward")
	var landed := await _wait_until(func() -> bool: return player.is_on_floor() and player.state == Player.State.MOVE, 3.0)
	var speed := player.horizontal_speed()
	await _phys(20)
	_release_all()
	var p := player.global_position
	_check("let go mid-pull, short of the anchor: carries on the pull's way, trimmed (no snap, no launch)",
			player.last_action != &"grapple_arrive" and released_at.distance_to(anchor.global_position) > 1.5
			and kept.distance_to(player.grapple.release_velocity(pulled)) < 1.5 and kept.length() > settings.sprint_speed,
			"released %.1f m out at %.1f m/s, then %.1f m/s" % [released_at.distance_to(anchor.global_position), pulled.length(), kept.length()])
	_check("carried over the edge onto the walk-up roof, running on", landed and absf(p.y - 10.5) < 0.1 and p.z < 21.0
			and speed > settings.walk_speed, "%s, %.1f m/s on landing" % [p, speed])


## Fire escapes: every level is a grabbable edge, the hotel's has a drop
## ladder (no stair from the street), and they lead on to wall-runs, climbs,
## rooftops and grapples.
func test_fire_escapes() -> void:
	_section("Fire escapes: jump / ladder on, then wall-run, climb, grapple")
	# Walk up from the street, jump, grab the hotel fire escape's first level, climb up.
	await _place(Vector3(-28.5, 0.05, -27.0), 180.0)
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return player.global_position.z > -25.3, 2.0)
	Input.action_press(&"jump")
	var hung := await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 1.5)
	_release_all()
	await _phys(4)
	await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
	await _phys(5)
	_check("street -> jump -> grab the hotel fire escape's first level -> climb onto it (3.5 m)", hung
			and absf(player.global_position.y - 3.5) < 0.1, str(player.global_position))
	# Its drop ladder.
	var r := await _climb_up(Vector3(-32.3, 0.05, -25.4), 180.0)
	_check("hotel fire escape: E at the drop ladder, climb up onto the first landing (3.5 m)", r.climbed
			and absf(r.pos.y - 3.5) < 0.1, "%s" % r)
	# Level 2 -> sprint off the end -> wall-run the north face -> wall-jump -> grapple the terrace.
	var runs := []
	var on_run := func(n: Vector3) -> void: runs.append(n)
	player.wall_run_started.connect(on_run)
	await _place(Vector3(-31.0, 7.05, -23.0), -90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.x > -24.6, 2.0)
	Input.action_press(&"jump")
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(20)
	await _tap(&"jump")
	var jumped := player.last_action == &"wall_jump"
	_release_all()
	player.wall_run_started.disconnect(on_run)
	var g := await _grapple_to(_anchor("Skyline/Meridian/AnchorTerrace"))
	_check("hotel fire escape level 2 -> sprint off the end -> wall-run the north face -> wall-jump -> grapple the terrace (10.5)",
			ran and runs.size() == 1 and (runs[0] as Vector3).dot(Vector3.FORWARD) > 0.9 and jumped and g.arrived
			and absf(g.landed.y - 10.5) < 0.1, "ran %s %s jumped %s %s" % [ran, runs, jumped, g])
	# Top landing -> run and jump off -> grapple.
	await _place(Vector3(-24.7, 17.55, -23.9), 0.0)
	Input.action_press(&"move_forward")
	await _phys(8)
	await _tap(&"jump")
	await _phys(10)
	_release_all()
	var airborne := not player.is_on_floor()
	g = await _grapple_to(_anchor("Skyline/Meridian/AnchorTerrace"))
	_check("hotel fire escape top -> jump off -> grapple the Meridian terrace (10.5)", airborne and g.arrived
			and absf(g.landed.y - 10.5) < 0.1, "%s" % g)
	# Mid-rise: the new fire escape's top walkway -> ladder -> roof by the 9 m gap.
	r = await _climb_up(Vector3(60.9, 14.05, 23.1), 0.0)
	_check("mid-rise fire escape top -> climb the ladder onto the gap roof (15.5)", r.climbed and absf(r.pos.y - 15.5) < 0.1, "%s" % r)
	# Street -> the mid-rise fire escape's stair -> level 1.
	await _place(Vector3(52.8, 0.05, 24.3), -90.0)
	var up := await _walk_to([Vector3(54.8, 0, 24.25), Vector3(59.9, 0, 24.25), Vector3(60.5, 0, 23.1)], false)
	_check("mid-rise fire escape: its first flight from South St reaches level 1 (3.5)", up
			and absf(player.global_position.y - 3.5) < 0.1, str(player.global_position))


## Ladders and drainpipes added where a roof had one way up: each climbed from
## the bottom, plus a climb down from the top.
func test_ladders() -> void:
	_section("Ladders and drainpipes")
	for case: Array in [
			["billboard ladder: parking lot -> catwalk (9)", Vector3(-52.8, 0.05, 64.4), 180.0, 9.0],
			["walk-up row: WalkUpC roof -> ladder -> WalkUpD roof (17.5)", Vector3(56.4, 10.55, 50.0), -90.0, 17.5],
			["mid-rise: service passage -> drainpipe -> gap roof (15.5)", Vector3(62.6, 0.05, -2.0), 90.0, 15.5],
			["Window Building: Central Ave -> drainpipe -> roof (14)", Vector3(-5.9, 0.05, 2.4), 90.0, 14.0],
			["service yard: North Ave -> ladder -> gap roof (11)", Vector3(-58.0, 0.05, -23.1), 180.0, 11.0]]:
		var r := await _climb_up(case[1], case[2])
		_check(case[0], r.climbed and absf(r.pos.y - case[3]) < 0.1, "%s" % r)
	# And back down: E at the gap roof's edge above the drainpipe, S to the street.
	var ends := []
	var on_end := func(reason: StringName) -> void: ends.append(reason)
	player.climb_finished.connect(on_end)
	await _place(Vector3(61.4, 15.55, -2.0), -90.0)
	var hint := player.prompt.hint_text()
	await _tap(&"traverse")
	var on := await _wait_until(func() -> bool: return player.state == Player.State.CLIMB, 2.0)
	Input.action_press(&"move_back")
	var down := await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 10.0)
	_release_all()
	player.climb_finished.disconnect(on_end)
	_check("gap roof: E at the edge (prompt 'E CLIMB DOWN'), climb down the drainpipe to the street", hint == "E CLIMB DOWN"
			and on and down and ends == [&"bottom"] and player.global_position.y < 0.1, "'%s' %s %s" % [hint, ends, player.global_position])
	# Workshop: the dumpster in the yard's corner is the step up to its roof.
	await _place(Vector3(-64.5, 1.35, 8.2), 180.0)
	Input.action_press(&"move_forward")
	await _phys(2)
	Input.action_press(&"jump")
	var grab := await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG or player.state == Player.State.TRAVERSAL, 1.2)
	_release_all()
	if player.state == Player.State.LEDGE_HANG:
		await _phys(4)
		await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
	await _phys(5)
	_check("service yard: dumpster -> jump -> grab -> workshop roof (4.5)", grab and absf(player.global_position.y - 4.5) < 0.1,
			str(player.global_position))


## The construction site: several ways up, across and out.
func test_construction_site() -> void:
	_section("Construction site")
	# Street level: sprint into the light shaft, wall-run the lift core, wall-jump across, grab floor 1.
	var r := await _shaft_run(Vector3(-46.4, 0.05, -40.0), -50.6)
	_check("ground -> light shaft -> wall-run the lift core -> wall-jump -> grab the unfinished floor (3.5)", r.ran and r.jumped
			and absf(r.pos.y - 3.5) < 0.1 and r.pos.x < -50.0, "%s" % r)
	# From floor 1: the same wall at height, onto floor 2.
	r = await _shaft_run(Vector3(-46.4, 3.55, -46.6), -50.2)
	_check("floor 1 -> sprint -> wall-run the core over the shaft -> wall-jump -> grab floor 2 (7)", r.ran and r.jumped
			and absf(r.pos.y - 7.0) < 0.1 and r.pos.x < -50.0, "%s" % r)
	# Scaffold: drop ladder to level 1, the flight to level 2.
	var c := await _climb_up(Vector3(-59.3, 0.05, -43.1), 0.0)
	var up := await _walk_to([Vector3(-58.9, 0, -44.25), Vector3(-52.0, 0, -44.25), Vector3(-52.0, 0, -45.2)], false)
	_check("scaffold: drop ladder -> level 1 (3.5) -> flight -> level 2 (7)", c.climbed and absf(c.pos.y - 3.5) < 0.1 and up
			and absf(player.global_position.y - 7.0) < 0.1, "%s then %s" % [c, player.global_position])
	# Plank ramp from the forecourt.
	await _place(Vector3(-43.0, 0.05, -38.9), 0.0)
	up = await _walk_to([Vector3(-43.0, 0, -47.5)], false)
	_check("plank ramp: forecourt -> floor 1 (3.5)", up and absf(player.global_position.y - 3.5) < 0.1, str(player.global_position))
	# Floor 4: walk the beam out over the open bay, jump off the end, grapple the service tenement.
	await _place(Vector3(-55.0, 14.05, -55.0), 180.0)
	var walked := await _walk_to([Vector3(-55.0, 0, -46.9)], false)
	var on_beam := player.global_position.y > 13.9
	Input.action_press(&"move_forward")
	await _phys(4)
	await _tap(&"jump")
	await _phys(8)
	_release_all()
	var g := await _grapple_to(_anchor("ServiceDistrict/NorthRow/AnchorTenementNorth"))
	_check("floor 4 -> walk the beam -> jump off -> grapple across North Ave onto the tenement (17.5)", walked and on_beam
			and g.arrived and absf(g.landed.y - 17.5) < 0.1, "%s %s" % [player.global_position, g])
	# Site office: dive out of either window, grapple on.
	var d := await _dive_out_and_grapple(Vector3(-43.0, 14.05, -48.0), 180.0, _anchor("ServiceDistrict/NorthRow/AnchorTenementNorth"))
	_check("site office: E out of the south window (slow time), airborne -> grapple the tenement (17.5)", d.dove and d.airborne
			and d.slow and d.arrived and absf(d.pos.y - 17.5) < 0.1, "%s" % d)
	# East window: the dive drops below the terrace's roof line on the way, so
	# the pull meets the terrace's west wall. The world wins: the grapple lets
	# go there and, holding toward it, the ledge is caught and climbed.
	d = await _dive_out_and_grapple(Vector3(-42.0, 14.05, -48.0), -90.0, _anchor("Skyline/Meridian/AnchorTerrace"), true, true)
	_check("site office: E out of the east window, airborne -> grapple the Meridian terrace -> its wall -> ledge -> up (10.5)",
			d.dove and d.airborne and absf(d.pos.y - 10.5) < 0.1, "%s" % d)
	# Crane: the mast ladder through the deck hatch, jump down to the top slab, grapple the Meridian.
	c = await _climb_up(Vector3(-34.0, 0.05, -57.4), 0.0, 20.0)
	_check("crane: E at the mast ladder, climb 30 m through the hatch onto the deck", c.climbed and absf(c.pos.y - 30.0) < 0.1, "%s" % c)
	await _place(Vector3(-33.0, 30.05, -60.5), 90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.x < -36.7, 2.0)
	await _tap(&"jump")
	var landed := await _wait_until(func() -> bool: return player.is_on_floor() and player.global_position.y < 29.0, 3.0)
	_release_all()
	await _phys(5)
	var slab_y := player.global_position.y
	g = await _grapple_to(_anchor("Skyline/Meridian/AnchorMeridianWest"))
	_check("crane deck -> jump down onto the top slab (24.5) -> grapple the Meridian roof (38)", landed and absf(slab_y - 24.5) < 0.1
			and g.arrived and absf(g.landed.y - 38.0) < 0.1, "slab %.2f %s" % [slab_y, g])


## Sprints from `start` (facing north) into the light shaft, jumps into a
## wall-run on the lift core once past `jump_z`, wall-jumps after a few steps
## steering west, grabs whatever floor edge is there and climbs up.
func _shaft_run(start: Vector3, jump_z: float) -> Dictionary:
	var out := {ran = false, jumped = false, pos = Vector3.ZERO}
	await _place(start, 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < jump_z, 3.0)
	Input.action_press(&"jump")
	out.ran = await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(10)
	await _tap(&"jump")
	out.jumped = player.last_action == &"wall_jump"
	Input.action_press(&"move_left")
	var caught := func() -> bool:
		return player.state == Player.State.LEDGE_HANG or player.state == Player.State.TRAVERSAL or player.is_on_floor()
	await _wait_until(caught, 2.0)
	_release_all()
	if player.state == Player.State.LEDGE_HANG:
		await _phys(4)
		await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
	await _phys(5)
	out.pos = player.global_position
	return out


## E at a ladder from `pos` facing `yaw`, hold W to the top. {climbed, pos}.
func _climb_up(pos: Vector3, yaw: float, timeout := 10.0) -> Dictionary:
	var out := {climbed = false, grabbed = false, pos = Vector3.ZERO}
	await _place(pos, yaw)
	await _tap(&"traverse")
	out.grabbed = await _wait_until(func() -> bool: return player.state == Player.State.CLIMB, 0.5)
	Input.action_press(&"move_forward")
	var done := func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor() and player.last_action != &"climb"
	out.climbed = out.grabbed and await _wait_until(done, timeout)
	_release_all()
	await _phys(5)
	out.pos = player.global_position
	return out


## Needle Alley, compact (x -21..-6.5): the wall-run chain across it, and the
## ledges that alternate across it up to the roofs on both sides.
func test_needle_alley() -> void:
	_section("Needle Alley: wall-run chain, and both sides up")
	# The chain: north wall, wall-jump, south wall, wall-jump, grapple the
	# service yard's deck down the alley's line (through the hotel yard).
	var runs := []
	var on_run := func(normal: Vector3) -> void: runs.append(normal)
	player.wall_run_started.connect(on_run)
	await _place(Vector3(-3.0, 0.05, -0.8), 90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.x < -8.5, 2.0)
	Input.action_press(&"jump")
	var first := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(6)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state != Player.State.WALL_RUN, 0.3)
	Input.action_press(&"move_left") # facing west, left is south: steer across to the other wall
	var second := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.8)
	Input.action_release(&"jump")
	player.wall_run_started.disconnect(on_run)
	_check("wall-run the north wall, wall-jump, wall-run the south wall", first and second and runs.size() == 2
			and (runs[0] as Vector3).dot(Vector3.BACK) > 0.9 and (runs[1] as Vector3).dot(Vector3.FORWARD) > 0.9, str(runs))
	await _phys(4)
	await _tap(&"jump")
	var deck := _anchor("ServiceDistrict/Yard/AnchorYardDeck")
	var r := await _grapple_to(deck)
	_check("wall-jump -> grapple the yard deck down the alley's line (9 m)", r.seen and r.arrived
			and absf(r.landed.y - 9.0) < 0.1, "%s" % r)
	_release_all()
	# South side up: drainpipe to the first ledge (3.5), across and up to the
	# north ledge (7), up onto the avenue block's roof (10.5).
	var c := await _climb_up(Vector3(-20.4, 0.05, -0.2), 180.0)
	var s1: bool = c.climbed and absf(c.pos.y - 3.5) < 0.1
	await _walk_to([Vector3(-17.0, 0, 0.75)], false)
	player.camera.yaw = 0.0 # face north, across the alley
	var n2 := await _jump_grab_climb()
	var roof_n := await _jump_grab_climb()
	_check("alley south: drainpipe -> ledge (3.5) -> jump across -> north ledge (7) -> avenue block roof (10.5)", s1
			and absf(n2.y - 7.0) < 0.1 and absf(roof_n.y - 10.5) < 0.1, "%s / %s / %s" % [c.pos, n2, roof_n])
	# North ledge -> across and up to the south ledge (10.5) in front of the
	# Window Building's north window -> E in; or up onto its roof.
	await _place(Vector3(-12.4, 7.05, -0.75), 180.0)
	var s3 := await _jump_grab_climb()
	await _walk_to([Vector3(-10.75, 0, 0.8)], false)
	player.camera.yaw = PI # face south, at the window, pushing toward it
	Input.action_press(&"move_forward")
	await _phys(3)
	var hint := player.prompt.hint_text()
	var ids := _record_traversals()
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.has(&"window_dive") and player.state == Player.State.MOVE and player.is_on_floor(), 3.0)
	await _phys(5)
	_stop_recording()
	var inside := player.global_position
	_check("alley north ledge -> jump across -> south ledge (10.5) -> E through the Window Building's north window", absf(s3.y - 10.5) < 0.1
			and hint == "E DIVE THROUGH" and ids.has(&"window_dive") and absf(inside.y - 10.5) < 0.1 and inside.z > 2.0,
			"%s hint '%s' %s -> %s" % [s3, hint, ids, inside])
	await _place(Vector3(-9.1, 10.55, 0.8), 180.0)
	var wb_roof := await _jump_grab_climb()
	_check("from that ledge (away from the window): grab the Window Building's roof (14)", absf(wb_roof.y - 14.0) < 0.1, str(wb_roof))


## The hotel's corridor: in from its fire escape's third level on North Ave,
## through the building, out over the hotel yard, grapple the walk-up.
func test_hotel_corridor() -> void:
	_section("Hotel: fire escape -> E in -> corridor -> E out over the yard -> grapple")
	var ids := _record_traversals()
	await _place(Vector3(-24.5, 10.55, -23.1), 180.0)
	var hint := player.prompt.hint_text()
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.has(&"window_dive") and player.state == Player.State.MOVE and player.is_on_floor(), 3.0)
	await _phys(5)
	_stop_recording()
	var p := player.global_position
	_check("fire escape level 3 (prompt 'E DIVE THROUGH'): E dives into the corridor (10.5)", hint == "E DIVE THROUGH"
			and ids.has(&"window_dive") and absf(p.y - 10.5) < 0.1 and p.z > -22.0, "'%s' %s %s" % [hint, ids, p])
	var ran := await _walk_to([Vector3(-24.5, 0, -4.0)], true)
	_check("the corridor runs right through the hotel", ran and absf(player.global_position.y - 10.5) < 0.1, str(player.global_position))
	var d := await _dive_out_and_grapple(Vector3(-24.5, 10.55, -4.0), 180.0, _anchor("DenseBlocks/WalkUp/AnchorWalkUpYard"))
	_check("E out of the south window over the yard (slow time) -> grapple onto the walk-up (10.5)", d.dove and d.airborne
			and d.slow and d.arrived and absf(d.pos.y - 10.5) < 0.1, "%s" % d)


## New links in the network: roof catwalk, fire escapes to roofs that had no
## street route, the diner ledge off the plaza wall-run.
func test_network_links() -> void:
	_section("Network links: catwalk, fire escapes to roofs, plaza wall-run")
	await _place(Vector3(-43.5, 17.55, -18.9), -90.0)
	var crossed := await _walk_to([Vector3(-33.0, 0, -18.9)], false)
	_check("service tenement roof -> catwalk over the lane -> hotel roof (17.5)", crossed
			and absf(player.global_position.y - 17.5) < 0.1, str(player.global_position))
	# Corner block: its new fire escape from South St to the roof (14).
	await _place(Vector3(9.0, 0.05, 25.3), -90.0)
	var pts := [Vector3(9.0, 0, 24.25)]
	for i in 4:
		pts.append_array([Vector3(15.6, 0, 24.25), Vector3(15.6, 0, 23.1), Vector3(8.4, 0, 23.1), Vector3(8.4, 0, 24.25)])
	pts.resize(pts.size() - 2)
	pts.append(Vector3(15.6, 0, 21.4))
	var up := await _walk_to(pts, false, 40.0)
	_check("east block: corner fire escape from South St -> roof (14)", up and absf(player.global_position.y - 14.0) < 0.1,
			str(player.global_position))
	# Office tower: seven flights from East St to its roof (24.5).
	await _place(Vector3(27.3, 0.05, -21.4), 180.0)
	pts = [Vector3(27.25, 0, -20.4)]
	for i in 7:
		pts.append_array([Vector3(27.25, 0, -13.0), Vector3(26.1, 0, -13.0), Vector3(26.1, 0, -20.4), Vector3(27.25, 0, -20.4)])
	pts.resize(pts.size() - 2)
	pts.append(Vector3(24.6, 0, -13.0))
	up = await _walk_to(pts, false, 60.0)
	_check("office tower: fire escape from East St all the way to the roof (24.5)", up
			and absf(player.global_position.y - 24.5) < 0.1, str(player.global_position))
	# Plaza wall-run -> wall-jump -> the diner's side ledge -> its roof.
	await _place(Vector3(24.45, 0.05, 38.0), 180.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z > 41.0, 2.0)
	Input.action_press(&"jump")
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _wait_until(func() -> bool: return player.global_position.z > 49.5, 1.2)
	await _tap(&"jump")
	Input.action_press(&"move_right") # facing south, right is west: toward the diner
	var caught := func() -> bool: return player.state == Player.State.LEDGE_HANG or player.state == Player.State.TRAVERSAL
	var grabbed := await _wait_until(caught, 1.5)
	_release_all()
	if player.state == Player.State.LEDGE_HANG:
		await _phys(4)
		await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
	await _phys(5)
	var ledge_y := player.global_position.y
	player.camera.yaw = PI * 0.5 # face west, the diner wall
	var roof := await _jump_grab_climb()
	_check("plaza wall-run -> wall-jump -> diner side ledge (3.5) -> diner roof (7)", ran and grabbed and absf(ledge_y - 3.5) < 0.1
			and absf(roof.y - 7.0) < 0.1, "ran %s grabbed %s ledge %.2f roof %s" % [ran, grabbed, ledge_y, roof])


## The whole city as one network (tools/city/traversal_audit.gd): every
## elevated walkable surface reachable from the street without a single
## wall-run, every district with a street-level way in, no roof whose only
## way on is also its only way off, every anchor usable from somewhere.
func test_traversal_network() -> void:
	_section("Traversal network audit (whole map, no wall-runs assumed)")
	var audit := Audit.new(city, player.sensor, player.grapple)
	audit.run()
	var unreachable := audit.unreachable().map(func(s: Audit.Surface) -> String: return s.path)
	var dead := audit.dead_ends().map(func(s: Audit.Surface) -> String: return s.path)
	var important := audit.surfaces.filter(func(s: Audit.Surface) -> bool: return s.important).size()
	_check("all %d elevated walkable surfaces reachable from the street" % important, unreachable.is_empty(), str(unreachable))
	# The courtyard's loading deck is the courtyard wall-run's launch pad: its
	# way on is the wall-run, which the audit doesn't model.
	_check("no dead-end roofs (only back down) but the courtyard wall-run pad", dead == ["SafehouseDistrict/Courtyard/LoadingDeck"], str(dead))
	var street_in := {}
	for e: Array in audit.edges.get(Audit.STREET, []):
		var s: Audit.Surface = audit.surfaces[e[0]]
		street_in.get_or_add(s.district, {})[e[1]] = true
	var ok := true
	for district in ["SafehouseDistrict", "DenseBlocks", "ServiceDistrict", "MidriseDistrict", "Skyline"]:
		var kinds: Dictionary = street_in.get(district, {})
		print("    %-18s street -> up: %s" % [district, ", ".join(kinds.keys())])
		ok = ok and kinds.size() >= 2
	_check("every district has at least two kinds of way up from the street", ok, str(street_in))
	var unused := []
	for path: String in audit.anchor_sources:
		if audit.anchor_sources[path] <= 0:
			unused.append(path)
	_check("every grapple anchor is usable from at least one mapped standing spot", unused.is_empty(), str(unused))


## Day / night: N toggles; night is dark but readable (moon, ambient, lamps,
## lit windows), and nothing about movement changes.
func test_day_night() -> void:
	_section("Day / night")
	var dn := get_first_node_in_group(DayNight.GROUP) as DayNight
	_check("the city has a DayNight node", dn != null)
	if dn == null:
		return
	# The mission opens the city at night; these checks start from day.
	dn.set_night(false, true)
	_check("set to day: blend at day", not dn.night and is_zero_approx(dn.blend))
	var env := dn.environment.environment
	var lights := get_nodes_in_group(&"night_lights")
	var lit_windows := (get_first_node_in_group(&"city_lit_windows") as GeometryInstance3D).material_override as StandardMaterial3D
	var day_sun := dn.sun.light_energy
	_check("day: sun up, night lights off, windows unlit", day_sun > 1.0 and lights.all(func(l: Light3D) -> bool: return not l.visible)
			and is_zero_approx(lit_windows.emission_energy_multiplier), "sun %.2f" % day_sun)
	await _place(Vector3(0.0, 0.05, 10.0), 0.0)
	await _key(KEY_N)
	var night := await _real_until(func() -> bool: return is_equal_approx(dn.blend, 1.0), 5.0)
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	var label := root.get_node("CityMain/DebugHUD/Label") as Label
	await process_frame
	_check("N: blends to night within %.1f s" % dn.transition_time, night and dn.night and label.text.contains("NIGHT (N)"),
			"blend %.2f" % dn.blend)
	_check("night sky and a dim, cool moon", sky.sky_top_color.get_luminance() < 0.05 and dn.sun.light_energy < 0.5
			and dn.sun.light_color.b > dn.sun.light_color.r, "sky %s moon %.2f %s" % [sky.sky_top_color, dn.sun.light_energy, dn.sun.light_color])
	var visible := lights.filter(func(l: Light3D) -> bool: return l.visible and l.light_energy > 0.5).size()
	_check("street lamps and feature lights on (%d)" % visible, visible >= 20 and visible == lights.size())
	_check("a third of the facade windows lit", lit_windows.emission_energy_multiplier > 1.0, "%.2f" % lit_windows.emission_energy_multiplier)
	# Not pitch black: flat ambient (away from the sky) plus the moon keep every
	# surface readable before any lamp.
	var ambient := env.ambient_light_energy * env.ambient_light_color.get_luminance() * (1.0 - env.ambient_light_sky_contribution)
	_check("readable without any lamp (ambient %.2f, moon %.2f)" % [ambient, dn.sun.light_energy], ambient > 0.12 and dn.sun.light_energy > 0.2)
	# Movement doesn't care what time it is.
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(40)
	var speed := player.horizontal_speed()
	_release_all()
	_check("at night: time runs normally, sprint is sprint", is_equal_approx(Engine.time_scale, 1.0)
			and absf(speed - settings.sprint_speed) < 0.1, "%.2f m/s" % speed)
	await _shot("city_night_street")
	await _key(KEY_N)
	var day := await _real_until(func() -> bool: return is_zero_approx(dn.blend), 5.0)
	_check("N again: back to day, night pieces off", day and not dn.night and lights.all(func(l: Light3D) -> bool: return not l.visible)
			and is_zero_approx(lit_windows.emission_energy_multiplier) and absf(dn.sun.light_energy - day_sun) < 0.01)


## Jump holding W at the edge in front (yaw already set), grab, climb up.
## Returns where the feet end up.
func _jump_grab_climb() -> Vector3:
	_release_all()
	await _phys(2)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	var caught := func() -> bool: return player.state == Player.State.LEDGE_HANG or player.state == Player.State.TRAVERSAL
	await _wait_until(caught, 1.2)
	_release_all()
	if player.state == Player.State.LEDGE_HANG:
		await _phys(4)
		await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 2.0)
	await _phys(5)
	return player.global_position


## Presses and releases a physical key (debug keys handled in _unhandled_input).
## A new event for each: Input keeps a reference to a parsed event until it
## is flushed, so reusing one would turn the press into a release.
func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = pressed
		Input.parse_input_event(key)
		await process_frame
		await process_frame


## Waits (real time) until cond() is true; returns false on timeout.
func _real_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_usec() + int(timeout * 1_000_000)
	while Time.get_ticks_usec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


# --- Sweeps ------------------------------------------------------------------

## Every anchor in the city, pulled to from a real standing spot nearby:
## [path, feet position, expected landing height (NAN: tank top or roof below)].
const ANCHOR_SPOTS := [
	["SafehouseDistrict/Safehouse/AnchorSafehouseRoof", Vector3(-22.0, 10.55, 21.0), 7.7],
	["SafehouseDistrict/ParkingLot/AnchorBillboard", Vector3(-48.0, 0.05, 52.0), 9.0],
	["SafehouseDistrict/WalkUps/AnchorWalkUpD", Vector3(52.0, 10.55, 45.0), 17.5],
	["SafehouseDistrict/WalkUps/AnchorWalkUpDNorth", Vector3(58.0, 15.55, 20.0), 17.5],
	["SafehouseDistrict/Courtyard/AnchorLoadingDeck", Vector3(-44.0, 9.05, 66.0), 3.8],
	["SafehouseDistrict/BackLot/AnchorTank", Vector3(52.5, 10.55, 51.0), 14.0],
	["DenseBlocks/Hotel/AnchorHotelNorth", Vector3(-16.0, 10.55, -41.0), 17.5],
	["DenseBlocks/Hotel/WaterTower/Anchor", Vector3(-25.0, 10.55, 8.0), NAN],
	["DenseBlocks/WalkUp/AnchorWalkUpSouth", Vector3(-27.1, 7.75, 40.0), 10.5],
	["DenseBlocks/WalkUp/AnchorWalkUpYard", Vector3(-24.0, 0.05, -1.0), 10.5],
	["DenseBlocks/EastBlock/AnchorCornerWest", Vector3(-10.0, 14.05, 12.0), 14.0],
	["DenseBlocks/EastBlock/AnchorOfficeTower", Vector3(19.0, 14.05, -3.0), 24.5],
	["ServiceDistrict/NorthRow/AnchorTenementWest", Vector3(-55.0, 11.05, -19.0), 17.5],
	["ServiceDistrict/NorthRow/AnchorTenementNorth", Vector3(-45.0, 0.05, -33.0), 17.5],
	["ServiceDistrict/Yard/AnchorYardDeck", Vector3(-38.0, 0.05, 0.0), 9.0],
	["MidriseDistrict/AnchorHighRoofNorth", Vector3(56.0, 26.05, -42.0), 17.5],
	["MidriseDistrict/WaterTower/Anchor", Vector3(44.0, 14.05, -17.0), NAN],
	["MidriseDistrict/AnchorTallWest", Vector3(37.0, 10.55, 8.0), 24.5],
	["Skyline/Meridian/AnchorTerrace", Vector3(-14.0, 0.05, -28.0), 10.5],
	["Skyline/Meridian/AnchorMeridianWest", Vector3(-33.0, 30.05, -60.0), 38.0],
	["Skyline/Meridian/AnchorMeridianEast", Vector3(12.0, 28.05, -55.0), 38.0],
	["Skyline/Crane/AnchorCraneDeck", Vector3(-41.0, 24.55, -61.0), 30.0],
	["Skyline/Spire/AnchorSpireBase", Vector3(21.0, 0.05, -28.0), 28.0],
	["Skyline/Spire/AnchorSpireBaseEast", Vector3(38.4, 35.05, -52.0), 28.0],
	["Skyline/Spire/AnchorSpireMid", Vector3(21.0, 28.05, -46.8), 42.0],
	["Skyline/Spire/AnchorSpireMidWest", Vector3(-11.5, 38.05, -61.0), 42.0],
	["Skyline/Spire/AnchorSpireCrown", Vector3(21.0, 42.05, -55.0), 56.0],
	["Skyline/Towers/AnchorTowerEastWest", Vector3(30.0, 28.05, -58.0), 35.0],
	["Skyline/Towers/AnchorTowerEastEast", Vector3(56.0, 26.05, -58.0), 35.0],
	["Skyline/Towers/AnchorTowerLowSouth", Vector3(58.0, 17.55, -20.0), 26.0],
	["Skyline/Towers/WaterTower/Anchor", Vector3(61.0, 26.05, -46.0), 31.5],
]


func test_all_anchors() -> void:
	_section("Every grapple anchor, from a real standing spot")
	var all := city.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is GrappleAnchor)
	_check("all %d anchors are covered below" % all.size(), all.size() == ANCHOR_SPOTS.size(), "%d in the city" % all.size())
	var failures := []
	var distances := []
	for spot: Array in ANCHOR_SPOTS:
		var anchor := _anchor(spot[0])
		var d := (anchor.global_position - spot[1]) as Vector3
		await _place(spot[1], rad_to_deg(atan2(-d.x, -d.z)))
		var chest: Vector3 = player.global_position + Vector3.UP * 1.2
		distances.append(chest.distance_to(anchor.global_position))
		var r := await _grapple_to(anchor)
		var expected: float = spot[2]
		var height_ok: bool = r.landed.y > 17.4 if is_nan(expected) else absf(r.landed.y - expected) < 0.1
		if not (r.seen and r.arrived and r.on_floor and r.clear and height_ok):
			failures.append("%s %s" % [spot[0].get_file(), r])
	_check("each anchor targeted, pulled to and landed on (%d)" % ANCHOR_SPOTS.size(), failures.is_empty(), str(failures))
	distances.sort()
	print("  grapple distances used: %.1f .. %.1f m" % [distances[0], distances[-1]])


func test_district_keys() -> void:
	_section("Debug keys 1-5 jump to the districts")
	var starts := get_nodes_in_group(&"playground_start")
	_check("five district start markers", starts.size() == 5, "%d" % starts.size())
	var ok := true
	for n in range(1, 6):
		await _place(Vector3(0.0, 0.05, 10.0), 0.0)
		var key := InputEventKey.new()
		key.keycode = (KEY_1 + n - 1) as Key
		key.physical_keycode = key.keycode
		key.pressed = true
		Input.parse_input_event(key)
		await _frames(2)
		key.pressed = false
		Input.parse_input_event(key)
		await _phys(10)
		var marker := starts.filter(func(m: Node) -> bool: return m.name == "Start%d" % n)
		ok = ok and marker.size() == 1 and player.global_position.distance_to((marker[0] as Node3D).global_position) < 0.3 \
				and player.is_on_floor()
	_check("each key lands the player on its district start", ok, str(player.global_position))


## The camera at many spots (tight interiors, slots, fire escapes, under slabs)
## and angles: never inside geometry, never with geometry between it and the player.
func test_camera_collision() -> void:
	_section("Camera collision across the city")
	var spots := [SPAWN, Vector3(-27.0, 0.05, 44.0), Vector3(-22.0, 3.85, 41.0), Vector3(-10.75, 10.55, 12.0),
			Vector3(-20.0, 0.05, 0.0), Vector3(-16.5, 0.05, 15.0), Vector3(-51.5, 0.05, 15.0), Vector3(18.5, 0.05, 12.0),
			Vector3(42.5, 0.05, 10.0), Vector3(-14.5, 0.05, 41.0), Vector3(-55.0, 3.55, -5.4), Vector3(-28.0, 3.85, 61.5),
			Vector3(-50.0, 0.05, -50.0), Vector3(-43.0, 10.55, -62.0), Vector3(0.0, 0.05, 0.0), Vector3(-34.0, 30.05, -59.0),
			Vector3(30.0, 14.05, -6.0), Vector3(57.0, 0.05, 7.5), Vector3(-48.0, 0.05, -55.0), Vector3(-43.0, 14.05, -48.0),
			Vector3(-34.0, 0.05, -57.4), Vector3(-59.3, 3.55, -44.2), Vector3(60.9, 14.05, 23.1),
			Vector3(-17.0, 3.55, 0.8), Vector3(-14.0, 7.05, -0.9), Vector3(-10.75, 10.55, 0.8), Vector3(-24.5, 10.55, -12.0),
			Vector3(-28.0, 0.05, 2.0), Vector3(26.1, 24.55, -16.0), Vector3(-38.0, 17.55, -18.9), Vector3(22.5, 3.55, 52.0)]
	var cam := player.camera
	var space := player.get_world_3d().direct_space_state
	var bad := []
	var pulled := 0
	var views := 0
	for spot: Vector3 in spots:
		await _place(spot, 0.0)
		for yaw_i in 8:
			for pitch: float in [-12.0, 35.0, -60.0]:
				cam.yaw = deg_to_rad(yaw_i * 45.0)
				cam.pitch = deg_to_rad(pitch)
				cam.snap()
				var cpos := cam.camera.global_position
				var q := PhysicsPointQueryParameters3D.new()
				q.position = cpos
				q.collision_mask = 1
				var inside := not space.intersect_point(q, 1).is_empty()
				var blocked := not space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, cpos, 1)).is_empty()
				views += 1
				if cam.boom_fraction < 0.99:
					pulled += 1
				if inside or blocked:
					bad.append("%s yaw %d pitch %d" % [spot, yaw_i * 45, pitch])
	cam.pitch = deg_to_rad(-12.0)
	cam.yaw = 0.0
	_check("camera clear of geometry in %d views at %d spots (%d pulled in by collision)" % [views, spots.size(), pulled],
			bad.is_empty(), str(bad.slice(0, 6)))


## Flood fill over the whole street level on a 1 m grid: every spot a body
## fits must connect back to Central Ave (no pits or enclosures to get stuck in).
func test_ground_connectivity() -> void:
	_section("Ground level: nowhere to get trapped")
	var x0 := -65.5
	var z0 := -71.5
	var nx := 132
	var nz := 142
	var open := PackedByteArray()
	open.resize(nx * nz)
	var open_count := 0
	for i in nx:
		for j in nz:
			var fits := player.sensor.has_clearance(Vector3(x0 + i, 0.03, z0 + j), 1.7, 0.3)
			open[i * nz + j] = 1 if fits else 0
			open_count += 1 if fits else 0
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var start := int(65.5) * nz + int(71.5) # (0, 0): Central Ave
	var reached := _flood(open, seen, start, nx, nz, x0, z0)
	var stuck := []
	for idx in nx * nz:
		if open[idx] == 1 and seen[idx] == 0:
			var size := _flood(open, seen, idx, nx, nz, x0, z0)
			stuck.append("%d cells near (%.1f, %.1f)" % [size, x0 + floori(float(idx) / nz), z0 + idx % nz])
	_check("all %d open street-level spots connect to the streets" % open_count, stuck.is_empty() and reached == open_count,
			"reached %d; isolated: %s" % [reached, stuck.slice(0, 8)])


## Every spot at street level has a structure (anything 0.5 m+ tall) within
## 10 m: no large, meaningless empty areas.
func test_open_space() -> void:
	_section("No large empty areas")
	var space := player.get_world_3d().direct_space_state
	var probe := BoxShape3D.new()
	probe.size = Vector3(20.0, 2.5, 20.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collision_mask = 1
	var empty := []
	var cells := 0
	var x := -64.0
	while x <= 64.0:
		var z := -70.0
		while z <= 68.0:
			params.transform = Transform3D(Basis(), Vector3(x, 1.75, z))
			cells += 1
			if space.intersect_shape(params, 1).is_empty():
				empty.append(Vector2(x, z))
			z += 4.0
		x += 4.0
	_check("no spot more than 10 m from any structure (%d samples)" % cells, empty.is_empty(), str(empty.slice(0, 10)))


# --- Helpers -----------------------------------------------------------------

func _anchor(path: String) -> GrappleAnchor:
	return city.get_node(path) as GrappleAnchor


func _ray_hits(from: Vector3, to: Vector3) -> bool:
	return not player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()


func _hold_yaw(degrees: float) -> void:
	player.camera.yaw = deg_to_rad(degrees)


## Walks (or sprints) through `points` in order by turning the camera toward
## each one and holding forward. False if a point isn't reached in time.
func _walk_to(points: Array, sprint := false, timeout := 10.0) -> bool:
	for target: Vector3 in points:
		var frames := int(timeout * 60.0)
		var reached := false
		while frames > 0:
			var d := Vector3(target.x - player.global_position.x, 0.0, target.z - player.global_position.z)
			if d.length() < 0.35:
				reached = true
				break
			player.camera.yaw = atan2(-d.x, -d.z)
			Input.action_press(&"move_forward")
			if sprint:
				Input.action_press(&"sprint")
			frames -= 1
			await physics_frame
		if not reached:
			_release_all()
			return false
	_release_all()
	await _phys(20)
	return true


## Sprints straight ahead from `start` for `distance` metres.
func _sprint_line(start: Vector3, yaw: float, distance: float) -> Dictionary:
	await _place(start, yaw)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(20)
	var slowest := INF
	var frames := int((distance / settings.sprint_speed + 3.0) * 60.0)
	while frames > 0 and Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() < distance:
		slowest = minf(slowest, player.horizontal_speed())
		frames -= 1
		await physics_frame
	_release_all()
	return {distance = Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length(), slowest = slowest}


## Sprints from `start`, jumps once `jump_when` is true, holds forward until
## landing. True if landed within 3 s.
func _run_and_land(start: Vector3, yaw: float, jump_when: Callable) -> bool:
	await _place(start, yaw)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(jump_when, 3.0)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return not player.is_on_floor(), 0.5)
	var landed := await _wait_until(func() -> bool: return player.is_on_floor() and player.state == Player.State.MOVE, 3.0)
	_release_all()
	await _phys(5)
	return landed


## From `pos` inside a room facing `yaw`: E through the window ahead, then
## grapple `anchor` from the fall.
func _dive_out_and_grapple(pos: Vector3, yaw: float, anchor: GrappleAnchor, expect_slow := true,
		hold_toward := false) -> Dictionary:
	var out := {dove = false, airborne = false, slow = false, arrived = false, pos = Vector3.ZERO}
	await _place(pos, yaw)
	var slow := [false]
	var on_slow := func() -> void: slow[0] = true
	player.bullet_time.started.connect(on_slow)
	Input.action_press(&"move_forward")
	await _phys(2)
	await _tap(&"traverse")
	out.dove = await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 1.0)
	Input.action_release(&"move_forward")
	await _wait_until(func() -> bool: return player.state != Player.State.TRAVERSAL, 2.0)
	await _phys(2)
	out.airborne = not player.is_on_floor() and player.state == Player.State.MOVE
	var r := await _grapple_to(anchor, hold_toward)
	player.bullet_time.started.disconnect(on_slow)
	out.slow = slow[0] or not expect_slow
	out.arrived = r.arrived
	out.pos = r.landed
	return out


## Fires at `anchor` (once the arrow is nocked) and waits for the landing.
## `hold_toward` keeps W held after firing and climbs up from a caught ledge
## (a pull the world stopped short of it).
func _grapple_to(anchor: GrappleAnchor, hold_toward := false) -> Dictionary:
	var out := {seen = false, arrived = false, landed = Vector3.ZERO, on_floor = false, clear = false}
	await _wait_until(func() -> bool: return player.grapple.is_ready(), 1.5)
	_aim_at(anchor.global_position)
	await _phys(2)
	out.seen = player.grapple.target == anchor
	var done := [false]
	var on_finish := func(arrived: bool) -> void:
		out.arrived = arrived
		done[0] = true
	player.grapple_finished.connect(on_finish)
	await _tap(&"grapple")
	if hold_toward:
		Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return done[0], 5.0)
	player.grapple_finished.disconnect(on_finish)
	if hold_toward and not out.arrived:
		if await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 1.5):
			await _tap(&"jump")
		_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	await _phys(5)
	out.landed = player.global_position
	out.on_floor = player.is_on_floor()
	out.clear = player.sensor.has_clearance(player.global_position, settings.standing_height)
	return out


## Breadth-first fill over open cells from `start`; returns the cells reached.
## Neighbours connect if both are open and nothing (a thin wall, a fence)
## stands between them at knee or head height.
func _flood(open: PackedByteArray, seen: PackedByteArray, start: int, nx: int, nz: int, x0: float, z0: float) -> int:
	var space := player.get_world_3d().direct_space_state
	var queue := [start]
	seen[start] = 1
	var count := 0
	while not queue.is_empty():
		var idx: int = queue.pop_back()
		count += 1
		var i := floori(float(idx) / nz)
		var j := idx % nz
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + step.x
			var nj := j + step.y
			if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
				continue
			var nidx := ni * nz + nj
			if open[nidx] == 0 or seen[nidx] == 1:
				continue
			var a := Vector3(x0 + i, 0.0, z0 + j)
			var b := Vector3(x0 + ni, 0.0, z0 + nj)
			var blocked := false
			for h: float in [0.4, 1.4]:
				var ray := PhysicsRayQueryParameters3D.create(a + Vector3.UP * h, b + Vector3.UP * h, 1)
				if not space.intersect_ray(ray).is_empty():
					blocked = true
			if blocked:
				continue
			seen[nidx] = 1
			queue.append(nidx)
	return count


## Points the camera (and so the grapple aim) straight at `point`.
func _aim_at(point: Vector3) -> void:
	var cam := player.camera
	var d := point - cam.global_position
	cam.yaw = atan2(-d.x, -d.z)
	cam.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(cam.min_pitch_degrees), deg_to_rad(cam.max_pitch_degrees))


func _mouse_button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)


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
	await _phys(8)


func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits (game time) until cond() is true; returns false on timeout.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var frames := int(timeout * 60.0)
	while frames > 0:
		if cond.call():
			return true
		frames -= 1
		await physics_frame
	return cond.call()


func _shot(file: String) -> void:
	if shots_dir == "":
		return
	await _frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots_dir.path_join(file + ".png"))


func _section(title: String) -> void:
	print("\n-- %s --" % title)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])
