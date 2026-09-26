extends SceneTree
## Automated movement checks that drive the real main scene through the Input
## system (same code path as a keyboard).
##
## Run headless:
##   godot --headless --path . -s res://tests/movement_test.gd
## Also save screenshots (needs a window, so no --headless):
##   godot --path . -s res://tests/movement_test.gd -- --shots=C:/some/dir

const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"sprint", &"jump", &"crouch", &"traverse"]
## Real keys for movement actions, sent as key events like a keyboard would.
const KEY_FOR := {&"move_forward": KEY_W, &"move_left": KEY_A, &"move_back": KEY_S,
		&"move_right": KEY_D, &"jump": KEY_SPACE, &"traverse": KEY_E}

var player: Player
var settings: MovementSettings
var front_window: TraversalWindow
var shots_dir := ""
var passed := 0
var failed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	settings = player.settings
	front_window = main.get_node("MovementTestLevel/Building/FrontWindow")
	_run.call_deferred()


func _run() -> void:
	await _phys(30)
	await test_spawn()
	await test_resolution()
	await test_walk_sprint_stop()
	await test_camera_relative()
	await test_jump()
	await test_crouch()
	await test_camera()
	await test_player_collision()
	await test_vaults()
	await test_ledges()
	await test_slow_time()
	await test_windows()
	await test_character()
	await test_gaps_and_ramp()
	await test_respawn()
	print("\n==== %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)


# --- Tests -------------------------------------------------------------------

func test_spawn() -> void:
	_section("Spawn")
	_check("player on floor after spawn", player.is_on_floor())
	_check("spawned at marker", player.global_position.distance_to(Vector3(0, 0, 10)) < 0.2,
			str(player.global_position))
	await _shot("01_spawn")


func test_walk_sprint_stop() -> void:
	_section("Walk / sprint / accel / stop")
	await _place(Vector3(0, 0, 10), 0.0)
	Input.action_press(&"move_forward")
	var t90 := await _time_until(func() -> bool: return player.horizontal_speed() >= settings.walk_speed * 0.9, 1.0)
	await _phys(30)
	var walk := player.horizontal_speed()
	_check("walk reaches %.1f m/s" % settings.walk_speed, absf(walk - settings.walk_speed) < 0.2, "%.2f" % walk)
	_check("walk accel to 90%% under 0.15 s", t90 >= 0.0 and t90 < 0.15, "%.3f s" % t90)
	var dir := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
	_check("forward = -Z with camera yaw 0", dir.dot(Vector3.FORWARD) > 0.99, str(dir))

	Input.action_press(&"sprint")
	var ts := await _time_until(func() -> bool: return player.horizontal_speed() >= settings.sprint_speed * 0.95, 1.0)
	await _phys(20)
	_check("sprint reaches %.1f m/s" % settings.sprint_speed, absf(player.horizontal_speed() - settings.sprint_speed) < 0.2,
			"%.2f (%.3f s to 95%%)" % [player.horizontal_speed(), ts])
	_check("player.is_sprinting", player.is_sprinting)
	await _shot("02_sprint")

	var start := player.global_position
	_release_all()
	var tstop := await _time_until(func() -> bool: return player.horizontal_speed() < 0.05, 1.0)
	var slide := start.distance_to(player.global_position)
	_check("stops from sprint under 0.3 s", tstop >= 0.0 and tstop < 0.3, "%.3f s, slid %.2f m" % [tstop, slide])


func test_camera_relative() -> void:
	_section("Camera-relative movement + rotation")
	await _place(Vector3(0, 0, 10), 0.0)
	player.camera.yaw = deg_to_rad(90.0) # camera now looks toward -X
	Input.action_press(&"move_forward")
	await _phys(40)
	var dir := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
	_check("W moves toward camera forward (-X)", dir.dot(Vector3.LEFT) > 0.99, str(dir))
	_check("body turned to face movement", absf(angle_difference(player.rotation.y, deg_to_rad(90.0))) < 0.05,
			"%.1f deg" % rad_to_deg(player.rotation.y))
	Input.action_release(&"move_forward")
	Input.action_press(&"move_right")
	await _phys(30)
	dir = Vector3(player.velocity.x, 0, player.velocity.z).normalized()
	_check("D moves toward camera right (-Z)", dir.dot(Vector3.FORWARD) > 0.98, str(dir))
	_release_all()
	player.camera.yaw = 0.0


func test_jump() -> void:
	_section("Jump / land")
	await _place(Vector3(0, 0, 10), 0.0)
	var base := player.global_position.y
	var landed := [false, 0.0]
	var on_land := func(speed: float) -> void:
		landed[0] = true
		landed[1] = speed
	player.landed.connect(on_land)
	Input.action_press(&"jump")
	var peak := base
	var frames := 0
	await _phys(2)
	while not player.is_on_floor() and frames < 120:
		peak = maxf(peak, player.global_position.y)
		frames += 1
		await physics_frame
	Input.action_release(&"jump")
	var apex := peak - base
	_check("full jump height ~%.2f m" % settings.jump_height, absf(apex - settings.jump_height) < 0.1, "%.2f m" % apex)
	_check("airtime under 0.7 s (snappy, not floaty)", frames / 60.0 < 0.7, "%.2f s" % (frames / 60.0))
	_check("landed signal fired", landed[0], "impact %.1f m/s" % landed[1])
	player.landed.disconnect(on_land)

	# Short tap -> lower jump (variable height).
	await _phys(10)
	Input.action_press(&"jump")
	await _phys(3)
	Input.action_release(&"jump")
	peak = base
	frames = 0
	while (frames < 5 or not player.is_on_floor()) and frames < 120:
		peak = maxf(peak, player.global_position.y)
		frames += 1
		await physics_frame
	_check("tapped jump is lower (variable height)", peak - base < apex - 0.3, "%.2f m" % (peak - base))

	# Jump buffer: press slightly before landing.
	await _phys(10)
	Input.action_press(&"jump")
	await _phys(2)
	Input.action_release(&"jump")
	await _wait_until(func() -> bool: return player.velocity.y < 0.0 and player.global_position.y < base + 0.35, 2.0)
	Input.action_press(&"jump")
	await _phys(2)
	Input.action_release(&"jump")
	var rejumped := await _wait_until(func() -> bool: return player.velocity.y > 3.0, 0.5)
	_check("buffered jump fires on landing", rejumped)
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)

	# Sprint-jump distance.
	await _place(Vector3(20, 0, 30), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(40)
	var takeoff := player.global_position
	Input.action_press(&"jump")
	await _phys(3)
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	_release_all()
	var dist := Vector2(player.global_position.x - takeoff.x, player.global_position.z - takeoff.z).length()
	_check("sprint jump covers 4.5-6.5 m", dist > 4.5 and dist < 6.5, "%.2f m" % dist)


func test_crouch() -> void:
	_section("Crouch")
	await _place(Vector3(20, 0, 20), 0.0)
	Input.action_press(&"crouch")
	Input.action_press(&"move_forward")
	await _phys(40)
	var shape: CapsuleShape3D = (player.get_node("CollisionShape3D") as CollisionShape3D).shape
	_check("crouch shrinks collider", player.is_crouching and is_equal_approx(shape.height, settings.crouch_height))
	_check("crouch speed ~%.1f" % settings.crouch_speed, absf(player.horizontal_speed() - settings.crouch_speed) < 0.15,
			"%.2f" % player.horizontal_speed())
	Input.action_press(&"sprint")
	await _phys(10)
	_check("cannot sprint while crouched", not player.is_sprinting)
	_release_all()
	await _phys(5)
	_check("stands back up in the open", not player.is_crouching and is_equal_approx(shape.height, settings.standing_height))

	# Tunnel: roof at 1.3 m blocks standing.
	await _place(Vector3(16.15, 0, 11.5), 0.0)
	Input.action_press(&"crouch")
	Input.action_press(&"move_forward")
	await _phys(50)
	Input.action_release(&"crouch")
	await _phys(10)
	_check("stays crouched under tunnel roof", player.is_crouching, "z=%.2f" % player.global_position.z)
	await _shot("03_crouch_tunnel")
	await _wait_until(func() -> bool: return not player.is_crouching, 3.0)
	_check("stands automatically after leaving tunnel", not player.is_crouching and player.global_position.z < 6.2,
			"z=%.2f" % player.global_position.z)
	_release_all()


func test_camera() -> void:
	_section("Camera")
	var cam := player.camera
	await _place(Vector3(0, 0, 10), 0.0)
	cam.add_look_input(Vector2(0, 100000))
	_check("pitch clamps at lower limit", is_equal_approx(cam.pitch, deg_to_rad(cam.min_pitch_degrees)))
	cam.add_look_input(Vector2(0, -100000))
	_check("pitch clamps at upper limit", is_equal_approx(cam.pitch, deg_to_rad(cam.max_pitch_degrees)))
	cam.pitch = deg_to_rad(-12)
	var yaw_before := cam.yaw
	cam.add_look_input(Vector2(200, 0))
	_check("mouse X orbits yaw", absf(cam.yaw - yaw_before) > 0.3)
	cam.yaw = 0.0
	await _frames(20)
	_check("unobstructed boom uses full distance", cam.boom_fraction > 0.98, "%.2f" % cam.boom_fraction)

	# Back against the tall wall (face at x = 11.5), camera behind = +X.
	await _place(Vector3(10.9, 0, -3), 0.0)
	cam.yaw = deg_to_rad(90.0)
	await _frames(20)
	var cam_x := cam.camera.global_position.x
	_check("camera pulled in by wall", cam.boom_fraction < 0.5, "fraction %.2f" % cam.boom_fraction)
	_check("camera stays in front of wall", cam_x < 11.5 - 0.1, "cam x %.2f" % cam_x)
	_check("body hidden while camera is pressed close", cam.camera.cull_mask & 2 == 0)
	await _shot("04_camera_wall")
	cam.yaw = 0.0
	await _place(Vector3(0, 0, 10), 0.0)
	await _frames(60)
	_check("camera eases back out", cam.boom_fraction > 0.95, "%.2f" % cam.boom_fraction)
	_check("body visible again", cam.camera.cull_mask & 2 != 0)


func test_player_collision() -> void:
	_section("Player collision")
	await _place(Vector3(9.0, 0, -1), -90.0) # facing +X toward tall wall
	player.camera.yaw = deg_to_rad(-90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(60)
	var x := player.global_position.x
	_check("blocked by wall (no tunnelling)", x < 11.5 - 0.3 and x > 10.9, "x=%.3f" % x)
	_check("no speed into wall", absf(player.velocity.x) < 0.2, "vx=%.2f" % player.velocity.x)
	_check("no vault/climb on 7 m wall", player.state == Player.State.MOVE)
	_release_all()
	player.camera.yaw = 0.0


func test_vaults() -> void:
	_section("Vault detection")
	# Auto vault over 1.0 m wall at z=-6 while sprinting.
	await _place(Vector3(-7, 0, -1.8), 0.0)
	var ids := _record_traversals()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -7.5, 2.0)
	_check("sprint auto-vaults 1.0 m wall", ids.has(&"vault_over"), str(ids))
	_check("kept momentum after vault", player.horizontal_speed() > 7.0, "%.2f m/s" % player.horizontal_speed())
	_release_all()

	# Sprint over the 0.4 m hurdle.
	await _place(Vector3(-7, 0, 8), 0.0)
	ids.clear()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 3.0, 2.0)
	_check("sprint vaults 0.4 m hurdle", ids.has(&"vault_over"), str(ids))
	_release_all()

	# Walking + Jump next to the 1.2 m wall = manual vault.
	await _place(Vector3(-7, 0, -9.9), 0.0)
	ids.clear()
	Input.action_press(&"move_forward")
	await _phys(6)
	Input.action_press(&"jump")
	await _phys(3)
	Input.action_release(&"jump")
	await _shot("05_vault_mid", 8)
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.global_position.z < -11.5, 2.0)
	_check("jump near 1.2 m wall vaults over", ids.has(&"vault_over") and player.global_position.z < -11.5,
			"%s z=%.2f" % [ids, player.global_position.z])
	_release_all()

	# Sprint into the deep crate = vault onto.
	await _place(Vector3(-7, 0, -12.2), 0.0)
	ids.clear()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return ids.has(&"vault_onto") and player.state == Player.State.MOVE, 2.0)
	await _phys(3)
	_check("deep crate -> vault onto", ids.has(&"vault_onto"), str(ids))
	_check("standing on crate top (y≈1.0)", absf(player.global_position.y - 1.0) < 0.1, "y=%.2f" % player.global_position.y)
	_release_all()

	# Walking into an obstacle without jumping must NOT vault.
	await _place(Vector3(-7, 0, -3.5), 0.0)
	ids.clear()
	Input.action_press(&"move_forward")
	await _phys(60)
	_check("walking into wall does not auto-vault", ids.is_empty() and player.global_position.z > -5.8, str(ids))
	_release_all()
	_stop_recording()


