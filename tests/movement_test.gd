extends SceneTree
## Automated movement checks that drive the real main scene through the Input
## system (same code path as a keyboard).
##
## Run headless:
##   godot --headless --path . -s res://tests/movement_test.gd
## Also save screenshots (needs a window, so no --headless):
##   godot --path . -s res://tests/movement_test.gd -- --shots=C:/some/dir

const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"sprint", &"jump", &"crouch", &"traverse", &"grapple", &"bullet_time"]
## Real inputs for actions, sent as key / mouse events like a keyboard and
## mouse would.
const KEY_FOR := {&"move_forward": KEY_W, &"move_left": KEY_A, &"move_back": KEY_S,
		&"move_right": KEY_D, &"jump": KEY_SPACE, &"traverse": KEY_E, &"bullet_time": KEY_F}
const MOUSE_FOR := {&"grapple": MOUSE_BUTTON_RIGHT}

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
	await test_window_grapple_loop()
	await test_grapple_arrow()
	await test_grapple_release()
	await test_wall_run()
	await test_wall_run_grapple()
	await test_wall_run_hint()
	await test_playground()
	await test_character()
	await test_idle_animation()
	await test_neutral_stance()
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
	_section("Slow time (F)")
	var bt := player.bullet_time

	# Space on the ground is a jump and never slows time.
	await _place(Vector3(20, 0, 20), 0.0)
	_key_event(&"jump", true)
	var jumped := await _wait_until(func() -> bool: return player.velocity.y > 3.0, 0.3)
	_key_event(&"jump", false)
	_check("Space on the ground jumps", jumped)
	_check("ground jump does not start slow time", not bt.active and is_equal_approx(Engine.time_scale, 1.0))
	# Space again at the apex of a normal jump: no slow time.
	await _wait_until(func() -> bool: return player.velocity.y < 0.5, 1.0)
	await _tap(&"jump")
	await _phys(2)
	_check("Space mid normal jump does not start slow time", not bt.active)
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	# F on the ground: nothing (slow time is for the air, over a real drop).
	await _phys(5)
	await _tap(&"bullet_time")
	await _phys(2)
	_check("F on the ground does not start slow time", not bt.active and player.state == Player.State.MOVE)
	# Space in the air over a real drop no longer slows time: Space is only jump now.
	await _drop_off_roof()
	await _tap(&"jump")
	await _phys(2)
	_check("Space in the air over a drop: no slow time (it's F now)", not bt.active and bt.is_ready())
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)

	# F in the air with a real drop below: slow time starts.
	var at_end := {fov = 0.0, usec = 0}
	var on_end := func() -> void:
		at_end.fov = player.camera.camera.fov
		at_end.usec = Time.get_ticks_usec()
	bt.ended.connect(on_end)
	await _drop_off_roof()
	var start := {usec = 0}
	var on_start := func() -> void: start.usec = Time.get_ticks_usec()
	bt.started.connect(on_start)
	await _tap(&"bullet_time")
	await _phys(1)
	_check("F in the air (roof drop) starts slow time", bt.active and player.last_action == &"slow_time",
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

	# Recharging: F in the air does nothing until the cooldown is over.
	_check("not ready straight after (recharging %.1f s)" % bt.cooldown, not bt.is_ready() and bt.cooldown_left() > bt.cooldown - 1.5,
			"%.1f s left" % bt.cooldown_left())
	await _drop_off_roof(false)
	await _tap(&"bullet_time")
	await _phys(2)
	_check("F in the air while recharging: no slow time", not bt.active)
	await _real_until(func() -> bool: return bt.is_ready(), bt.cooldown + 1.0)
	_check("ready again after the cooldown", bt.is_ready())
	await _drop_off_roof(false)
	await _tap(&"bullet_time")
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

	# E is for windows (and ladders) only: it never vaults. Space does.
	ids.clear()
	await _place(Vector3(-7, 0, -4.8), 0.0)
	Input.action_press(&"move_forward")
	await _phys(6)
	await _tap(&"traverse")
	await _phys(20)
	_check("E at a waist-high wall doesn't vault (E is windows and ladders only)", ids.is_empty(), str(ids))
	await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and ids.size() > 0, 2.0)
	_release_all()
	_check("Space there vaults it", ids.has(&"vault_over"), str(ids))

	# The back window is a plain window: E climbs (or vaults) through it, but
	# like every window, running, sprinting or jumping into it never takes it.
	ids.clear()
	await _place(Vector3(2.0, 0, -29.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(90)
	_release_all()
	_check("back window: sprinting into it does nothing (windows are E only)", ids.is_empty() and player.global_position.z > -33.85,
			"%s z=%.2f" % [ids, player.global_position.z])
	ids.clear()
	await _place(Vector3(2.0, 0, -32.3), 0.0)
	Input.action_press(&"move_forward")
	await _phys(4)
	await _tap(&"jump")
	await _phys(50)
	_release_all()
	_check("back window: jumping into it does nothing", ids.is_empty() and player.global_position.z > -33.85,
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


func test_window_grapple_loop() -> void:
	_section("Window -> bullet time -> grapple -> next building")
	var area := front_window.get_parent().get_parent().get_node("GrappleTestArea")
	var win := area.get_node("PenthouseWindow") as TraversalWindow
	var anchor_a := area.get_node("AnchorTowerA") as GrappleAnchor
	var anchor_b := area.get_node("AnchorTowerB") as GrappleAnchor
	var start := (area.get_node("GrappleTestStart") as Node3D).global_position
	var bt := player.bullet_time
	var ids := _record_traversals()
	_check("test area: tower window, two anchors, start marker", win.dive_window and anchor_a != null and anchor_b != null)
	var grapple_events := InputMap.action_get_events(&"grapple")
	var slow_events := InputMap.action_get_events(&"bullet_time")
	_check("grapple is bound to the right mouse button only (F removed)", grapple_events.size() == 1
			and grapple_events[0] is InputEventMouseButton
			and (grapple_events[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT, str(grapple_events))
	_check("bullet time is bound to F only", slow_events.size() == 1 and slow_events[0] is InputEventKey
			and (slow_events[0] as InputEventKey).physical_keycode == KEY_F, str(slow_events))
	# F with a grapple target in sight: no grapple (F is slow time now).
	await _place(Vector3(30, 8.05, -44.0), 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	var had_target := player.grapple.target == anchor_a
	await _tap(&"bullet_time")
	await _phys(5)
	_check("F with a grapple target in sight does not fire the grapple", had_target and player.state == Player.State.MOVE
			and player.grapple.arrow == null and not player.bullet_time.active, str(player.last_action))

	# E does nothing with no window around.
	await _place(Vector3(20, 0, 30), 0.0)
	ids.clear()
	await _tap(&"traverse")
	await _phys(20)
	_check("E with no window nearby: nothing happens", ids.is_empty() and player.state == Player.State.MOVE, str(ids))

	# Sprinting or jumping into the tower window without E: no traversal.
	ids.clear()
	await _place(start, 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(70)
	_release_all()
	_check("sprint into the tower window without E: no traversal", ids.is_empty() and player.global_position.z > win.global_position.z
			and absf(player.global_position.y - 10.0) < 0.1, "%s at %s" % [ids, player.global_position])
	ids.clear()
	await _place(start, 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return win.distance_to_wall(player.global_position) < 2.6, 2.0)
	await _tap(&"jump")
	await _phys(60)
	_release_all()
	_check("sprint-jump into the tower window without E: no traversal", ids.is_empty() and player.global_position.z > win.global_position.z,
			"%s at %s" % [ids, player.global_position])

	# THE SEQUENCE: sprint -> jump -> E in the air -> dive out -> bullet time -> aim -> fire the
	# grapple arrow -> it attaches -> cable connects -> pulled -> Tower B.
	var r := await _tower_dive(anchor_b, true)
	_check("prompt shows [E] DIVE THROUGH mid-jump", r.prompt_in_air == "E DIVE THROUGH", "'%s'" % r.prompt_in_air)
	_check("E in the air dives through the window", r.dove, str(r.ids))
	_check("bullet time starts at the dive (0.3x)", r.slow_at_dive and is_equal_approx(r.scale_at_dive, bt.time_scale), "%.2f" % r.scale_at_dive)
	_check("bullet time lasts ~0.4 s and ends by itself", absf(r.bt_length - 0.4) < 0.06, "%.3f s" % r.bt_length)
	_check("dive carries the player out of the window, airborne", r.out_airborne, "clear of the frame at %s" % r.clear_pos)
	_check("anchor on Tower B targeted and highlighted", r.target_seen)
	_check("grapple arrow fires while airborne (straight out of the dive)", r.fired and r.fired_airborne and r.cut_dive_short,
			"fired=%s airborne=%s cut_short=%s" % [r.fired, r.fired_airborne, r.cut_dive_short])
	_check("arrow flies to Tower B's anchor (closing in every frame)", r.arrow_frames >= 2 and r.arrow_closing,
			"%d frames in flight, closing=%s" % [r.arrow_frames, r.arrow_closing])
	_check("arrow attaches to the anchor before any pull", r.attached_on_anchor and not r.pulled_before_attach)
	_check("cable connects the player's hand to the attached arrow", r.cable_ok, r.cable_detail)
	var ev: Array = r.events
	var fire_at := ev.find(&"fired")
	_check("order: dive + bullet time -> fire -> attach -> pull -> land", fire_at > 0 and ev.find(&"dive") in range(fire_at)
			and ev.find(&"slow_time") in range(fire_at) and ev.slice(fire_at) == [&"fired", &"attached", &"pull", &"arrived"], str(ev))
	_check("player reaches the grapple point", r.arrived and r.arrive_dist < 1.0, "arrived=%s, %.2f m from the anchor" % [r.arrived, r.arrive_dist])
	_check("lands on Tower B's roof", r.on_floor and absf(r.landed.y - 8.0) < 0.1 and r.landed.z < -40.2 and r.landed.z > -48.0,
			"landed at %s" % r.landed)
	_check("not stuck in geometry", r.clear)
	_check("arrow and cable cleared after landing", r.cleared)
	Input.action_press(&"move_forward")
	await _phys(30)
	var walk := player.horizontal_speed()
	_release_all()
	await _phys(5)
	_key_event(&"jump", true)
	var jumped := await _wait_until(func() -> bool: return player.velocity.y > 3.0, 0.3)
	_key_event(&"jump", false)
	_check("normal movement afterwards (walk + jump on Tower B)", absf(walk - settings.walk_speed) < 0.3 and jumped,
			"walk %.2f, jumped %s" % [walk, jumped])
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)

	# Same dive without pressing grapple: it never grapples by itself.
	r = await _tower_dive(anchor_b, false)
	_check("anchor was targeted during the fall", r.target_seen)
	_check("no arrow and no grapple without a deliberate press", not r.fired and not r.pulled)
	_check("dive exit hands over to a normal fall (not dragged down, no mid-air jump)", r.exit_y > 9.6 and not r.jumped_after_exit,
			"exit y %.2f, jumped %s" % [r.exit_y, r.jumped_after_exit])
	_check("falls to the ground between the towers, safely", r.on_floor and absf(r.landed.y) < 0.1 and r.clear, "landed at %s" % r.landed)

	# Grapple from a normal fall (no dive), steep from well below the anchor.
	await _place(Vector3(30, 4.0, -35.0), 0.0)
	var g := await _grapple_to(anchor_b)
	_check("mid-air grapple from 4.5 m below: arrives and lands on Tower B", g.arrived and g.on_floor and absf(g.landed.y - 8.0) < 0.1
			and g.landed.z < -40.2, "landed at %s" % g.landed)

	# From Tower B's roof back up to Tower A (on foot, right mouse button): the loop repeats.
	await _place(Vector3(30, 8.05, -44.0), 180.0)
	g = await _grapple_to(anchor_a)
	_check("grapple from the ground with right mouse: back up to Tower A", g.arrived and g.on_floor and absf(g.landed.y - 10.0) < 0.1
			and g.landed.x > 25.2 and g.landed.z > -28.0, "landed at %s" % g.landed)
	_check("not stuck in geometry after the return", g.clear)

	# Invalid targets: aimed away, out of range, behind a building.
	await _place(Vector3(30, 8.05, -44.0), 180.0)
	player.camera.yaw = deg_to_rad(90.0)
	await _phys(3)
	_check("aimed away: no target", player.grapple.target == null)
	await _tap(&"grapple")
	await _phys(5)
	_check("grapple press with no target does nothing (no arrow fired)", player.state == Player.State.MOVE
			and player.grapple.arrow == null and player.last_action != &"grapple_fire" and player.last_action != &"grapple",
			str(player.last_action))
	await _place(Vector3(30, 0.05, 30.0), 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	_check("out of range (58 m): no target", player.grapple.target == null)
	await _place(Vector3(30, 0.05, -52.0), 180.0)
	_aim_at(anchor_b.global_position)
	await _phys(3)
	_check("anchor behind a building (no line of sight): no target", player.grapple.target == null)

	# Pressing grapple again lets go mid-pull.
	await _place(Vector3(30, 8.05, -44.0), 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	var finished := [null]
	var on_finish := func(a: bool) -> void: finished[0] = a
	player.grapple_finished.connect(on_finish)
	await _tap(&"grapple")
	await _wait_until(func() -> bool: return player.state == Player.State.GRAPPLE, 1.0) # arrow has stuck
	await _phys(5)
	var pulling := player.state == Player.State.GRAPPLE
	await _tap(&"grapple")
	await _phys(3)
	player.grapple_finished.disconnect(on_finish)
	_check("pressing grapple again lets go mid-pull (arrow and cable removed)", pulling and finished[0] == false
			and player.state == Player.State.MOVE and player.grapple.arrow == null, "pulling=%s finished=%s" % [pulling, finished[0]])
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)

	# The front (ground) window also takes an airborne E, both directions.
	ids.clear()
	await _place(Vector3(0, 0, front_window.global_position.z + 6.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return front_window.distance_to_wall(player.global_position) < 2.6, 2.0)
	await _tap(&"jump")
	await _phys(1)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return player.state != Player.State.TRAVERSAL and ids.size() > 0, 3.0)
	_release_all()
	await _phys(20)
	_check("front window: jump + E dives IN", ids.has(&"window_dive") and player.global_position.z < -26.5 and player.is_on_floor(),
			"%s at %s" % [ids, player.global_position])
	ids.clear()
	await _place(Vector3(0, 0, -32.5), 180.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return front_window.distance_to_wall(player.global_position) < 2.6, 2.0)
	await _tap(&"jump")
	await _phys(1)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return player.state != Player.State.TRAVERSAL and ids.size() > 0, 3.0)
	_release_all()
	await _phys(20)
	_check("front window: jump + E dives OUT", ids.has(&"window_dive") and player.global_position.z > -25.5 and player.is_on_floor(),
			"%s at %s" % [ids, player.global_position])
	_stop_recording()
	if shots_dir != "":
		await _grapple_showcase(win, anchor_b, start)


## Screenshot-only replay of the sequence (no checks; runs after them so
## screenshot stalls can't affect results).
func _grapple_showcase(win: TraversalWindow, anchor: GrappleAnchor, start: Vector3) -> void:
	await _place(start, 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return win.distance_to_wall(player.global_position) < 2.6, 2.0)
	await _tap(&"jump")
	await _phys(1)
	_release_all()
	await _shot("15_tower_prompt_midjump", 0, false)
	await _tap(&"traverse")
	await _phys(3)
	await _shot("16_tower_dive_bullet_time", 0, false)
	await _wait_until(func() -> bool: return player.global_position.z < win.global_position.z - 0.7, 2.0)
	_aim_at(anchor.global_position)
	await _phys(2)
	await _tap(&"grapple")
	await _shot("17_grapple_arrow_flight", 0, false)
	await _wait_until(func() -> bool: return player.state == Player.State.GRAPPLE, 2.0)
	await _shot("18_grapple_arrow_attached", 0, false)
	await _phys(8)
	await _shot("19_grapple_pull", 0, false)
	await _wait_until(func() -> bool: return player.state != Player.State.GRAPPLE, 3.0)
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	player.camera.yaw = deg_to_rad(180.0) # look back at Tower A
	await _phys(20)
	await _shot("20_landed_on_tower_b")


## Sprint at the tower window from the start marker, jump, press E in the air,
## then (optionally) fire the grapple arrow at `anchor` once clear of the
## window and follow it: flight, attach, cable, pull, landing.
func _tower_dive(anchor: GrappleAnchor, press_grapple: bool) -> Dictionary:
	var area := front_window.get_parent().get_parent().get_node("GrappleTestArea")
	var win := area.get_node("PenthouseWindow") as TraversalWindow
	var grapple := player.grapple
	var out := {prompt_in_air = "", dove = false, ids = [], slow_at_dive = false, scale_at_dive = 1.0, bt_length = 0.0,
			out_airborne = false, clear_pos = Vector3.ZERO, target_seen = false, fired = false, fired_airborne = false,
			cut_dive_short = false, arrow_frames = 0, arrow_closing = true, attached_on_anchor = false,
			pulled = false, pulled_before_attach = false, cable_ok = false, cable_detail = "", events = [],
			arrived = false, arrive_dist = INF, exit_y = 0.0, jumped_after_exit = false,
			landed = Vector3.ZERO, on_floor = false, clear = false, cleared = false}
	await _place((area.get_node("GrappleTestStart") as Node3D).global_position, 0.0)
	var bt_times := [0, 0]
	var on_bt_start := func() -> void:
		bt_times[0] = Time.get_ticks_usec()
		out.events.append(&"slow_time")
	var on_bt_end := func() -> void: bt_times[1] = Time.get_ticks_usec()
	var dive := [null]
	var on_traversal := func(id: StringName) -> void:
		out.ids.append(id)
		if id == &"window_dive":
			dive[0] = player.current_motion
			out.slow_at_dive = player.bullet_time.active
			out.scale_at_dive = Engine.time_scale
			out.events.append(&"dive")
	var on_traversal_end := func(id: StringName) -> void:
		if id == &"window_dive":
			out.exit_y = player.global_position.y
	var on_fired := func(_a: GrappleAnchor) -> void:
		out.fired = true
		out.fired_airborne = player.global_position.y > 9.0 and not player.is_on_floor()
		out.cut_dive_short = dive[0] != null and not (dive[0] as TraversalMotion).is_finished()
		out.events.append(&"fired")
		grapple.arrow.attached.connect(func(_b: GrappleAnchor) -> void: out.events.append(&"attached"))
	var on_pull := func(_a: GrappleAnchor) -> void:
		out.pulled = true
		out.pulled_before_attach = not grapple.is_attached()
		out.attached_on_anchor = grapple.is_attached() and grapple.arrow.global_position.distance_to(anchor.global_position) < 0.01
		out.events.append(&"pull")
	var on_grapple_end := func(arrived: bool) -> void:
		out.arrived = arrived
		out.arrive_dist = player.global_position.distance_to(anchor.global_position)
		out.events.append(&"arrived" if arrived else &"ended")
	player.bullet_time.started.connect(on_bt_start)
	player.bullet_time.ended.connect(on_bt_end)
	player.traversal_started.connect(on_traversal)
	player.traversal_finished.connect(on_traversal_end)
	player.grapple_fired.connect(on_fired)
	player.grapple_started.connect(on_pull)
	player.grapple_finished.connect(on_grapple_end)

	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return win.distance_to_wall(player.global_position) < 2.6, 2.0)
	await _tap(&"jump")
	await _phys(1)
	if not player.is_on_floor():
		out.prompt_in_air = player.prompt.hint_text()
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 0.5)
	out.dove = out.ids.has(&"window_dive")
	_release_all()
	# Aim at the next building while diving through the frame. A grapple press
	# just before clearing it is remembered (grapple buffer) and fires on the
	# first tick the player is clear, like a player pressing slightly early.
	# (Pressing only after clearing the frame raced the end of the dive, which
	# depends on how much of it bullet time slowed - real time - and was flaky.)
	_aim_at(anchor.global_position)
	if press_grapple:
		await _wait_until(func() -> bool: return player.global_position.z < win.global_position.z + 0.3, 2.0)
		await _tap(&"grapple")
	# Clear of the frame, still in the air.
	await _wait_until(func() -> bool: return player.global_position.z < win.global_position.z - 0.7, 2.0)
	out.clear_pos = player.global_position
	out.out_airborne = player.global_position.y > 9.5 and not player.is_on_floor()
	out.target_seen = player.grapple.target == anchor and anchor.is_targeted()
	if press_grapple:
		# Follow the arrow: it must close on the anchor every frame until it sticks.
		var last := INF
		while grapple.is_arrow_flying() and out.arrow_frames < 120:
			var d := grapple.arrow.global_position.distance_to(anchor.global_position)
			out.arrow_closing = out.arrow_closing and d < last
			last = d
			out.arrow_frames += 1
			await physics_frame
		# Cable connected: player's hand -> the stuck arrow's nock.
		await _wait_until(func() -> bool: return player.state == Player.State.GRAPPLE, 1.0)
		await _frames(2)
		if grapple.arrow != null:
			var ends := _cable_ends()
			var hand := player.get_global_transform_interpolated().origin + Vector3.UP * grapple.hand_height
			var hand_gap := ends[0].distance_to(hand)
			var nock_gap := ends[1].distance_to(grapple.arrow.nock_position())
			out.cable_ok = grapple._cable.visible and hand_gap < 0.5 and nock_gap < 0.05
			out.cable_detail = "hand gap %.2f m, nock gap %.3f m" % [hand_gap, nock_gap]
		await _wait_until(func() -> bool: return out.fired and player.state == Player.State.MOVE, 4.0)
	else:
		# Try Space right after the exit: no coyote jump in mid-air.
		await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
		var vy_before := player.velocity.y
		await _tap(&"jump")
		await _phys(2)
		out.jumped_after_exit = player.velocity.y > maxf(vy_before, 0.0) + 1.0
	await _wait_until(func() -> bool: return player.is_on_floor(), 5.0)
	await _real_until(func() -> bool: return not player.bullet_time.active, 1.0)
	await _phys(5)
	out.bt_length = (bt_times[1] - bt_times[0]) / 1_000_000.0
	out.landed = player.global_position
	out.on_floor = player.is_on_floor()
	out.clear = player.sensor.has_clearance(player.global_position, settings.standing_height)
	out.cleared = grapple.arrow == null and not grapple._cable.visible
	player.bullet_time.started.disconnect(on_bt_start)
	player.bullet_time.ended.disconnect(on_bt_end)
	player.traversal_started.disconnect(on_traversal)
	player.traversal_finished.disconnect(on_traversal_end)
	player.grapple_fired.disconnect(on_fired)
	player.grapple_started.disconnect(on_pull)
	player.grapple_finished.disconnect(on_grapple_end)
	return out


## Aims at `anchor`, presses grapple (right mouse) and follows the pull.
func _grapple_to(anchor: GrappleAnchor) -> Dictionary:
	var out := {arrived = false, landed = Vector3.ZERO, on_floor = false, clear = false}
	_aim_at(anchor.global_position)
	await _phys(2)
	var done := [false]
	var on_finish := func(arrived: bool) -> void:
		out.arrived = arrived
		done[0] = true
	player.grapple_finished.connect(on_finish)
	await _tap(&"grapple") # right mouse button
	await _wait_until(func() -> bool: return done[0], 4.0)
	player.grapple_finished.disconnect(on_finish)
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	await _phys(5)
	out.landed = player.global_position
	out.on_floor = player.is_on_floor()
	out.clear = player.sensor.has_clearance(player.global_position, settings.standing_height)
	return out


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


func test_grapple_arrow() -> void:
	_section("Grapple arrow: fire -> fly -> attach -> cable -> pull")
	var area := front_window.get_parent().get_parent().get_node("GrappleTestArea")
	var anchor_a := area.get_node("AnchorTowerA") as GrappleAnchor
	var anchor_b := area.get_node("AnchorTowerB") as GrappleAnchor
	var grapple := player.grapple
	var bt := player.bullet_time
	var roof_b := Vector3(30, 8.05, -44.0)
	var events := []
	var on_fired := func(_a: GrappleAnchor) -> void: events.append(&"fired")
	var on_pull := func(_a: GrappleAnchor) -> void: events.append(&"pull")
	var on_end := func(arrived: bool) -> void: events.append(&"arrived" if arrived else &"ended")
	player.grapple_fired.connect(on_fired)
	player.grapple_started.connect(on_pull)
	player.grapple_finished.connect(on_end)

	# Standing on Tower B, fire at Tower A's anchor and follow the shot frame by frame.
	await _place(roof_b, 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	events.clear()
	var feet := player.global_position
	var shot := {}
	var on_shot := func(a: GrappleAnchor) -> void: # the moment of release
		shot.arrow = grapple.arrow
		shot.nock_gap = (grapple.arrow.global_transform * Vector3(0, 0, GrappleArrow.LENGTH)).distance_to(grapple.hand_position())
		shot.aim = (-grapple.arrow.global_basis.z).dot((a.global_position - grapple.arrow.global_position).normalized())
	player.grapple_fired.connect(on_shot)
	await _tap(&"grapple")
	player.grapple_fired.disconnect(on_shot)
	_check("grapple press fires an arrow (arrow in flight, not pulling yet)", events == [&"fired"]
			and player.state == Player.State.GRAPPLE_FIRE and grapple.is_arrow_flying(), "%s %s" % [events, Player.State.keys()[player.state]])
	var arrow: GrappleArrow = shot.get("arrow")
	var parts := arrow.find_children("*", "MeshInstance3D", true, false).size() if arrow else 0
	_check("it is a real arrow: a GrappleArrow with placeholder geometry (head, claws, shaft, fletching)",
			arrow != null and arrow.is_visible_in_tree() and parts >= 8, "%d mesh parts" % parts)
	_check("released from the hand, nocked in front of the body, aimed at the anchor",
			shot.get("nock_gap", INF) < 0.5 and shot.get("aim", 0.0) > 0.999, "nock %.2f m from the hand, aim dot %.4f"
			% [shot.get("nock_gap", INF), shot.get("aim", 0.0)])
	var dists: Array[float] = []
	var cable: Array[float] = []
	var moved := 0.0
	var pulled_in_flight := false
	while grapple.is_arrow_flying() and dists.size() < 120:
		dists.append(grapple.arrow.global_position.distance_to(anchor_a.global_position))
		cable.append(grapple._cable.global_transform.basis.y.length() if grapple._cable.visible else 0.0)
		moved = maxf(moved, player.global_position.distance_to(feet))
		pulled_in_flight = pulled_in_flight or player.state == Player.State.GRAPPLE or events.has(&"pull")
		await physics_frame
	var closing := dists.size() >= 3
	var paying_out := cable.size() >= 3 and cable[0] > 0.0
	for i in range(1, dists.size()):
		closing = closing and dists[i] < dists[i - 1]
		paying_out = paying_out and cable[i] >= cable[i - 1] - 0.01
	var speed := (dists[0] - dists[-1]) / maxf(dists.size() - 1, 1) * Engine.physics_ticks_per_second if dists.size() > 1 else 0.0
	_check("arrow travels to the anchor at arrow speed (~%.0f m/s)" % grapple.arrow_speed, closing
			and absf(speed - grapple.arrow_speed) < 1.0, "%.1f m/s over %d frames" % [speed, dists.size()])
	_check("cable pays out behind the arrow while it flies", paying_out and cable[-1] > cable[0] + 2.0,
			"%.1f m -> %.1f m" % [cable[0] if cable.size() else 0.0, cable[-1] if cable.size() else 0.0])
	_check("player is not pulled while the arrow flies", not pulled_in_flight and moved < 0.2, "moved %.2f m" % moved)
	var tip_gap := arrow.global_position.distance_to(anchor_a.global_position) if is_instance_valid(arrow) else INF
	_check("arrow attaches: stuck with its tip in the anchor", is_instance_valid(arrow) and arrow.phase == GrappleArrow.Phase.ATTACHED
			and tip_gap < 0.01, "tip %.3f m from the anchor" % tip_gap)
	await _wait_until(func() -> bool: return player.state == Player.State.GRAPPLE, 0.5)
	await _frames(2)
	var ends := _cable_ends()
	var hand := player.get_global_transform_interpolated().origin + Vector3.UP * grapple.hand_height
	var hand_gap := ends[0].distance_to(hand)
	var nock_gap := ends[1].distance_to(arrow.nock_position()) if is_instance_valid(arrow) else INF
	_check("cable connects the player's hand to the attached arrow's nock", grapple._cable.visible and hand_gap < 0.3 and nock_gap < 0.05,
			"hand gap %.2f m, nock gap %.3f m" % [hand_gap, nock_gap])
	_check("pull begins only after the arrow attached", events == [&"fired", &"pull"] and player.state == Player.State.GRAPPLE, str(events))
	await _wait_until(func() -> bool: return events.size() >= 3, 4.0)
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	await _phys(5)
	_check("pulled along the cable and lands on Tower A", events == [&"fired", &"pull", &"arrived"] and player.is_on_floor()
			and absf(player.global_position.y - 10.0) < 0.1, "%s at %s" % [events, player.global_position])
	_check("arrow and cable removed once the grapple is over", grapple.arrow == null and not grapple._cable.visible
			and not is_instance_valid(arrow))

	# Grapple again while the arrow is still flying: let go, no pull.
	await _place(roof_b, 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	events.clear()
	await _tap(&"grapple")
	var cancelled := grapple.arrow
	var was_flying := grapple.is_arrow_flying()
	await _tap(&"grapple")
	await _phys(3)
	_check("grapple again mid-flight: lets go (arrow and cable removed, no pull)", was_flying and events == [&"fired", &"ended"]
			and player.state == Player.State.MOVE and player.last_action == &"grapple_release" and grapple.arrow == null
			and not grapple._cable.visible and not is_instance_valid(cancelled), "%s last %s" % [events, player.last_action])
	_check("still standing on Tower B afterwards", player.is_on_floor() and absf(player.global_position.y - 8.0) < 0.1,
			str(player.global_position))

	# The anchor goes away while the arrow flies: it misses and the grapple ends safely.
	await _place(roof_b, 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	events.clear()
	await _tap(&"grapple")
	var missed := [false]
	grapple.arrow.missed.connect(func() -> void: missed[0] = true)
	anchor_a.enabled = false
	await _phys(3)
	anchor_a.enabled = true
	_check("anchor disabled mid-flight: arrow misses, grapple ends, no pull", missed[0] and events == [&"fired", &"ended"]
			and player.state == Player.State.MOVE and player.last_action == &"grapple_miss" and grapple.arrow == null,
			"%s last %s" % [events, player.last_action])

	# Something moves into the arrow's path: it strikes it and the grapple ends.
	await _place(roof_b, 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	events.clear()
	await _tap(&"grapple")
	var path_mid := grapple.hand_position().lerp(anchor_a.global_position, 0.6)
	var wall := _temp_wall(path_mid, anchor_a.global_position)
	var struck := [Vector3.INF]
	var blocked := grapple.arrow
	blocked.missed.connect(func() -> void: struck[0] = blocked.global_position)
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 1.0)
	wall.queue_free()
	var wall_gap := (struck[0] as Vector3).distance_to(path_mid)
	_check("path blocked mid-flight: arrow strikes the obstacle, grapple ends, no pull", wall_gap < 0.5
			and events == [&"fired", &"ended"] and player.last_action == &"grapple_miss" and absf(player.global_position.y - 8.0) < 0.1,
			"struck %.2f m from the wall, %s" % [wall_gap, events])

	# Safety net: an arrow still flying past its time limit counts as a miss.
	await _place(roof_b, 180.0)
	_aim_at(anchor_a.global_position)
	await _phys(3)
	events.clear()
	await _tap(&"grapple")
	grapple.arrow.max_flight_time = 0.0
	await _phys(3)
	_check("arrow flight timeout: counts as a miss, grapple ends", events == [&"fired", &"ended"]
			and player.last_action == &"grapple_miss" and player.state == Player.State.MOVE, str(events))

	# Off Tower B's edge in slow time: the arrow flies in game time (slowed with
	# everything else) and still carries the player up to Tower A.
	await _place(Vector3(32, 8.05, -41.5), 180.0)
	_aim_at(anchor_a.global_position)
	events.clear()
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return not player.is_on_floor() and player.global_position.y < 7.3, 2.0)
	Input.action_release(&"move_forward")
	await _tap(&"bullet_time")
	var at_fire := {slow = false, scale = 1.0}
	var on_slow_fire := func(_a: GrappleAnchor) -> void:
		at_fire.slow = bt.active
		at_fire.scale = Engine.time_scale
	player.grapple_fired.connect(on_slow_fire)
	_aim_at(anchor_a.global_position)
	await _tap(&"grapple")
	player.grapple_fired.disconnect(on_slow_fire)
	# Physics ticks keep their real-time rate; slow time shrinks each tick's delta.
	var real_speed := 0.0
	var slow_throughout := bt.active
	if grapple.is_arrow_flying():
		var p0 := grapple.arrow.global_position
		await physics_frame
		slow_throughout = slow_throughout and bt.active
		if grapple.is_arrow_flying():
			real_speed = p0.distance_to(grapple.arrow.global_position) * Engine.physics_ticks_per_second
	_check("arrow fired during bullet time (0.3x untouched)", at_fire.slow and is_equal_approx(at_fire.scale, bt.time_scale),
			"slow %s, scale %.2f" % [at_fire.slow, at_fire.scale])
	_check("arrow flies in game time: slowed to 0.3x with everything else", slow_throughout
			and absf(real_speed - grapple.arrow_speed * bt.time_scale) < 1.0, "%.1f m/s real (%.0f x %.1f)"
			% [real_speed, grapple.arrow_speed, bt.time_scale])
	await _wait_until(func() -> bool: return events.size() >= 3, 4.0)
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	await _real_until(func() -> bool: return not bt.active, 1.0)
	await _phys(5)
	_check("slow-time shot: attaches, pulls, lands on Tower A", events == [&"fired", &"pull", &"arrived"] and player.is_on_floor()
			and absf(player.global_position.y - 10.0) < 0.1, "%s at %s" % [events, player.global_position])
	_check("bullet time still ends by itself (time scale back to 1)", not bt.active and is_equal_approx(Engine.time_scale, 1.0))

	# The arrow is self-contained: it flies and sticks without the player.
	await _place(Vector3(20, 0, 30), 0.0)
	var solo := GrappleArrow.new()
	root.add_child(solo)
	var stuck := [null]
	solo.attached.connect(func(a: GrappleAnchor) -> void: stuck[0] = a)
	solo.launch(Vector3(30, 12, -33), anchor_b)
	await _wait_until(func() -> bool: return stuck[0] != null, 1.0)
	_check("GrappleArrow works on its own (no player involved)", stuck[0] == anchor_b and solo.is_attached()
			and solo.global_position.distance_to(anchor_b.global_position) < 0.01 and player.state == Player.State.MOVE
			and grapple.arrow == null)
	solo.queue_free()
	player.grapple_fired.disconnect(on_fired)
	player.grapple_started.disconnect(on_pull)
	player.grapple_finished.disconnect(on_end)


func test_grapple_release() -> void:
	_section("Grapple release: the way you were going, never a launch")
	var anchor_a := front_window.get_parent().get_parent().get_node("GrappleTestArea/AnchorTowerA") as GrappleAnchor
	var g := player.grapple
	for run in [{dist = 8.0, label = "early (8 m out)", steer = false}, {dist = 1.5, label = "right before the anchor", steer = true}]:
		var r := await _release_run(anchor_a, run.dist, run.steer)
		var before: Vector3 = r.v_before
		var after: Vector3 = r.v_release
		var same_way := Vector2(after.x, after.z).normalized().dot(Vector2(before.x, before.z).normalized()) > 0.99
		_check("release %s: carries on the pull's way, trimmed to what a body carries (no boost, no launch)" % run.label,
				r.released and r.last_action == &"grapple_release" and after.is_equal_approx(g.release_velocity(before))
				and same_way and after.length() <= before.length() + 0.01
				and Vector2(after.x, after.z).length() <= g.release_speed + 0.01 and after.y <= g.release_rise_speed + 0.01,
				"%s -> %s, %s" % [before, after, r.last_action])
		if not run.steer:
			_check("release %s: horizontal speed never grows afterwards, vertical only falls" % run.label,
					r.max_flat <= r.flat_release + 0.01 and r.vy_only_falls, "released at %.2f m/s, max after %.2f m/s"
					% [r.flat_release, r.max_flat])
		else:
			_check("release %s: normal movement takes over and can steer" % run.label, r.state_after == Player.State.MOVE
					and r.steer_gain > 2.0 and r.max_flat <= r.flat_release + 0.5, "steer +%.1f m/s sideways, top speed across %.2f (released %.2f)"
					% [r.steer_gain, r.max_flat, r.flat_release])


## Grapples from Tower B to `anchor`, releases once within `dist` of it and
## follows the free movement for half a second (optionally steering left).
func _release_run(anchor: GrappleAnchor, dist: float, steer: bool) -> Dictionary:
	var out := {released = false, v_before = Vector3.ZERO, v_release = Vector3.INF, last_action = &"", flat_release = 0.0,
			speed_release = 0.0, max_flat = 0.0, max_speed = 0.0, vy_only_falls = true, steer_gain = 0.0, state_after = -1}
	await _place(Vector3(30, 8.05, -44.0), 180.0)
	_aim_at(anchor.global_position)
	await _phys(3)
	var tick_start := [Vector3.ZERO]
	var on_tick := func() -> void: tick_start[0] = player.velocity # before the player's step
	var on_finish := func(_arrived: bool) -> void:
		out.released = true
		out.v_before = tick_start[0]
		out.v_release = player.velocity
		out.last_action = player.last_action
	physics_frame.connect(on_tick)
	player.grapple_finished.connect(on_finish)
	await _tap(&"grapple")
	var close_enough := func() -> bool: return player.state == Player.State.GRAPPLE and player.global_position.distance_to(anchor.global_position) <= dist
	await _wait_until(close_enough, 3.0)
	await _tap(&"grapple")
	physics_frame.disconnect(on_tick)
	player.grapple_finished.disconnect(on_finish)
	var v0: Vector3 = out.v_release
	out.flat_release = Vector2(v0.x, v0.z).length()
	out.speed_release = v0.length()
	var left := player.camera.yaw_basis() * Vector3.LEFT
	var left0 := v0.dot(left)
	if steer:
		Input.action_press(&"move_left")
	var last_vy := v0.y
	for i in 30:
		await physics_frame
		var v := player.velocity
		out.max_flat = maxf(out.max_flat, Vector2(v.x, v.z).length())
		out.max_speed = maxf(out.max_speed, v.length())
		if not player.is_on_floor():
			out.vy_only_falls = out.vy_only_falls and v.y <= last_vy + 0.001
		last_vy = v.y
		out.steer_gain = maxf(out.steer_gain, v.dot(left) - left0)
	out.state_after = player.state
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	return out


func test_wall_run() -> void:
	_section("Wall-run + wall-jump")
	var area := front_window.get_parent().get_parent().get_node("TraversalPlayground/BasicWallRun")
	var face_x := (area.get_node("RunWall") as Node3D).global_position.x + 0.3 # the face the lanes run along
	var lane := Vector3(face_x + 0.6, 0.05, -1.0) # 0.25 m off the wall; heading -Z the wall is on the left
	var pivot := player.get_node("Visual/Pivot") as Node3D
	var runs := []
	var ends := []
	var on_run := func(normal: Vector3) -> void: runs.append(normal)
	var on_end := func(did_jump: bool) -> void: ends.append(did_jump)
	player.wall_run_started.connect(on_run)
	player.wall_run_finished.connect(on_end)

	# Entering: sprint, jump alongside the tall wall, keep holding forward.
	var entered := await _run_and_jump(lane, 0.0)
	_check("sprint-jump alongside a tall wall, holding forward: wall-run starts", entered and player.last_action == &"wall_run"
			and runs.size() == 1 and (runs[0] as Vector3).is_equal_approx(Vector3.RIGHT), "%s %s" % [player.last_action, runs])
	_check("starts off the ground, in the jump", player.global_position.y > 0.5 and not player.is_on_floor(),
			"feet at %.2f" % player.global_position.y)
	# Holding forward, the run carries on along the wall at running speed.
	var z0 := player.global_position.z
	var slowest := INF
	var widest := 0.0
	var ticks := 0
	while player.state == Player.State.WALL_RUN and ticks < 20:
		await physics_frame
		ticks += 1
		slowest = minf(slowest, -player.velocity.z)
		widest = maxf(widest, player.global_position.x - 0.35 - face_x)
	var facing := (-player.global_basis.z).dot(Vector3.FORWARD)
	_check("holding forward: runs along the wall at running speed, on the wall", ticks == 20 and slowest > settings.sprint_speed - 0.3
			and z0 - player.global_position.z > 3.0 and widest <= player.sensor.wall_run_reach + 0.01 and facing > 0.95,
			"%d ticks, slowest %.2f m/s, %.2f m along, widest gap %.2f m" % [ticks, slowest, z0 - player.global_position.z, widest])
	_check("visual hook: body leans off the wall while running", pivot.rotation.z < -0.1, "roll %.2f" % pivot.rotation.z)
	Input.action_press(&"move_left") # into the wall as well as along it
	await _phys(6)
	_check("steering into the wall as well keeps the run going", player.state == Player.State.WALL_RUN)
	Input.action_release(&"move_left")
	# Steering away drops off the wall with the speed it had.
	var along := -player.velocity.z
	Input.action_press(&"move_right")
	await _phys(2)
	_check("steering away drops off, keeping the speed along the wall", player.state == Player.State.MOVE
			and player.last_action == &"wall_run_end" and ends == [false] and -player.velocity.z > along - 0.3
			and not player.is_on_floor(), "%s, %.2f -> %.2f m/s" % [player.last_action, along, -player.velocity.z])
	# Normal air movement from there: steering back into the same wall doesn't re-stick.
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	var landed := await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	_check("back to normal air movement: steers back to the wall without re-sticking, lands", landed
			and runs.size() == 1 and player.state == Player.State.MOVE and player.global_position.x - 0.35 - face_x < 0.05,
			"runs %d, gap %.2f" % [runs.size(), player.global_position.x - 0.35 - face_x])
	_release_all()
	await _phys(30)
	_check("visual hook: upright again once off the wall", absf(pivot.rotation.z) < 0.03, "roll %.3f" % pivot.rotation.z)

	# A run left alone ends by itself (here: slides down to the ground) and
	# hands straight back to normal running.
	runs.clear()
	ends.clear()
	entered = await _run_and_jump(lane, 0.0)
	var run_ticks := 0
	while player.state == Player.State.WALL_RUN and run_ticks < 120:
		await physics_frame
		run_ticks += 1
	await _phys(10)
	_check("a run left alone ends by itself within %.1f s" % player.wall_run_max_time, entered and ends == [false]
			and run_ticks / 60.0 <= player.wall_run_max_time + 0.05, "%.2f s" % (run_ticks / 60.0))
	_check("then normal movement: running on the ground at sprint speed", player.state == Player.State.MOVE
			and player.is_on_floor() and absf(player.horizontal_speed() - settings.sprint_speed) < 0.3,
			"%.2f m/s" % player.horizontal_speed())
	_release_all()

	# Invalid walls: too low, sloped, too slow, not steering along, running into it.
	var slab_feet := Vector3(-30.0, 0.5, -15.0)
	var from := slab_feet + Vector3.UP * 0.6
	var raw := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,
			from + Vector3.RIGHT * (player.sensor.body_radius + player.sensor.wall_run_reach), 1))
	_check("sensor: the 30-degree slab is in reach but rejected; the tall wall is accepted", not raw.is_empty()
			and absf((raw.normal as Vector3).y - 0.5) < 0.01 and player.sensor.detect_run_wall(slab_feet, Vector3.RIGHT) == null
			and player.sensor.detect_run_wall(Vector3(lane.x, 0.5, -15.0), Vector3.LEFT) != null)
	for case in [{label = "low wall (1.2 m)", start = Vector3(-49.1, 0.05, -4.0), yaw = 0.0, sprint = true, forward = true},
			{label = "30-degree slab", start = Vector3(-30.0, 0.05, -6.0), yaw = 0.0, sprint = true, forward = true},
			{label = "tall wall at walking pace", start = lane, yaw = 0.0, sprint = false, forward = true},
			{label = "tall wall without steering along it", start = lane, yaw = 0.0, sprint = true, forward = false},
			{label = "running into the tall wall (60 degrees)", start = Vector3(-36.6, 0.05, -8.0), yaw = 60.0, sprint = true, forward = true}]:
		runs.clear()
		var stuck := await _run_and_jump(case.start, case.yaw, case.sprint, case.forward)
		var down := await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
		_check("no wall-run: %s" % case.label, not stuck and runs.is_empty() and down and player.state == Player.State.MOVE,
				"%s, landed %s" % [player.last_action, down])
		_release_all()

	# Wall-jump: Space on the wall.
	runs.clear()
	ends.clear()
	entered = await _run_and_jump(lane, 0.0)
	await _phys(10)
	Input.action_release(&"jump")
	await _phys(1)
	var tick_start := [Vector3.ZERO]
	var at_jump := [Vector3.ZERO]
	var on_tick := func() -> void: tick_start[0] = player.velocity
	var on_jump := func(did_jump: bool) -> void:
		if did_jump:
			at_jump[0] = player.velocity
	physics_frame.connect(on_tick)
	player.wall_run_finished.connect(on_jump)
	Input.action_press(&"jump") # held: the full height of a normal jump
	var jumped := await _wait_until(func() -> bool: return at_jump[0] != Vector3.ZERO, 0.3)
	physics_frame.disconnect(on_tick)
	player.wall_run_finished.disconnect(on_jump)
	var takeoff_y := player.global_position.y
	var before: Vector3 = tick_start[0]
	var after: Vector3 = at_jump[0]
	_check("Space on the wall: wall-jump, straight back to normal movement", entered and jumped and ends == [true]
			and player.state == Player.State.MOVE and player.last_action == &"wall_jump", str(ends))
	_check("wall-jump keeps the speed along the wall", absf(-after.z - -before.z) < 0.01, "%.2f -> %.2f m/s" % [-before.z, -after.z])
	_check("no launch: pushes off at %.1f m/s, rises like a normal jump" % player.wall_jump_push,
			absf(after.x - player.wall_jump_push) < 0.01 and absf(after.y - settings.jump_velocity()) < 0.01,
			"push %.2f, up %.2f" % [after.x, after.y])
	# Immediate air control: steer straight back toward the wall.
	Input.action_press(&"move_left")
	await _phys(6)
	_check("immediate air control after the wall-jump", after.x - player.velocity.x > 1.0,
			"sideways %.2f -> %.2f m/s in 0.1 s" % [after.x, player.velocity.x])
	var peak := takeoff_y
	for i in 4:
		peak = maxf(peak, player.global_position.y)
		await physics_frame
	var along_later := -player.velocity.z
	while not player.is_on_floor() and player.velocity.y > 0.0:
		peak = maxf(peak, player.global_position.y)
		await physics_frame
	_check("keeps useful momentum after the wall-jump", along_later > -before.z * 0.9, "%.2f of %.2f m/s along" % [along_later, -before.z])
	_check("rises no higher than a normal jump", peak - takeoff_y <= settings.jump_height + 0.05,
			"%.2f m (jump height %.2f)" % [peak - takeoff_y, settings.jump_height])
	landed = await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	_check("lands normally; steering back didn't re-stick to that wall", landed and runs.size() == 1
			and player.state == Player.State.MOVE, "runs %d" % runs.size())
	_release_all()

	# Wall on the right (running the other way): the camera stays on the open
	# side, off the wall, with a slight roll away from it; normal again after.
	var cam := player.camera
	entered = await _run_and_jump(Vector3(lane.x, 0.05, -29.0), 180.0)
	await _phys(30)
	var cam_side := cam.camera.global_position.x - player.global_position.x
	var up := cam.camera.global_basis.y
	_check("wall on the right: camera moves to the open side, not into the wall", entered and player.state == Player.State.WALL_RUN
			and cam_side > 0.2 and cam.boom_fraction > 0.9, "camera %.2f m off the body axis, boom %.2f" % [cam_side, cam.boom_fraction])
	_check("camera rolls slightly away from the wall", up.x > 0.03 and up.x < 0.1, "up.x %.3f" % up.x)
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	_release_all()
	await _phys(60)
	# (Standing against that wall now, the normal right shoulder meets it and the
	# existing camera collision pulls in as it always has; only the wall-run
	# adjustment itself is checked here.)
	_check("camera wall-run framing removed after the run (shoulder and roll back to normal)",
			absf(cam._shoulder - cam.shoulder_offset) < 0.01 and absf(cam.camera.rotation.z) < 0.005,
			"shoulder %.3f, roll %.4f" % [cam._shoulder, cam.camera.rotation.z])
	player.wall_run_started.disconnect(on_run)
	player.wall_run_finished.disconnect(on_end)


func test_wall_run_grapple() -> void:
	_section("Wall-run + grapple")
	var area := front_window.get_parent().get_parent().get_node("TraversalPlayground/BasicWallRun")
	var anchor := area.get_node("AnchorEndTower") as GrappleAnchor
	var face_x := (area.get_node("RunWall") as Node3D).global_position.x + 0.3
	var events := []
	var on_fired := func(_a: GrappleAnchor) -> void: events.append(&"fired")
	var on_pull := func(_a: GrappleAnchor) -> void: events.append(&"pull")
	var on_grapple_end := func(arrived: bool) -> void: events.append(&"arrived" if arrived else &"released")
	var on_run := func(_n: Vector3) -> void: events.append(&"wall_run")
	var on_run_end := func(jumped: bool) -> void: events.append(&"wall_jump" if jumped else &"wall_run_end")
	player.grapple_fired.connect(on_fired)
	player.grapple_started.connect(on_pull)
	player.grapple_finished.connect(on_grapple_end)
	player.wall_run_started.connect(on_run)
	player.wall_run_finished.connect(on_run_end)

	# Grapple alongside the wall, let go, steer to the wall: the run picks up the momentum.
	await _place(Vector3(face_x + 0.75, 0.05, -3.0), 0.0) # pulled 0.4 m off the wall
	_aim_at(anchor.global_position)
	await _phys(3)
	events.clear()
	await _tap(&"grapple")
	var pulling := func() -> bool: return player.state == Player.State.GRAPPLE and player.global_position.z < -10.0
	await _wait_until(pulling, 3.0)
	var tick_start := [Vector3.ZERO]
	var at := {release = Vector3.INF, before_run = Vector3.INF}
	var on_tick := func() -> void: tick_start[0] = player.velocity
	var on_release := func(_arrived: bool) -> void:
		at.release = player.velocity
		at.pulled = tick_start[0]
	var on_start := func(_n: Vector3) -> void: at.before_run = player.velocity
	physics_frame.connect(on_tick)
	player.grapple_finished.connect(on_release)
	player.wall_run_started.connect(on_start)
	await _tap(&"grapple")
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left") # toward the wall
	var ran := await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 1.0)
	await physics_frame
	var first_run_tick := player.velocity
	physics_frame.disconnect(on_tick)
	player.grapple_finished.disconnect(on_release)
	player.wall_run_started.disconnect(on_start)
	_check("grapple release keeps the pull's way, trimmed to what a body carries",
			(at.release as Vector3).is_equal_approx(player.grapple.release_velocity(at.get("pulled", Vector3.ZERO))),
			"%s -> %s" % [at.get("pulled"), at.release])
	_check("grapple -> release -> steer to the wall: wall-run", ran and events.slice(0, 4) == [&"fired", &"pull", &"released", &"wall_run"],
			str(events))
	var entry_along := -(at.before_run as Vector3).z
	_check("the run carries the grapple momentum (no boost, only the usual bleed)", entry_along > settings.sprint_speed + 2.5
			and -first_run_tick.z <= entry_along + 0.01 and -first_run_tick.z > entry_along - 0.5,
			"%.2f m/s arriving, %.2f m/s on the wall" % [entry_along, -first_run_tick.z])
	_release_all()

	# Wall-run, wall-jump, then grapple out of the jump.
	events.clear()
	var entered := await _run_and_jump(Vector3(face_x + 0.6, 0.05, -1.0), 0.0)
	await _phys(8)
	Input.action_release(&"jump")
	await _tap(&"jump")
	_aim_at(anchor.global_position)
	await _phys(2)
	var airborne := not player.is_on_floor() and player.state == Player.State.MOVE
	await _tap(&"grapple")
	await _wait_until(func() -> bool: return events.has(&"arrived") or events.has(&"released"), 4.0)
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	await _phys(5)
	_check("wall-jump -> grapple: fires from the air after the jump, pulls, arrives", entered and airborne
			and events == [&"wall_run", &"wall_jump", &"fired", &"pull", &"arrived"], str(events))
	_check("lands on the end tower", player.is_on_floor() and absf(player.global_position.y - 7.0) < 0.1, str(player.global_position))
	_release_all()

	# The grapple can also be fired straight from a wall-run.
	events.clear()
	entered = await _run_and_jump(Vector3(face_x + 0.6, 0.05, -1.0), 0.0)
	await _phys(6)
	_aim_at(anchor.global_position)
	await _phys(2)
	await _tap(&"grapple")
	_check("grapple straight from a wall-run: leaves the wall, arrow away", entered and events.slice(0, 3) == [&"wall_run", &"wall_run_end", &"fired"]
			and player.state in [Player.State.GRAPPLE_FIRE, Player.State.GRAPPLE], str(events))
	_release_all()
	player.grapple_fired.disconnect(on_fired)
	player.grapple_started.disconnect(on_pull)
	player.grapple_finished.disconnect(on_grapple_end)
	player.wall_run_started.disconnect(on_run)
	player.wall_run_finished.disconnect(on_run_end)


func test_wall_run_hint() -> void:
	_section("Wall-run debug readout")
	var face_x := (front_window.get_parent().get_parent().get_node("TraversalPlayground/BasicWallRun/RunWall") as Node3D).global_position.x + 0.3
	var label := root.get_node("Main/DebugHUD/Label") as Label
	_check("the debug HUD turns the readout on", player.debug_wall_run_hint)
	# Sprinting alongside the wall on the ground, steering along it: ready to jump.
	await _place(Vector3(face_x + 0.6, 0.05, -1.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(20)
	await _frames(2)
	_check("sprinting alongside a runnable wall: WALL RUN READY (shown in the HUD)", player.wall_run_hint == "WALL RUN READY"
			and label.text.contains("[WALL RUN READY]"), "'%s'" % player.wall_run_hint)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.5)
	await _phys(1)
	_check("on the wall: WALL RUN", player.wall_run_hint == "WALL RUN", "'%s'" % player.wall_run_hint)
	Input.action_release(&"jump")
	await _phys(6)
	await _tap(&"jump")
	await _phys(1)
	_check("Space off the wall: WALL JUMP", player.wall_run_hint == "WALL JUMP", "'%s'" % player.wall_run_hint)
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	# Walking alongside it: named, with the reason it won't start.
	await _place(Vector3(face_x + 0.6, 0.05, -1.0), 0.0)
	Input.action_press(&"move_forward")
	await _phys(20)
	_check("walking alongside it: 'too slow along it'", player.wall_run_hint == "wall: too slow along it", "'%s'" % player.wall_run_hint)
	# Sprinting a little too far out: in sight, but out of reach.
	await _place(Vector3(face_x + 1.1, 0.05, -1.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _phys(20)
	_check("sprinting 0.75 m off the wall: 'get closer'", player.wall_run_hint == "wall: get closer", "'%s'" % player.wall_run_hint)
	_release_all()
	# Open ground: nothing shown.
	await _place(Vector3(20, 0.05, 30), 0.0)
	Input.action_press(&"move_forward")
	await _phys(10)
	await _frames(2)
	_release_all()
	_check("open ground: no readout", player.wall_run_hint == "" and not label.text.contains("["), "'%s'" % player.wall_run_hint)


func test_playground() -> void:
	_section("Traversal playground")
	var pg := front_window.get_parent().get_parent().get_node("TraversalPlayground")
	var sections := ["BasicWallRun", "WallJump", "WallRunGrapple", "WallRunWindow", "OpenTraversal"]
	var starts := get_nodes_in_group(&"playground_start")
	var anchors := pg.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is GrappleAnchor)
	_check("five sections, each with a start marker", sections.all(func(s: String) -> bool: return pg.has_node(s))
			and starts.size() == 5, "%d starts" % starts.size())
	_check("playground grapple anchors in place and enabled", anchors.size() == 5
			and anchors.all(func(a: GrappleAnchor) -> bool: return a.enabled), "%d anchors" % anchors.size())
	# Debug keys 1-5 jump to the section starts.
	await _place(Vector3(20, 0.05, 30), 0.0)
	var key := InputEventKey.new()
	key.keycode = KEY_3
	key.physical_keycode = KEY_3
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	key.pressed = false
	Input.parse_input_event(key)
	await _phys(8)
	var start3 := pg.get_node("WallRunGrapple/Start3") as Node3D
	_check("debug key 3 jumps to section 3's start", player.global_position.distance_to(start3.global_position) < 0.3
			and player.last_action == &"section_3", "%s" % player.global_position)

	# 1: the angled wall runs with the wall on the right.
	var ran := await _run_and_jump(Vector3(-29.4, 0.05, 44.7), 15.0) # 4 m before the angled wall, in its lane
	var right := player.global_basis.x
	_check("1: angled wall - wall-run with the wall on the right", ran and player.wall_normal.dot(right) < -0.9,
			"normal %s" % player.wall_normal)
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)

	# 2: wall-run, wall-jump across, grab the rooftop no jump from the ground reaches.
	var r := await _pg_route_walljump()
	_check("2: wall-run -> wall-jump -> grab -> climb onto the 4 m rooftop", r.ran and r.jumped and r.grabbed
			and r.on_floor and absf(r.pos.y - 4.0) < 0.1, "%s" % r)
	await _place(Vector3(-52.5, 0.05, -60.0), 90.0) # facing the rooftop's side from the ground
	Input.action_press(&"move_forward")
	await _phys(20)
	Input.action_press(&"jump")
	await _phys(60)
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	_check("2: a plain jump from the ground can't reach that rooftop", player.global_position.y < 0.1
			and player.state == Player.State.MOVE, "%s %s" % [player.last_action, player.global_position])

	# 3: ramp up, wall-run at height, grapple from the wall to the tall tower.
	r = await _pg_route_grapple(pg.get_node("WallRunGrapple/G_Anchor") as GrappleAnchor)
	_check("3: ramp -> wall-run at height -> grapple from the wall -> tower top", r.ran and r.fired_from_wall
			and r.arrived and absf(r.pos.y - 14.0) < 0.1, "%s" % r)

	# 4: ramp up, wall-run, wall-jump and steer in line, E through the upper window.
	r = await _pg_route_window()
	_check("4: ramp -> wall-run -> wall-jump -> E dives in through the upper window", r.ran and r.dove
			and r.inside, "%s" % r)
	var exit := await _pg_exit_window(pg.get_node("WallRunWindow/H_BeyondAnchor") as GrappleAnchor)
	_check("4: the far window dives out high (airborne), tower beyond in grapple reach", exit.dove and exit.airborne
			and exit.target_seen, "%s" % exit)

	# 5: from deck B, wall-run across the 7 m gap (too far to jump) onto deck C.
	await _place(Vector3(-6.0, 3.05, -69.9), -90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.x > -2.7, 3.0)
	Input.action_press(&"jump")
	ran = await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 3.0)
	_release_all()
	_check("5: wall-run across the 7 m deck gap", ran and player.global_position.x > 4.5
			and absf(player.global_position.y - 3.0) < 0.1, str(player.global_position))
	# Leave the camera as later tests expect it (the routes above aimed it up).
	player.camera.pitch = deg_to_rad(-12.0)
	player.camera.yaw = 0.0


## Section 2 route: sprint alongside the wall, wall-run, wall-jump across the
## gap steering toward the rooftop, grab its edge and climb up.
func _pg_route_walljump() -> Dictionary:
	var out := {ran = false, jumped = false, grabbed = false, on_floor = false, pos = Vector3.ZERO}
	await _place(Vector3(-51.6, 0.05, -37.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -46.5, 3.0)
	Input.action_press(&"jump")
	out.ran = await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _phys(12)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.state != Player.State.WALL_RUN, 0.2)
	out.jumped = player.last_action == &"wall_jump"
	Input.action_press(&"move_left") # toward the rooftop
	out.grabbed = await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 2.0)
	_release_all()
	await _phys(10)
	await _tap(&"jump") # climb up
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	await _phys(10)
	out.on_floor = player.is_on_floor()
	out.pos = player.global_position
	return out


## Section 3 route: sprint up the ramp and off the deck into a wall-run, then
## grapple to the tower from the wall.
func _pg_route_grapple(anchor: GrappleAnchor) -> Dictionary:
	var out := {ran = false, fired_from_wall = false, arrived = false, pos = Vector3.ZERO}
	await _place(Vector3(-31.1, 0.05, -30.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < -51.6, 4.0)
	Input.action_press(&"jump")
	out.ran = await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	await _phys(10)
	_aim_at(anchor.global_position)
	await _phys(2)
	var on_fire := func(_a: GrappleAnchor) -> void: out.fired_from_wall = player.last_action == &"grapple_fire" and not player.is_on_floor()
	var on_end := func(arrived: bool) -> void: out.arrived = arrived
	player.grapple_fired.connect(on_fire)
	player.grapple_finished.connect(on_end)
	var was_running := player.state == Player.State.WALL_RUN
	await _tap(&"grapple")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.last_action.begins_with("grapple_"), 4.0)
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	await _phys(5)
	player.grapple_fired.disconnect(on_fire)
	player.grapple_finished.disconnect(on_end)
	_release_all()
	out.fired_from_wall = out.fired_from_wall and was_running
	out.pos = player.global_position
	return out


## Section 4 route: sprint up the ramp and off the deck into a wall-run along
## the wing, wall-jump about halfway (the push off the wall carries the player
## in line with the window), hold forward, E through it.
func _pg_route_window() -> Dictionary:
	var out := {ran = false, dove = false, inside = false, pos = Vector3.ZERO}
	var ids := _record_traversals()
	await _place(Vector3(-56.1, 0.05, 48.5), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.global_position.z < 32.4, 4.0)
	Input.action_press(&"jump")
	out.ran = await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.6)
	Input.action_release(&"jump")
	await _wait_until(func() -> bool: return player.global_position.z < 26.5, 1.0)
	Input.action_press(&"jump") # wall-jump
	await _wait_until(func() -> bool: return player.prompt.hint_text() != "", 1.0)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.has(&"window_dive") and player.state == Player.State.MOVE, 2.0)
	_release_all()
	await _phys(10)
	_stop_recording()
	out.dove = ids.has(&"window_dive")
	out.pos = player.global_position
	out.inside = player.is_on_floor() and absf(out.pos.y - 3.0) < 0.1 and out.pos.z > 14.3 and out.pos.z < 18.7
	return out