func test_ledges() -> void:
	_section("Ledge detection / grab / climb")
	var ids := _record_traversals()
	# 2.6 m wall: jump -> hang.
	await _place(Vector3(4.6, 0, -3), -90.0)
	player.camera.yaw = deg_to_rad(-90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	var hung := await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 1.5)
	Input.action_release(&"jump")
	_check("jump at 2.6 m wall grabs ledge", hung, "state %s last %s" % [Player.State.keys()[player.state], player.last_action])
	Input.action_release(&"move_forward")
	await _phys(20)
	if hung:
		_check("hangs below edge (feet ≈ 0.65)", absf(player.global_position.y - 0.65) < 0.08, "y=%.2f" % player.global_position.y)
		await _shot("06_ledge_hang")
		var z0 := player.global_position.z
		Input.action_press(&"move_right") # camera faces +X, right = +Z
		await _phys(30)
		Input.action_release(&"move_right")
		_check("shimmies along ledge", absf(player.global_position.z - z0) > 0.3, "dz=%.2f" % (player.global_position.z - z0))
		Input.action_press(&"jump")
		await _phys(2)
		Input.action_release(&"jump")
		await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
		await _phys(5)
		_check("climbs up onto the wall (y≈2.6)", ids.has(&"climb_up") and absf(player.global_position.y - 2.6) < 0.1,
				"%s y=%.2f" % [ids, player.global_position.y])

	# 3.2 m wall: grab, then drop with crouch.
	await _place(Vector3(4.6, 0, -9), -90.0)
	player.camera.yaw = deg_to_rad(-90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	hung = await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 1.5)
	_release_all()
	_check("jump at 3.2 m wall grabs ledge", hung)
	await _phys(10)
	Input.action_press(&"crouch")
	await _phys(2)
	Input.action_release(&"crouch")
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	_check("crouch drops from ledge safely", player.state == Player.State.MOVE and player.global_position.y < 0.1)

	# 1.8 m wall: too low to hang -> mantle straight up.
	ids.clear()
	await _place(Vector3(4.6, 0, 3), -90.0)
	player.camera.yaw = deg_to_rad(-90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return ids.has(&"mantle") and player.state == Player.State.MOVE, 1.5)
	_release_all()
	await _phys(5)
	_check("1.8 m wall -> mantle onto top", ids.has(&"mantle") and absf(player.global_position.y - 1.8) < 0.1,
			"%s y=%.2f" % [ids, player.global_position.y])
	player.camera.yaw = 0.0

	# Crate steps up to the building roof: 1.0 -> 2.1 -> 3.9.
	ids.clear()
	await _place(Vector3(-6.1, 2.1, -30.0), -90.0)
	player.camera.yaw = deg_to_rad(-90.0)
	await _phys(5)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.global_position.y > 3.8 and player.state == Player.State.MOVE, 2.0)
	_release_all()
	_check("crate -> roof ledge climb", player.global_position.y > 3.8, "%s y=%.2f" % [ids, player.global_position.y])
	player.camera.yaw = 0.0
	_stop_recording()


func test_slow_time() -> void:
	_section("Slow time (Space)")
	var bt := player.bullet_time

	# Space on the ground is still a jump and never slows time.
	await _place(Vector3(20, 0, 20), 0.0)
	_key_event(&"jump", true)
	var jumped := await _wait_until(func() -> bool: return player.velocity.y > 3.0, 0.3)
	_key_event(&"jump", false)
	_check("Space on the ground jumps", jumped)
	_check("ground jump does not start slow time", not bt.active and is_equal_approx(Engine.time_scale, 1.0))
	# Space again at the apex of a normal jump (low over the ground): no slow time.
	await _wait_until(func() -> bool: return player.velocity.y < 0.5, 1.0)
	await _tap(&"jump")
	await _phys(2)
	_check("Space mid normal jump does not start slow time", not bt.active)
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)

	# Space in the air with a real drop below: slow time starts.
	var at_end := {fov = 0.0, usec = 0}
	var on_end := func() -> void:
		at_end.fov = player.camera.camera.fov
		at_end.usec = Time.get_ticks_usec()
	bt.ended.connect(on_end)
	await _drop_off_roof()
	var start := {usec = 0}
	var on_start := func() -> void: start.usec = Time.get_ticks_usec()
	bt.started.connect(on_start)
	await _tap(&"jump")
	await _phys(1)
	_check("Space in the air (roof drop) starts slow time", bt.active and player.last_action == &"slow_time",
			"last %s" % player.last_action)
	_check("slow time uses the existing 0.3x slow-down", is_equal_approx(Engine.time_scale, bt.time_scale), "%.2f" % Engine.time_scale)
	_check("slow time duration is %.1f s" % bt.duration, is_equal_approx(bt.duration, 0.4), "%.2f" % bt.duration)
	await _real_until(func() -> bool: return not bt.active, bt.duration + 1.0)
	var lasted: float = (at_end.usec - start.usec) / 1_000_000.0
	_check("slowdown lasts ~0.4 s real", absf(lasted - bt.duration) < 0.05, "%.3f s" % lasted)
	_check("camera FOV tightens during slow time", at_end.fov < player.camera.base_fov - 2.0, "fov %.1f at the end" % at_end.fov)
	_check("slow time ends by itself (time scale back to 1)", not bt.active and is_equal_approx(Engine.time_scale, 1.0))
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	_check("lands normally after slow time ends mid-fall", player.is_on_floor() and player.state == Player.State.MOVE)
	await _phys(40)
	_check("camera FOV returns to normal", absf(player.camera.camera.fov - lerpf(player.camera.base_fov, player.camera.sprint_fov,
			player.camera.speed_amount)) < 1.0, "%.1f" % player.camera.camera.fov)

	# Recharging: Space in the air does nothing until the cooldown is over.
	_check("not ready straight after (recharging %.1f s)" % bt.cooldown, not bt.is_ready() and bt.cooldown_left() > bt.cooldown - 1.5,
			"%.1f s left" % bt.cooldown_left())
	await _drop_off_roof(false)
	await _tap(&"jump")
	await _phys(2)
	_check("Space in the air while recharging: no slow time", not bt.active)
	await _real_until(func() -> bool: return bt.is_ready(), bt.cooldown + 1.0)
	_check("ready again after the cooldown", bt.is_ready())
	await _drop_off_roof(false)
	await _tap(&"jump")
	await _phys(1)
	_check("can use it again once recharged", bt.active)
	await _real_until(func() -> bool: return not bt.active, bt.duration + 1.0)
	lasted = (at_end.usec - start.usec) / 1_000_000.0
	_check("second use also lasts ~0.4 s and ends by itself", absf(lasted - bt.duration) < 0.05
			and is_equal_approx(Engine.time_scale, 1.0), "%.3f s" % lasted)
	bt.started.disconnect(on_start)
	bt.ended.disconnect(on_end)
	# Normal movement and jumping afterwards.
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	Input.action_press(&"move_forward")
	await _phys(40)
	var walk := player.horizontal_speed()
	Input.action_release(&"move_forward")
	_check("walking works normally afterwards", absf(walk - settings.walk_speed) < 0.2, "%.2f" % walk)
	await _phys(5)
	_key_event(&"jump", true)
	jumped = await _wait_until(func() -> bool: return player.velocity.y > 3.0, 0.3)
	_key_event(&"jump", false)
	_check("Space on the ground still jumps normally", jumped and not bt.active)