## Section 4, the way out: E at the far window from inside the room (a high
## window: the dive ends in the air), with the tower beyond targeted.
func _pg_exit_window(anchor: GrappleAnchor) -> Dictionary:
	var out := {dove = false, airborne = false, target_seen = false}
	await _place(Vector3(-53.8, 3.05, 16.5), 0.0)
	_aim_at(anchor.global_position)
	await _tap(&"traverse")
	out.dove = await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 1.0)
	await _wait_until(func() -> bool: return player.state != Player.State.TRAVERSAL, 2.0)
	await _phys(2) # (is_on_floor() only updates once normal movement moves the body again)
	out.airborne = not player.is_on_floor() and player.global_position.y > 2.0
	_aim_at(anchor.global_position)
	await _phys(2)
	out.target_seen = player.grapple.target == anchor
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	return out


## Sprints (or walks) forward from `start` facing `yaw` degrees, then jumps
## holding Space; `forward` false lets go of forward at the jump. True if a
## wall-run starts within half a second.
func _run_and_jump(start: Vector3, yaw: float, sprint := true, forward := true) -> bool:
	await _place(start, yaw)
	Input.action_press(&"move_forward")
	if sprint:
		Input.action_press(&"sprint")
	await _phys(18)
	Input.action_press(&"jump")
	if not forward:
		Input.action_release(&"move_forward")
	return await _wait_until(func() -> bool: return player.state == Player.State.WALL_RUN, 0.5)