## Walks off the building's front roof edge (3.9 m) and returns once the
## player is falling clear of it. `fresh` = teleport (also recharges slow
## time); otherwise just reposition so the cooldown is kept.
func _drop_off_roof(fresh := true) -> void:
	var start := Vector3(3.0, 3.95, -27.0)
	if fresh:
		await _place(start, 180.0)
	else:
		_release_all()
		player.global_position = start
		player.velocity = Vector3.ZERO
		player.rotation.y = PI
		player.camera.yaw = PI
		player.reset_physics_interpolation()
		await _phys(8)
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return not player.is_on_floor() and player.global_position.y < 3.0, 3.0)
	Input.action_release(&"move_forward")


func test_windows() -> void:
	_section("Window traversal: E to dive")
	var ids := _record_traversals()
	var cam := player.camera
	var bt := player.bullet_time
	var wall_z := front_window.global_position.z
	var prompt := player.prompt

	# No QTE anywhere in the player any more.
	_check("QTE traversal code deleted", not ResourceLoader.exists("res://scripts/parkour/traversal_qte.gd")
			and not ResourceLoader.exists("res://scripts/parkour/qte_prompt.gd"))

	# Without E nothing happens: walking, sprinting, jumping into the window.
	ids.clear()
	await _place(Vector3(0, 0, wall_z + 4.0), 0.0)
	Input.action_press(&"move_forward")
	await _phys(60)
	_release_all()
	_check("walk into the window without E: no traversal", ids.is_empty() and player.global_position.z > wall_z, str(ids))
	ids.clear()
	await _place(Vector3(0, 0, wall_z + 10.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(90)
	_release_all()
	_check("sprint into the window without E: no traversal", ids.is_empty() and player.global_position.z > wall_z
			and player.state == Player.State.MOVE, "%s z=%.2f" % [ids, player.global_position.z])
	ids.clear()
	await _place(Vector3(0, 0, wall_z + 2.0), 0.0)
	Input.action_press(&"move_forward")
	await _phys(4)
	_key_event(&"jump", true)
	await _phys(3)
	_key_event(&"jump", false)
	await _phys(50)
	_release_all()
	_check("jump into the window without E: no traversal", ids.is_empty() and player.global_position.z > wall_z,
			"%s z=%.2f" % [ids, player.global_position.z])
	ids.clear()
	await _place(Vector3(0, 0, wall_z + 10.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < wall_z + 2.5, 2.0)
	_key_event(&"jump", true)
	await _phys(3)
	_key_event(&"jump", false)
	await _phys(50)
	_release_all()
	_check("sprint-jump into the window without E: no traversal", ids.is_empty() and player.global_position.z > wall_z,
			"%s z=%.2f" % [ids, player.global_position.z])

	# The prompt: "[E] DIVE THROUGH" only where E works.
	await _place(Vector3(0, 0, wall_z + 2.5), 0.0)
	await _phys(3)
	_check("lined up outside within range: prompt shows E DIVE THROUGH", prompt.hint_text() == "E DIVE THROUGH", "'%s'" % prompt.hint_text())
	await _shot("12_e_prompt")
	await _place(Vector3(0, 0, wall_z - 2.5), 180.0)
	await _phys(3)
	_check("lined up inside within range: prompt shows too", prompt.hint_text() == "E DIVE THROUGH", "'%s'" % prompt.hint_text())
	await _place(Vector3(0, 0, wall_z + 5.0), 0.0)
	await _phys(3)
	_check("too far away: no prompt", prompt.hint_text() == "", "'%s'" % prompt.hint_text())
	await _place(Vector3(0, 0, wall_z + 2.5), 180.0)
	await _phys(3)
	_check("facing away: no prompt", prompt.hint_text() == "", "'%s'" % prompt.hint_text())
	await _place(Vector3(3.5, 0, wall_z + 2.5), 0.0)
	await _phys(3)
	_check("off to the side (not lined up): no prompt", prompt.hint_text() == "", "'%s'" % prompt.hint_text())
	_check("no SHIFT or SPACE traversal prompt", not prompt.hint_text().begins_with("SHIFT") and not prompt.hint_text().begins_with("SPACE"))

	# Out of range + E does nothing at the window.
	ids.clear()
	await _place(Vector3(0, 0, wall_z + 5.0), 0.0)
	await _tap(&"traverse")
	await _phys(30)
	_check("E out of range: nothing happens", ids.is_empty() and player.state == Player.State.MOVE, str(ids))

	# E dives through: outside -> inside, from a normal distance (standing).
	ids.clear()
	var r := await _window_run({start = Vector3(0, 0, wall_z + 2.8), mid_shot = "09_window_dive"})
	_check("outside, E at 2.8 m (standing): dives IN", r.started and ids.has(&"window_dive") and r.inside, "%s end %s" % [ids, r.end])
	_check("no momentum needed: dives at sprint pace", r.entry_speed >= settings.sprint_speed - 0.01, "%.2f m/s" % r.entry_speed)
	_check("dive keeps its cinematic slow time (0.3x)", r.slow_during and is_equal_approx(r.slowmo, bt.time_scale), "%.2f" % r.slowmo)
	_check("camera FOV tightened during the dive slow time", r.fov_during > 0.0 and r.fov_during < cam.sprint_fov - 3.0, "fov %.1f" % r.fov_during)
	_check("dive exits with momentum", r.exit_speed > settings.sprint_speed, "%.2f m/s" % r.exit_speed)
	_check("prompt hidden during the dive", r.hint_during == "", "'%s'" % r.hint_during)
	await _real_until(func() -> bool: return not bt.active, bt.duration + 1.0)
	_check("slow time ends by itself after the dive", is_equal_approx(Engine.time_scale, 1.0))
	_key_event(&"move_left", true)
	await _phys(30)
	var dir := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
	_key_event(&"move_left", false)
	_check("A moves normally afterwards", dir.dot(Vector3.LEFT) > 0.95 and player.state == Player.State.MOVE, str(dir))
	await _phys(10)
	_key_event(&"jump", true)
	var jumped := await _wait_until(func() -> bool: return player.velocity.y > 3.0, 0.3)
	_key_event(&"jump", false)
	_check("Space jumps normally afterwards", jumped)
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)

	# Close range, and while running at it.
	ids.clear()
	r = await _window_run({start = Vector3(0, 0, wall_z + 0.9)})
	_check("outside, E right at the window: dives IN", r.started and ids.has(&"window_dive") and r.inside, "%s end %s" % [ids, r.end])
	_check("close start never steps backwards", r.takeoff_dist <= 0.95, "took off %.2f m out" % r.takeoff_dist)
	ids.clear()
	r = await _window_run({start = Vector3(0, 0, wall_z + 10.0), approach = "sprint"})
	_check("outside, sprinting at it + E: dives IN", r.started and ids.has(&"window_dive") and r.inside, "%s end %s" % [ids, r.end])

	# Inside -> outside.
	ids.clear()
	r = await _window_run({start = Vector3(0, 0, wall_z - 2.8), yaw = 180.0, mid_shot = "13_dive_out"})
	_check("inside, E at 2.8 m: dives OUT", r.started and ids.has(&"window_dive") and r.outside, "%s end %s" % [ids, r.end])
	ids.clear()
	r = await _window_run({start = Vector3(0, 0, wall_z - 0.9), yaw = 180.0})
	_check("inside, E right at the window: dives OUT", r.started and ids.has(&"window_dive") and r.outside, "%s end %s" % [ids, r.end])
	ids.clear()
	r = await _window_run({start = Vector3(0, 0, -33.3), yaw = 180.0, approach = "sprint"})
	_check("inside, sprinting across the room + E: dives OUT", r.started and ids.has(&"window_dive") and r.outside, "%s end %s" % [ids, r.end])

	# E elsewhere keeps its normal parkour meaning.
	ids.clear()
	await _place(Vector3(-7, 0, -4.8), 0.0)
	Input.action_press(&"move_forward")
	await _phys(6)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and ids.size() > 0, 2.0)
	_release_all()
	_check("E at a waist-high wall still vaults", ids.has(&"vault_over"), str(ids))

	# The back window is a plain window and keeps its behaviour.
	ids.clear()
	await _place(Vector3(2.0, 0, -29.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -35.0 and player.state == Player.State.MOVE, 3.0)
	_release_all()
	_check("back window: sprinting into it still vaults", ids.has(&"window_vault") and player.global_position.z < -34.0,
			"%s z=%.2f" % [ids, player.global_position.z])
	ids.clear()
	await _place(Vector3(2.0, 0, -30.5), 0.0)
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return player.global_position.z < -32.3, 2.0)
	await _tap(&"traverse")
	_release_all()
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and ids.size() > 0, 3.0)
	_check("back window: walking + E still vaults", ids.has(&"window_vault") and player.global_position.z < -34.0,
			"%s z=%.2f" % [ids, player.global_position.z])

	# Diagonal jump / E at the front sill cannot vault it either.
	ids.clear()
	await _place(Vector3(-0.9, 0, wall_z + 0.85), -45.0)
	player.camera.yaw = deg_to_rad(-45.0)
	Input.action_press(&"move_forward")
	await _phys(6)
	Input.action_press(&"jump")
	await _phys(3)
	Input.action_release(&"jump")
	await _phys(40)
	Input.action_press(&"traverse")
	await _phys(3)
	_release_all()
	await _phys(30)
	player.camera.yaw = 0.0
	_check("diagonal jump / E at the sill: no vault through", ids.is_empty() and player.global_position.z > wall_z,
			"%s z=%.2f" % [ids, player.global_position.z])
	_stop_recording()


## Presses E at the front window and follows the dive.
## opts: start / yaw = where to begin, approach = "stand" (default, just
## press E) | "sprint" (sprint at it, press E once within 2.5 m),
## mid_shot = screenshot name.
func _window_run(opts := {}) -> Dictionary:
	var out := {started = false, slow_during = false, slowmo = 1.0, fov_during = 0.0, hint_during = "x",
			inside = false, outside = false, end = Vector3.ZERO, entry_speed = 0.0, exit_speed = 0.0, takeoff_dist = 0.0}
	await _place(opts.get("start", Vector3(0, 0, -23.35)), opts.get("yaw", 0.0))
	var on_start := func(_id: StringName) -> void:
		out.takeoff_dist = front_window.distance_to_wall(player.global_position)
		out.slow_during = player.bullet_time.active
		out.slowmo = Engine.time_scale
	var on_slow_end := func() -> void: out.fov_during = player.camera.camera.fov
	player.traversal_started.connect(on_start)
	player.bullet_time.ended.connect(on_slow_end)
	if opts.get("approach", "stand") == "sprint":
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		await _wait_until(func() -> bool: return front_window.distance_to_wall(player.global_position) < 2.5, 3.0)
	await _tap(&"traverse")
	out.started = await _wait_until(func() -> bool: return player.state != Player.State.MOVE, 1.0)
	if out.started:
		out.entry_speed = player._approach_entry_speed
	await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 3.0)
	out.hint_during = player.prompt.hint_text()
	if opts.has("mid_shot"):
		await _shot(opts.mid_shot, 12)
	await _wait_until(func() -> bool: return player.state != Player.State.TRAVERSAL, 3.0)
	out.exit_speed = player.horizontal_speed()
	player.traversal_started.disconnect(on_start)
	player.bullet_time.ended.disconnect(on_slow_end)
	_release_all()
	await _phys(20)
	out.end = player.global_position
	var settled: bool = absf(out.end.y) < 0.1 and player.state == Player.State.MOVE
	out.inside = settled and out.end.z < -26.5 and out.end.z > -33.7
	out.outside = settled and out.end.z > front_window.global_position.z + 0.5
	return out