## World-space ends of the drawn grapple cable: [player end, far end].
func _cable_ends() -> Array[Vector3]:
	var xform := player.grapple._cable.global_transform
	var ends: Array[Vector3] = [xform.origin - xform.basis.y * 0.5, xform.origin + xform.basis.y * 0.5]
	return ends


## A temporary 3x3 m wall centred on `center`, square to the line toward `facing`.
func _temp_wall(center: Vector3, facing: Vector3) -> StaticBody3D:
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.3)
	var shape := CollisionShape3D.new()
	shape.shape = box
	var wall := StaticBody3D.new()
	wall.add_child(shape)
	root.add_child(wall)
	wall.look_at_from_position(center, facing)
	return wall


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


func test_idle_animation() -> void:
	_section("Vigilante idle animation")
	var lib := load("res://assets/characters/vigilante/animations/vigilante_animations.tres") as AnimationLibrary
	_check("animation library loads", lib != null)
	if lib == null:
		return
	var idle := lib.get_animation(&"idle")
	_check("library contains 'idle'", idle != null,
			str(lib.get_animation_list()))
	_check("idle is 2-3 s and loops", idle.length >= 2.0 and idle.length <= 3.0 and idle.loop_mode == Animation.LOOP_LINEAR,
			"%.1f s, loop_mode %d" % [idle.length, idle.loop_mode])

	# A standalone copy of the model, far from the level, with its own player.
	var model: Node3D = (load("res://assets/characters/vigilante/vigilante_player.glb") as PackedScene).instantiate()
	model.position = Vector3(200, 0, 200)
	root.add_child(model)
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var tracked: Array[String] = []
	var bad_paths: Array[String] = []
	for t in idle.get_track_count():
		var path := idle.track_get_path(t)
		var bone := path.get_concatenated_subnames()
		tracked.append(bone)
		if String(path.get_concatenated_names()) != "Skeleton3D" or skel.find_bone(bone) < 0:
			bad_paths.append(str(path))
	_check("every track targets a real bone on the model's Skeleton3D", bad_paths.is_empty() and tracked.size() > 0, str(bad_paths))
	# Idle is built on the neutral stance: it must carry every neutral track, and
	# the pelvis/legs must be held exactly at neutral (no motion there).
	var neutral := lib.get_animation(&"neutral")
	var missing := []
	var legs_moving := []
	var leg_chain := ["joint_pelvis", "joint_thigh.L", "joint_shin.L", "joint_foot.L", "joint_thigh.R", "joint_shin.R", "joint_foot.R"]
	for nt in neutral.get_track_count():
		var it := idle.find_track(neutral.track_get_path(nt), neutral.track_get_type(nt))
		if it < 0:
			missing.append(str(neutral.track_get_path(nt)))
			continue
		var bone := neutral.track_get_path(nt).get_concatenated_subnames()
		if leg_chain.has(bone):
			for k in idle.track_get_key_count(it):
				if idle.track_get_key_value(it, k) != neutral.track_get_key_value(nt, 0):
					legs_moving.append(bone)
					break
	_check("idle holds the whole neutral stance (every neutral track)", missing.is_empty(), str(missing))
	_check("pelvis and legs held exactly at neutral", legs_moving.is_empty(), str(legs_moving))
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library(&"", lib)

	# Reference: the neutral stance itself.
	ap.play(&"neutral")
	ap.seek(0.0, true)
	await process_frame
	await process_frame
	var feet := [skel.find_bone("joint_foot.L"), skel.find_bone("joint_foot.R")]
	var feet_ref: Array[Transform3D] = [skel.get_bone_global_pose(feet[0]), skel.get_bone_global_pose(feet[1])]
	var boots := [model.find_child("boot_L", true, false) as Node3D, model.find_child("boot_R", true, false) as Node3D]
	var boots_ref: Array[Vector3] = [boots[0].global_position, boots[1].global_position]
	var attachments := model.find_children("*", "BoneAttachment3D", true, false)
	var watched := {}
	var neutral_rot := {}
	for name in tracked:
		var b := skel.find_bone(name)
		watched[name] = b
		neutral_rot[name] = skel.get_bone_pose_rotation(b)

	ap.play(&"idle")
	var samples := []
	var feet_drift := 0.0
	var detach := 0.0
	var max_angle := 0.0
	var start_angle := 0.0
	var spine_angles := []
	var worst_arm := 0.0
	var widest_hand := 0.0
	var hands_clear := true
	var min_gap := INF
	var t := 0.0
	while t < idle.length - 0.001:
		ap.seek(t, true)
		await process_frame
		await process_frame
		var pose := {}
		for name in watched:
			var q := skel.get_bone_pose_rotation(watched[name])
			pose[name] = q
			var off := rad_to_deg(q.angle_to(neutral_rot[name]))
			max_angle = maxf(max_angle, off)
			if t == 0.0:
				start_angle = maxf(start_angle, off)
		spine_angles.append(rad_to_deg((pose[&"joint_spine"] as Quaternion).angle_to(neutral_rot[&"joint_spine"])))
		samples.append(pose)
		worst_arm = maxf(worst_arm, maxf(_arm_angle(skel, ".L", false), _arm_angle(skel, ".R", false)))
		for side in ["L", "R"]:
			var hand_box := _mesh_box(model, "hand_" + side)
			widest_hand = maxf(widest_hand, absf(skel.get_bone_global_pose(skel.find_bone("joint_hand." + side)).origin.x))
			for body in ["thigh_" + side, "pelvis", "belt"]:
				var body_box := _mesh_box(model, body)
				hands_clear = hands_clear and hand_box.has_volume() and not hand_box.intersects(body_box)
				min_gap = minf(min_gap, hand_box.position.x - body_box.end.x if side == "L" else body_box.position.x - hand_box.end.x)
		for i in 2:
			feet_drift = maxf(feet_drift, skel.get_bone_global_pose(feet[i]).origin.distance_to(feet_ref[i].origin))
			feet_drift = maxf(feet_drift, boots[i].global_position.distance_to(boots_ref[i]))
		for a in attachments:
			var ba := a as BoneAttachment3D
			var expected := skel.global_transform * skel.get_bone_global_pose(ba.bone_idx)
			detach = maxf(detach, ba.global_transform.origin.distance_to(expected.origin))
		t += 0.1
	_check("idle starts from the neutral stance (t=0 within 1.5 deg)", start_angle < 1.5, "%.2f deg" % start_angle)
	_check("skeleton actually moves (spine breathes)", spine_angles.max() > 0.3, "spine up to %.2f deg" % spine_angles.max())
	_check("motion stays subtle (every bone within 3 deg of neutral)", max_angle > 0.3 and max_angle < 3.0, "max %.2f deg" % max_angle)
	_check("never returns toward the A-pose (arms within 12 deg of vertical all cycle)", worst_arm < 12.0,
			"worst %.1f deg (A-pose 41.3)" % worst_arm)
	_check("arms stay beside the body all cycle", widest_hand < 0.30, "hand x up to %.3f m" % widest_hand)
	_check("hands clear of thighs, pelvis and belt all cycle", hands_clear, "closest sideways gap %.3f m" % min_gap)
	# Seamless loop: the jump from the last sample back to the first is no bigger than a normal step.
	var biggest_step := 0.0
	for i in samples.size():
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[(i + 1) % samples.size()]
		for name in a:
			biggest_step = maxf(biggest_step, rad_to_deg((a[name] as Quaternion).angle_to(b[name])))
	var wrap_step := 0.0
	for name in samples[0]:
		wrap_step = maxf(wrap_step, rad_to_deg((samples[-1][name] as Quaternion).angle_to(samples[0][name])))
	_check("loops seamlessly (end -> start step no bigger than any other)", wrap_step <= biggest_step + 0.001,
			"wrap %.3f deg, largest step %.3f deg" % [wrap_step, biggest_step])
	_check("feet stay planted (vs neutral)", feet_drift < 0.0005, "max drift %.5f m" % feet_drift)
	_check("no body part detaches from its bone", detach < 0.0005, "max offset %.5f m across %d attachments" % [detach, attachments.size()])
	var pos_before := ap.current_animation_position
	ap.play(&"idle")
	await _real_wait(0.5)
	_check("plays in real time and keeps looping", ap.is_playing() and ap.current_animation == &"idle")
	ap.seek(idle.length + 0.4, true)
	_check("playback wraps past the end (loop)", absf(ap.current_animation_position - 0.4) < 0.05 and ap.is_playing(),
			"position %.2f (from %.2f)" % [ap.current_animation_position, pos_before])
	model.queue_free()

	# The comparison preview: neutral, idle frozen at start / inhale / exhale,
	# and idle playing live.
	var preview: Node = load("res://scenes/test/vigilante_idle_preview.tscn").instantiate()
	preview.set("position", Vector3(300, 0, 300))
	root.add_child(preview)
	await _frames(5)
	var get_player := func(n: String) -> AnimationPlayer: return preview.get_node_or_null(n) as AnimationPlayer
	var p_neutral: AnimationPlayer = get_player.call("NeutralPlayer")
	var p_live: AnimationPlayer = get_player.call("IdleLivePlayer")
	var frozen_ok := true
	for entry in [["IdleStartPlayer", 0.0], ["IdleInhalePlayer", 0.75], ["IdleExhalePlayer", 2.25]]:
		var p: AnimationPlayer = get_player.call(entry[0])
		# A paused player reports current_animation as ""; the clip is in assigned_animation.
		frozen_ok = frozen_ok and p != null and p.assigned_animation == &"idle" and not p.is_playing() \
				and absf(p.current_animation_position - entry[1]) < 0.01
	_check("idle preview: neutral + idle start / inhale / exhale frozen + idle live",
			p_neutral != null and p_neutral.current_animation == &"neutral" and frozen_ok
			and p_live != null and p_live.is_playing() and p_live.current_animation == &"idle")
	preview.queue_free()
	await _frames(2)
	_check("player model is not animated (idle not connected to gameplay)",
			player.find_children("*", "AnimationPlayer", true, false).is_empty())