func test_character() -> void:
	_section("Vigilante character model (static)")
	var model := player.get_node_or_null("Visual/Pivot/VigilanteModel") as Node3D
	_check("Vigilante model is in the player scene", model != null)
	if model == null:
		return
	_check("placeholder capsule/visor removed", player.get_node_or_null("Visual/Pivot/Body") == null
			and player.get_node_or_null("Visual/Pivot/Visor") == null)
	_check("model has no collision of its own", model.find_children("*", "CollisionObject3D", true, false).is_empty())
	var shape: CapsuleShape3D = (player.get_node("CollisionShape3D") as CollisionShape3D).shape
	_check("gameplay capsule unchanged (r 0.35, h 1.8)", is_equal_approx(shape.radius, 0.35) and is_equal_approx(shape.height, 1.8))
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	_check("model meshes on the camera-hide layer", meshes.all(func(m: MeshInstance3D) -> bool: return m.layers == 2), "%d meshes" % meshes.size())

	await _place(Vector3(20, 0, 20), 0.0)
	await _phys(20)
	var box := _model_aabb(model)
	var feet := player.global_position.y
	_check("feet on the ground (no float / sink)", absf(box.position.y - feet) < 0.03, "model bottom %.3f vs feet %.3f" % [box.position.y, feet])
	_check("real-world scale (~1.85 m tall)", absf(box.size.y - 1.848) < 0.05, "%.2f m" % box.size.y)

	# Faces the way the player faces: eyes in front of the body.
	var eyes := (model.find_child("eye_lens_L", true, false) as Node3D).global_position
	var forward := -player.global_basis.z
	var eye_offset := Vector3(eyes.x - player.global_position.x, 0, eyes.z - player.global_position.z)
	_check("model faces the player's forward direction", eye_offset.dot(forward) > 0.05, "eye offset %.2f" % eye_offset.dot(forward))
	Input.action_press(&"move_left")
	await _phys(40)
	Input.action_release(&"move_left")
	eyes = (model.find_child("eye_lens_L", true, false) as Node3D).global_position
	eye_offset = Vector3(eyes.x - player.global_position.x, 0, eyes.z - player.global_position.z)
	_check("turns with movement (faces -X after moving left)", eye_offset.dot(Vector3.LEFT) > 0.05, "%.2f" % eye_offset.dot(Vector3.LEFT))

	# In frame for the camera.
	await _place(Vector3(20, 0, 20), 0.0)
	await _frames(10)
	var head := (model.find_child("head", true, false) as Node3D).global_position + Vector3.UP * 0.1
	var boot := (model.find_child("boot_L", true, false) as Node3D).global_position
	_check("camera frames the whole character", player.camera.camera.is_position_in_frustum(head)
			and player.camera.camera.is_position_in_frustum(boot))
	await _shot("14_character_idle")

	# Crouch keeps the feet planted and fits the smaller collider.
	Input.action_press(&"crouch")
	await _phys(30)
	box = _model_aabb(model)
	Input.action_release(&"crouch")
	_check("crouched: feet still on the ground", absf(box.position.y - player.global_position.y) < 0.03, "%.3f" % box.position.y)
	_check("crouched: model fits the crouch height", box.size.y <= settings.crouch_height + 0.1, "%.2f m" % box.size.y)
	await _phys(20)

	# Follows the body through a jump and lands flush again.
	_key_event(&"jump", true)
	await _phys(15)
	_key_event(&"jump", false)
	box = _model_aabb(model)
	_check("model follows the jump", box.position.y > 0.5, "bottom %.2f" % box.position.y)
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	await _phys(20)
	box = _model_aabb(model)
	_check("after landing: feet back on the ground", absf(box.position.y - player.global_position.y) < 0.03, "%.3f" % box.position.y)