func test_neutral_stance() -> void:
	_section("Vigilante neutral stance")
	var lib := load("res://assets/characters/vigilante/animations/vigilante_animations.tres") as AnimationLibrary
	var neutral := lib.get_animation(&"neutral") if lib else null
	_check("neutral animation exists and loads", neutral != null and ResourceLoader.exists("res://assets/characters/vigilante/animations/neutral.tres"))
	if neutral == null:
		return
	_check("library contains both neutral and idle", lib.has_animation(&"neutral") and lib.has_animation(&"idle")
			and lib.get_animation_list().size() == 2, str(lib.get_animation_list()))
	var static_pose := true
	for t in neutral.get_track_count():
		static_pose = static_pose and neutral.track_get_key_count(t) == 1
	_check("static pose in a looping clip (loop-safe)", static_pose and neutral.loop_mode == Animation.LOOP_LINEAR,
			"%d tracks, %.1f s" % [neutral.get_track_count(), neutral.length])

	var model: Node3D = (load("res://assets/characters/vigilante/vigilante_player.glb") as PackedScene).instantiate()
	model.position = Vector3(220, 0, 220)
	root.add_child(model)
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bad := []
	for t in neutral.get_track_count():
		var path := neutral.track_get_path(t)
		if String(path.get_concatenated_names()) != "Skeleton3D" or skel.find_bone(path.get_concatenated_subnames()) < 0:
			bad.append(str(path))
	_check("every track targets a real bone", bad.is_empty(), str(bad))
	var rest_pose := func(bone: String) -> Transform3D: return skel.get_bone_global_rest(skel.find_bone(bone))
	var boots := [model.find_child("boot_L", true, false) as Node3D, model.find_child("boot_R", true, false) as Node3D]
	await process_frame
	var boots_rest: Array[Vector3] = [boots[0].global_position, boots[1].global_position]
	_check("rest pose is still the authored A-pose", absf(_arm_angle(skel, ".L", true) - 41.25) < 1.0,
			"upper arm %.1f deg from vertical at rest" % _arm_angle(skel, ".L", true))

	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library(&"", lib)
	ap.play(&"neutral")
	ap.seek(0.0, true)
	await process_frame
	await process_frame
	var g := func(bone: String) -> Transform3D: return skel.get_bone_global_pose(skel.find_bone(bone))
	var arm_l := _arm_angle(skel, ".L", false)
	var arm_r := _arm_angle(skel, ".R", false)
	_check("arms out of the A-pose (hanging within 12 deg of vertical)", arm_l < 12.0 and arm_r < 12.0,
			"L %.1f / R %.1f deg (rest 41.3)" % [arm_l, arm_r])
	var hand_l: Vector3 = g.call("joint_hand.L").origin
	var hand_r: Vector3 = g.call("joint_hand.R").origin
	var rest_hand_l: Vector3 = rest_pose.call("joint_hand.L").origin
	_check("hands brought in beside the hips", absf(hand_l.x) < 0.30 and absf(hand_r.x) < 0.30 and absf(rest_hand_l.x) - absf(hand_l.x) > 0.2,
			"hand x %.2f / %.2f (rest %.2f)" % [hand_l.x, hand_r.x, rest_hand_l.x])
	_check("hands hang at hip / upper-thigh height", hand_l.y > 0.7 and hand_l.y < 0.95, "hand joint y %.2f" % hand_l.y)
	var elbow := rad_to_deg((g.call("joint_forearm.L").origin - g.call("joint_upperarm.L").origin).angle_to(
			g.call("joint_hand.L").origin - g.call("joint_forearm.L").origin))
	_check("elbows relaxed, not bent hard", elbow > 5.0 and elbow < 25.0, "%.1f deg" % elbow)
	var knee := rad_to_deg((g.call("joint_shin.L").origin - g.call("joint_thigh.L").origin).angle_to(
			g.call("joint_foot.L").origin - g.call("joint_shin.L").origin))
	_check("knees soft, not locked or deep", knee > 5.0 and knee < 20.0, "%.1f deg" % knee)

	# Hands stay on the arms and clear of the legs and hips.
	var hand_attached := hand_l.distance_to(g.call("joint_forearm.L").origin)
	_check("hands remain attached to the forearms", absf(hand_attached - 0.262) < 0.001, "%.4f m" % hand_attached)
	var clear := true
	var boxes_found := true
	var gap := INF
	for side in ["L", "R"]:
		var hand_box := _mesh_box(model, "hand_" + side)
		boxes_found = boxes_found and hand_box.has_volume()
		for body in ["thigh_" + side, "pelvis", "belt"]:
			var body_box := _mesh_box(model, body)
			boxes_found = boxes_found and body_box.has_volume()
			clear = clear and not hand_box.intersects(body_box)
			# Sideways clearance between facing edges (+X is the character's left).
			var edge_gap := hand_box.position.x - body_box.end.x if side == "L" else body_box.position.x - hand_box.end.x
			gap = minf(gap, edge_gap)
	_check("hands clear of thighs, pelvis and belt", boxes_found and clear, "found=%s, closest sideways gap %.3f m" % [boxes_found, gap])

	# Feet planted exactly, flat as at rest.
	var foot_drift := 0.0
	var foot_turn := 0.0
	for side in [".L", ".R"]:
		var posed: Transform3D = g.call("joint_foot" + side)
		var rest: Transform3D = rest_pose.call("joint_foot" + side)
		foot_drift = maxf(foot_drift, posed.origin.distance_to(rest.origin))
		foot_turn = maxf(foot_turn, rad_to_deg(posed.basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion())))
	for i in 2:
		foot_drift = maxf(foot_drift, boots[i].global_position.distance_to(boots_rest[i]))
	_check("feet stay planted and flat", foot_drift < 0.001 and foot_turn < 0.5, "drift %.4f m, turn %.2f deg" % [foot_drift, foot_turn])
	var detach := 0.0
	for a in model.find_children("*", "BoneAttachment3D", true, false):
		var ba := a as BoneAttachment3D
		detach = maxf(detach, ba.global_position.distance_to((skel.global_transform * skel.get_bone_global_pose(ba.bone_idx)).origin))
	_check("no body parts detach", detach < 0.0005, "max %.5f m" % detach)
	var head_up := (g.call("joint_head").basis.y as Vector3).normalized()
	_check("head upright, looking forward", rad_to_deg(head_up.angle_to(Vector3.UP)) < 3.0, "%.1f deg off vertical" % rad_to_deg(head_up.angle_to(Vector3.UP)))
	ap.seek(neutral.length * 0.99, true)
	await process_frame
	await process_frame
	_check("pose identical across the loop", (g.call("joint_hand.L").origin as Vector3).distance_to(hand_l) < 0.0001)
	model.queue_free()

	var preview: Node = load("res://scenes/test/vigilante_neutral_preview.tscn").instantiate()
	preview.set("position", Vector3(320, 0, 320))
	root.add_child(preview)
	await _frames(5)
	var players := preview.find_children("*", "AnimationPlayer", true, false)
	_check("neutral preview shows 3 views playing neutral", players.size() == 3
			and players.all(func(p: AnimationPlayer) -> bool: return p.is_playing() and p.current_animation == &"neutral"))
	preview.queue_free()
	await _frames(2)
	_check("still not connected to the player", player.find_children("*", "AnimationPlayer", true, false).is_empty())


## Upper arm angle from straight down, in degrees (rest or current pose).
func _arm_angle(skel: Skeleton3D, side: String, rest: bool) -> float:
	var joint := func(bone: String) -> Vector3:
		var i := skel.find_bone(bone + side)
		return (skel.get_bone_global_rest(i) if rest else skel.get_bone_global_pose(i)).origin
	return rad_to_deg((joint.call("joint_forearm") - joint.call("joint_upperarm")).angle_to(Vector3.DOWN))


## World AABB of the named MeshInstance3D (its BoneAttachment3D parent shares
## the name, so search meshes only). Empty AABB if missing.
func _mesh_box(model: Node3D, name: String) -> AABB:
	var found := model.find_children(name, "MeshInstance3D", true, false)
	if found.is_empty():
		return AABB()
	var mi := found[0] as MeshInstance3D
	return mi.global_transform * mi.get_aabb()


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


## Sends a real key event, or mouse button event for mouse-bound actions
## (reaches _input handlers like a keyboard / mouse would).
func _key_event(action: StringName, pressed: bool) -> void:
	if MOUSE_FOR.has(action):
		_mouse_button(MOUSE_FOR[action], pressed)
		return
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