func _model_aabb(model: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		total = box if first else total.merge(box)
		first = false
	return total


func test_resolution() -> void:
	_section("Resolution")
	var base := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	_check("project resolution is 1920x1080", base == Vector2i(1920, 1080), str(base))
	_check("UI base size is 1920x1080 (16:9)", root.content_scale_size == Vector2i(1920, 1080), str(root.content_scale_size))
	_check("stretch mode scales UI with the window", root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	if shots_dir == "":
		print("  (window checks skipped in headless mode)")
		return
	print("  screen %s, usable %s, window %s at %s" % [DisplayServer.screen_get_size(), DisplayServer.screen_get_usable_rect(),
			DisplayServer.window_get_size(), DisplayServer.window_get_position()])
	_check("boots with a 1920x1080 window", DisplayServer.window_get_size() == Vector2i(1920, 1080), str(DisplayServer.window_get_size()))
	var prompt: InteractionPrompt = player.prompt
	for size in [Vector2i(1280, 720), Vector2i(1440, 1080), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(size)
		await _frames(10)
		var visible := root.get_visible_rect().size
		var cap_bottom := visible.y * InteractionPrompt.ANCHOR_Y + InteractionPrompt.CAP_HEIGHT * 0.5
		var fits := prompt.size.is_equal_approx(visible) and cap_bottom < visible.y
		_check("prompt layout fits a %dx%d window" % [size.x, size.y], fits,
				"canvas %s, prompt %s, lowest element %.0f" % [visible, prompt.size, cap_bottom])
		if size != Vector2i(1920, 1080):
			await _place(Vector3(0, 0, front_window.global_position.z + 5.0), 0.0)
			await _shot("11_resized_%dx%d" % [size.x, size.y])


func test_gaps_and_ramp() -> void:
	_section("Ramp / gaps / rooftops")
	await _place(Vector3(-16, 0, 8), 0.0)
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return player.global_position.z < -3.0, 4.0)
	_release_all()
	_check("walks up ramp onto 2.5 m platform", absf(player.global_position.y - 2.5) < 0.1, "y=%.2f" % player.global_position.y)

	# Roof (3.9) -> rooftop 2 across a 2.5 m gap.
	await _place(Vector3(0, 3.9, -29.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -33.4, 3.0)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.global_position.z < -37.0 and player.is_on_floor(), 3.0)
	Input.action_release(&"jump")
	_check("clears 2.5 m rooftop gap", player.global_position.y > 3.8, "y=%.2f z=%.2f" % [player.global_position.y, player.global_position.z])
	await _shot("09_rooftop")
	# Rooftop 2 -> rooftop 3 (3 m gap, 0.9 m drop).
	await _wait_until(func() -> bool: return player.global_position.z < -41.9, 3.0)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.global_position.z < -46.0 and player.is_on_floor(), 3.0)
	Input.action_release(&"jump")
	_check("clears 3 m gap to lower roof", absf(player.global_position.y - 3.0) < 0.1,
			"y=%.2f z=%.2f" % [player.global_position.y, player.global_position.z])
	# Rooftop 3 -> hang on 5.8 m wall.
	Input.action_release(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -50.0, 3.0)
	Input.action_press(&"jump")
	var hung := await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 2.0)
	_release_all()
	_check("grabs the high rooftop ledge", hung, "y=%.2f" % player.global_position.y)


func test_respawn() -> void:
	_section("Respawn")
	await _place(Vector3(30, 0, 30), 0.0)
	Input.action_press(&"debug_respawn")
	await _phys(2)
	Input.action_release(&"debug_respawn")
	_check("R respawns at spawn", player.global_position.distance_to(Vector3(0, 0.05, 10)) < 0.1)
	await _place(Vector3(58, 0, 30), 0.0)
	Input.action_press(&"move_right")
	await _wait_until(func() -> bool: return player.global_position.distance_to(Vector3(0, 0.05, 10)) < 0.1, 6.0)
	_release_all()
	_check("falling off the world respawns", player.global_position.distance_to(Vector3(0, 0.05, 10)) < 0.2)


# --- Helpers -----------------------------------------------------------------

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


## Sends a real key event (reaches _input handlers like a keyboard would).
func _key_event(action: StringName, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_FOR[action]
	event.pressed = pressed
	Input.parse_input_event(event)


## Press and release, held across at least one physics tick like a real
## keypress (a sub-tick tap would be invisible to physics-side input code).
func _tap(action: StringName) -> void:
	_key_event(action, true)
	await process_frame
	await physics_frame
	await physics_frame
	_key_event(action, false)


func _real_wait(seconds: float) -> void:
	var end := Time.get_ticks_usec() + int(seconds * 1_000_000)
	while Time.get_ticks_usec() < end:
		await process_frame


## Waits (real time) until cond() is true; returns false on timeout.
func _real_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_usec() + int(timeout * 1_000_000)
	while Time.get_ticks_usec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


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


## Game seconds until cond() becomes true, or -1.
func _time_until(cond: Callable, timeout: float) -> float:
	var frames := 0
	while frames < int(timeout * 60.0):
		if cond.call():
			return frames / 60.0
		frames += 1
		await physics_frame
	return -1.0


func _shot(file: String, wait_physics := 0, settle := true) -> void:
	if shots_dir == "":
		return
	if wait_physics > 0:
		await _phys(wait_physics)
	elif settle:
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
