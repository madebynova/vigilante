extends SceneTree
## Checks for the game layer on top of the movement: the landing roll and
## hard landings, letting go of the grapple, the grapple's balance (momentum
## pull, nocking, the world stopping a pull), input held through quick moves,
## the grapple reticle readout and prompts (in a bare lab built in code), then
## the first mission in the real city scene: briefing, route (with and without
## the grapple), the window -> 180 -> grapple move, pickup, finish, best time,
## restart, pause and controls. Everything goes through the Input
## system like the other suites.
##
## Run headless:
##   godot --headless --path . -s res://tests/game_test.gd

const Kit := preload("res://tools/city/city_kit.gd")

const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"sprint", &"jump", &"crouch", &"traverse", &"grapple", &"bullet_time"]
const KEY_FOR := {&"move_forward": KEY_W, &"move_left": KEY_A, &"move_back": KEY_S,
		&"move_right": KEY_D, &"jump": KEY_SPACE, &"traverse": KEY_E, &"bullet_time": KEY_F,
		&"crouch": KEY_C, &"sprint": KEY_SHIFT, &"debug_respawn": KEY_R}
const MOUSE_FOR := {&"grapple": MOUSE_BUTTON_RIGHT}
const SAVE_PATH := "user://game_test.cfg"

var player: Player
var settings: MovementSettings
var lab: Node3D
var kit: Kit
var main: Node
var mission: Mission
var passed := 0
var failed := 0


func _initialize() -> void:
	SaveData.path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	lab = Node3D.new()
	lab.name = "Lab"
	root.add_child(lab)
	kit = Kit.new(lab)
	_build_lab()
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	settings = player.settings
	_run.call_deferred()


func _run() -> void:
	await _phys(20)
	await test_landing()
	await test_roll()
	await test_release()
	await test_grapple_balance()
	await test_obstruction()
	await test_held_input()
	await test_window_buffer()
	await test_e_never_vaults()
	await test_reticle()
	await test_hang_prompt()
	await _load_city()
	await test_mission_start()
	await test_mission_route()
	await test_parkour_route()
	await test_window_turn_grapple()
	await test_mission_restart()
	await test_mission_assisted()
	await test_pause_and_controls()
	await test_roll_tip()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("\n==== %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)


# --- Lab -----------------------------------------------------------------------

func _build_lab() -> void:
	kit.box("Ground", -300.0, 300.0, -1.0, 0.0, -300.0, 300.0, Kit.PAVEMENT)
	# Towers to sprint off (east edge at x + 6), open ground beyond.
	for h: float in [3.5, 7.0, 14.0]:
		var x := _tower_x(h)
		kit.building("Drop%d" % int(h), x, x + 6.0, 50.0, 56.0, h, Kit.ROOF, 0.0, false)
	# A roof with an anchor on its south edge, for steep pulls up its face.
	kit.building("PullBlock", 210.0, 220.0, -10.0, 0.0, 10.5, Kit.GRAPPLE, 0.0, false)
	kit.anchor("PullAnchor", Vector3(215.0, 11.0, -0.4))
	# A waist-high wall to vault, a tower with an anchor beyond it.
	kit.box("VaultWall", 238.0, 246.0, 0.0, 1.0, -10.0, -9.7, Kit.PROP)
	kit.building("VaultTower", 240.0, 244.0, -30.0, -26.0, 6.0, Kit.GRAPPLE, 0.0, false)
	kit.anchor("VaultAnchor", Vector3(242.0, 6.5, -26.4))
	# A 2.6 m ledge to hang from.
	kit.building("HangBlock", 260.0, 266.0, -6.0, 0.0, 2.6, Kit.ROOF, 0.0, false)
	# A dive window (sill 0.9) in a wall facing -Z, a room behind it.
	kit.wall("DiveWall", "z", -40.0, 0.3, 294.0, 306.0, 0.0, 3.6, Kit.ROOF, [Kit.window_hole(300.0, 0.9)])
	kit.box("DiveRoof", 294.0, 306.0, 3.6, 3.9, -46.0, -39.85, Kit.ROOF)
	kit.dive_window("DiveWindow", "z", -40.0, 300.0, 0.9)
	# Reticle: an anchor far out of range, and one hidden behind a wall.
	kit.anchor("FarAnchor", Vector3(0.0, 3.0, 50.0))
	kit.building("Screen", 20.0, 30.0, 20.0, 21.0, 8.0, Kit.ROOF, 0.0, false)
	kit.anchor("HiddenAnchor", Vector3(25.0, 3.0, 30.0))
	kit.building("NearScreen", 32.0, 38.0, 20.0, 21.0, 8.0, Kit.ROOF, 0.0, false)
	kit.anchor("NearHiddenAnchor", Vector3(35.0, 3.0, 23.0))
	# A second anchor in reach of the pull block's roof (grapple -> grapple).
	kit.building("NockTower", 222.0, 226.0, -20.0, -16.0, 12.5, Kit.GRAPPLE, 0.0, false)
	kit.anchor("NockAnchor", Vector3(224.0, 13.0, -16.4))


## West edge of the drop tower `h` m tall.
static func _tower_x(h: float) -> float:
	return {3.5: 100.0, 7.0: 130.0, 14.0: 160.0}[h]


## Sprints east off the tower `h` m tall; `roll` taps crouch just before
## touchdown. Returns what the landing did.
func _drop(h: float, roll: bool) -> Dictionary:
	var out := {impact = 0.0, rolled = false, staggered = -1, speed_after = 0.0, state_after = -1}
	var x := _tower_x(h)
	await _place(Vector3(x + 1.0, h + 0.05, 53.0), -90.0)
	var on_land := func(s: float) -> void: out.impact = s
	var on_roll := func() -> void: out.rolled = true
	var on_stagger := func(hard: bool) -> void: out.staggered = 1 if hard else 0
	player.landed.connect(on_land)
	player.rolled.connect(on_roll)
	player.staggered.connect(on_stagger)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return not player.is_on_floor(), 3.0)
	if roll:
		await _wait_until(func() -> bool: return player.velocity.y < 0.0 and player.global_position.y < 1.0 + (-player.velocity.y) * 0.08, 4.0)
		await _tap(&"crouch")
	await _wait_until(func() -> bool: return out.impact > 0.0, 4.0)
	await _phys(40)
	out.speed_after = player.horizontal_speed()
	out.state_after = player.state
	_release_all()
	player.landed.disconnect(on_land)
	player.rolled.disconnect(on_roll)
	player.staggered.disconnect(on_stagger)
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	return out


func test_landing() -> void:
	_section("Landing: height matters")
	var low := await _drop(3.5, false)
	_check("one storey (3.5 m): no stagger, sprint kept", low.staggered == -1 and low.speed_after > settings.sprint_speed - 0.3,
			"impact %.1f, %.1f m/s" % [low.impact, low.speed_after])
	var mid := await _drop(7.0, false)
	_check("two storeys (7 m), no roll: a short stagger", mid.staggered == 0 and mid.impact >= player.heavy_landing_speed,
			"impact %.1f" % mid.impact)
	var high := await _drop(14.0, false)
	_check("four storeys (14 m), no roll: floored for longer", high.staggered == 1 and high.impact >= player.hard_landing_speed,
			"impact %.1f" % high.impact)
	var r := await _drop(7.0, true)
	_check("two storeys, crouch tapped just before touchdown: rolls, no stagger, sprint kept", r.rolled and r.staggered == -1
			and r.speed_after > settings.sprint_speed - 0.5, "rolled %s, %.1f m/s" % [r.rolled, r.speed_after])
	var rh := await _drop(14.0, true)
	_check("four storeys with a roll: speed carried, then a short stagger", rh.rolled and rh.staggered == 0,
			"rolled %s stagger %d" % [rh.rolled, rh.staggered])


func test_roll() -> void:
	_section("Roll")
	# Roll then jump out of it.
	var h := 7.0
	var x := _tower_x(h)
	await _place(Vector3(x + 1.0, h + 0.05, 53.0), -90.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return not player.is_on_floor(), 3.0)
	await _wait_until(func() -> bool: return player.velocity.y < 0.0 and player.global_position.y < 1.0 + (-player.velocity.y) * 0.08, 4.0)
	await _tap(&"crouch")
	var rolling := await _wait_until(func() -> bool: return player.state == Player.State.ROLL, 1.0)
	var low := player.is_crouching
	await _phys(12)
	await _tap(&"jump")
	var sprang := await _wait_until(func() -> bool: return player.velocity.y > 3.0, 0.5)
	_check("rolling: body low (crouch height)", rolling and low)
	_check("jump late in the roll springs out of it", sprang and player.state == Player.State.MOVE, str(Player.State.keys()[player.state]))
	_release_all()
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	await _phys(5)
	_check("stands up after the roll", not player.is_crouching)
	# Roll straight into a wall: stops at it, never through it.
	await _place(Vector3(x + 1.0, h + 0.05, 53.0), -90.0)
	var wall := kit.box("RollWall", x + 14.5, x + 15.0, 0.0, 3.0, 45.0, 61.0, Kit.ROOF)
	await _phys(2)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return not player.is_on_floor(), 3.0)
	await _wait_until(func() -> bool: return player.velocity.y < 0.0 and player.global_position.y < 1.0 + (-player.velocity.y) * 0.08, 4.0)
	await _tap(&"crouch")
	await _wait_until(func() -> bool: return player.state == Player.State.ROLL, 1.0)
	await _wait_until(func() -> bool: return player.state != Player.State.ROLL, 1.5)
	_release_all()
	await _phys(10)
	_check("a roll into a wall stops at it (never through)", player.global_position.x < x + 14.5 - 0.3, "x %.2f" % player.global_position.x)
	wall.queue_free()
	await _phys(2)


func test_release() -> void:
	_section("Grapple release by a wall: no launch, ledges catchable")
	var anchor := lab.get_node("PullAnchor") as GrappleAnchor
	for case: Array in [[4.0, false], [8.6, true], [10.2, true]]:
		var rel_y: float = case[0]
		var hold_w: bool = case[1]
		await _place(Vector3(215.0, 0.05, 7.0), 0.0)
		_aim_at(anchor.global_position)
		await _phys(2)
		await _tap(&"grapple")
		await _wait_until(func() -> bool: return player.state == Player.State.GRAPPLE and player.global_position.y > rel_y, 3.0)
		var at := player.global_position
		var pull := player.velocity
		await _tap(&"grapple")
		if hold_w:
			Input.action_press(&"move_forward")
		var top := at.y
		var actions: Array[StringName] = []
		for i in 90:
			top = maxf(top, player.global_position.y)
			if actions.is_empty() or actions.back() != player.last_action:
				actions.append(player.last_action)
			await physics_frame
		_release_all()
		var rise := top - at.y
		if not hold_w:
			_check("let go %.0f m below the edge (pulled up at %.0f m/s): rises no more than a jump" % [anchor.global_position.y - at.y, pull.length()],
					rise <= settings.jump_height + 0.1, "rose %.2f m" % rise)
		else:
			var caught := actions.has(&"ledge_grab") or actions.has(&"mantle") or (player.is_on_floor() and player.global_position.y > 10.0)
			_check("let go %.1f m below the edge, holding W: catches the ledge or carries onto the roof" % (10.5 - at.y), caught,
					"%s, ends at %s" % [actions, player.global_position])
		await _place(Vector3(215.0, 0.05, 7.0), 0.0)


## Pulls up the pull block's face from `start`: standing, or sprinting in
## and jumping first. Returns the top pull speed and whether it arrived.
func _pull(start: Vector3, run_in: bool) -> Dictionary:
	var out := {top = 0.0, arrived = false}
	var anchor := lab.get_node("PullAnchor") as GrappleAnchor
	await _place(start, 0.0)
	if run_in:
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		await _phys(30)
		await _tap(&"jump")
		await _phys(4)
	_aim_at(anchor.global_position)
	await _phys(1)
	var done := [false]
	var on_finish := func(arrived: bool) -> void:
		out.arrived = arrived
		done[0] = true
	player.grapple_finished.connect(on_finish)
	await _tap(&"grapple")
	_release_all()
	while not done[0]:
		if player.state == Player.State.GRAPPLE:
			out.top = maxf(out.top, player.velocity.length())
		await physics_frame
	player.grapple_finished.disconnect(on_finish)
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	return out


func test_grapple_balance() -> void:
	_section("Grapple: strongest on the move, a beat between grapples")
	var g := player.grapple
	var still := await _pull(Vector3(215.0, 0.05, 9.0), false)
	var moving := await _pull(Vector3(215.0, 0.05, 20.0), true)
	_check("from a standstill it winches (%.0f m/s), not a launch" % g.pull_speed_standing, still.arrived
			and absf(still.top - g.pull_speed_standing) < 0.6, "top %.1f m/s" % still.top)
	_check("fired on the move (sprint + jump) it pulls at full speed (%.0f m/s)" % g.pull_speed, moving.arrived
			and moving.top > g.pull_speed - 1.0, "top %.1f m/s" % moving.top)
	# Straight after arriving, the next arrow isn't nocked yet.
	var fired := [0]
	var on_fire := func(_a: GrappleAnchor) -> void: fired[0] += 1
	player.grapple_fired.connect(on_fire)
	var nock := lab.get_node("NockAnchor") as GrappleAnchor
	_aim_at(nock.global_position)
	await _phys(2)
	var aimed := g.target == nock
	await _tap(&"grapple")
	await _phys(3)
	_check("arrive -> fire again at once: the reticle shows the next arrow nocking, no shot", aimed and fired[0] == 0
			and not g.is_ready(), "fired %d, nocked %.2f" % [fired[0], g.nock_fraction()])
	await _wait_until(func() -> bool: return g.is_ready(), g.nock_time + 0.2)
	_aim_at(nock.global_position)
	await _phys(1)
	await _tap(&"grapple")
	await _phys(3)
	_check("%.1f s later: fires" % g.nock_time, fired[0] == 1)
	player.grapple_fired.disconnect(on_fire)
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 5.0)
	# Any parkour move nocks it at once.
	await _place(Vector3(242.0, 0.05, -2.0), 0.0)
	g.start_nock()
	var nocking := not g.is_ready()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 2.0)
	var vaulting := player.state == Player.State.TRAVERSAL
	var ready := g.is_ready()
	_release_all()
	_check("grapple -> parkour (a vault) -> the next arrow is nocked at once", nocking and vaulting and ready)
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)


func test_obstruction() -> void:
	_section("Grapple: the world wins over the pull")
	var anchor := lab.get_node("PullAnchor") as GrappleAnchor
	await _place(Vector3(215.0, 0.05, 22.0), 0.0)
	_aim_at(anchor.global_position)
	await _phys(1)
	var ended := [false, true]
	var on_finish := func(arrived: bool) -> void:
		ended[0] = true
		ended[1] = arrived
	player.grapple_finished.connect(on_finish)
	await _tap(&"grapple")
	await _wait_until(func() -> bool: return player.state == Player.State.GRAPPLE and player.global_position.z < 14.0, 3.0)
	# A wall drops in between: the cable would pass through it.
	var wall := kit.box("Obstacle", 205.0, 225.0, 0.0, 14.0, 9.0, 9.5, Kit.ROOF)
	var nearest := INF
	var frames := 0
	while frames < 60:
		nearest = minf(nearest, player.global_position.z)
		frames += 1
		await physics_frame
	player.grapple_finished.disconnect(on_finish)
	var action := player.last_action
	_check("a wall between the player and the anchor mid-pull: the pull lets go", ended[0] and not ended[1]
			and (action == &"grapple_blocked" or player.state == Player.State.MOVE), "%s %s" % [ended, action])
	_check("never through the wall (stays on its side)", nearest > 9.5 + 0.3, "closest z %.2f" % nearest)
	_check("normal movement takes over (falling, steerable)", player.state == Player.State.MOVE)
	await _wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	wall.queue_free()
	await _phys(2)


func test_held_input() -> void:
	_section("Input held through quick moves")
	var ids := _record_traversals()
	# Jump pressed during a vault goes off as it ends.
	await _place(Vector3(242.0, 0.05, -2.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 2.0)
	await _tap(&"jump")
	var vaulting := player.state == Player.State.TRAVERSAL
	var jumped := await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.velocity.y > 3.0, 1.0)
	_release_all()
	_check("jump pressed mid-vault: jumps as the vault ends", ids.has(&"vault_over") and vaulting and jumped, str(ids))
	await _wait_until(func() -> bool: return player.is_on_floor(), 2.0)
	# Grapple pressed during a vault fires as it ends.
	ids.clear()
	var anchor := lab.get_node("VaultAnchor") as GrappleAnchor
	await _place(Vector3(242.0, 0.05, -2.0), 0.0)
	_aim_at(anchor.global_position)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 2.0)
	var fired := [false]
	var on_fire := func(_a: GrappleAnchor) -> void: fired[0] = true
	player.grapple_fired.connect(on_fire)
	await _tap(&"grapple")
	var during: bool = fired[0]
	await _wait_until(func() -> bool: return fired[0], 1.0)
	player.grapple_fired.disconnect(on_fire)
	_release_all()
	_check("grapple pressed mid-vault: fires as the vault ends (not lost)", ids.has(&"vault_over") and not during and fired[0], str(ids))
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE and player.is_on_floor(), 5.0)
	_stop_recording()


func test_window_buffer() -> void:
	_section("E a moment early still dives")
	var window := lab.get_node("DiveWindow") as TraversalWindow
	var ids := _record_traversals()
	await _place(Vector3(300.0, 0.05, -30.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait_until(func() -> bool: return window.distance_to_wall(player.global_position) < 5.0, 3.0)
	await _tap(&"jump")
	await _wait_until(func() -> bool: return window.distance_to_wall(player.global_position) < window.dive_distance + 0.7, 1.0)
	var early := window.distance_to_wall(player.global_position)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.has(&"window_dive"), 0.5)
	_release_all()
	_check("mid-jump E pressed %.1f m out (reach %.1f m): dives once in reach" % [early, window.dive_distance],
			ids.has(&"window_dive") and early > window.dive_distance, str(ids))
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	# Pressed too early it is forgotten: nothing happens later on its own.
	ids.clear()
	await _place(Vector3(300.0, 0.05, -30.0), 0.0)
	await _tap(&"traverse")
	await _phys(20)
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return window.distance_to_wall(player.global_position) < 1.5, 3.0)
	await _phys(10)
	_release_all()
	_check("E long before reaching the window: walking up to it later does nothing", not ids.has(&"window_dive"), str(ids))
	_stop_recording()


func test_e_never_vaults() -> void:
	_section("E is for windows and ladders only")
	var ids := _record_traversals()
	await _place(Vector3(242.0, 0.05, -9.0), 0.0)
	await _tap(&"traverse")
	await _phys(30)
	_check("E facing a waist-high wall: no vault", ids.is_empty(), str(ids))
	await _tap(&"jump")
	await _phys(30)
	_check("Space there vaults it", ids.has(&"vault_over"), str(ids))
	_stop_recording()
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)


func test_reticle() -> void:
	_section("Grapple reticle readout")
	var g := player.grapple
	await _place(Vector3(0.0, 0.05, 0.0), 180.0)
	_aim_at((lab.get_node("FarAnchor") as Node3D).global_position)
	await _phys(3)
	_check("aiming at an anchor out of range: crossed, OUT OF RANGE", g.target == null and g.aimed != null
			and g.aimed_block == Grapple.Block.TOO_FAR, "%s %d" % [g.aimed, g.aimed_block])
	await _place(Vector3(25.0, 0.05, 5.0), 180.0)
	_aim_at((lab.get_node("HiddenAnchor") as Node3D).global_position)
	await _phys(3)
	_check("an anchor 25 m away hidden behind a building: nothing shown (the world keeps it hidden)", g.target == null
			and g.aimed == null, "%s %d" % [g.aimed, g.aimed_block])
	await _place(Vector3(35.0, 0.05, 12.0), 180.0)
	_aim_at((lab.get_node("NearHiddenAnchor") as Node3D).global_position)
	await _phys(3)
	_check("a nearby anchor just behind a wall: crossed, NO LINE OF SIGHT (explains why)", g.target == null
			and g.aimed != null and g.aimed_block == Grapple.Block.BLOCKED, "%s %d" % [g.aimed, g.aimed_block])
	await _place(Vector3(35.0, 0.05, 17.0), 180.0)
	_aim_at((lab.get_node("NearHiddenAnchor") as Node3D).global_position)
	await _phys(3)
	var blocked_near := g.aimed != null
	await _place(Vector3(40.0, 0.05, 23.0), 90.0)
	_aim_at((lab.get_node("NearHiddenAnchor") as Node3D).global_position)
	await _phys(3)
	_check("round the corner with a clear line: usable again", blocked_near and g.target != null
			and g.target.name == "NearHiddenAnchor", "%s" % g.target)
	await _place(Vector3(242.0, 0.05, -12.0), 0.0)
	_aim_at((lab.get_node("VaultAnchor") as Node3D).global_position)
	await _phys(3)
	_check("aiming at a usable anchor: circled (a target, no cross)", g.target != null and g.aimed == null)
	var hud := player.get_node_or_null("PromptLayer/PlayerHUD") as PlayerHUD
	_check("the player scene carries the reticle HUD", hud != null)


func test_hang_prompt() -> void:
	_section("Prompts")
	await _place(Vector3(263.0, 0.05, 1.2), 0.0)
	Input.action_press(&"move_forward")
	await _phys(4)
	Input.action_press(&"jump")
	var hung := await _wait_until(func() -> bool: return player.state == Player.State.LEDGE_HANG, 1.5)
	_release_all()
	await _phys(2)
	_check("hanging from a ledge: prompt SPACE CLIMB UP", hung and player.prompt.hint_text() == "SPACE CLIMB UP",
			"'%s'" % player.prompt.hint_text())
	await _tap(&"jump")
	await _wait_until(func() -> bool: return player.state == Player.State.MOVE, 2.0)
	await _phys(2)
	_check("climbed up: prompt gone", player.prompt.hint_text() == "", "'%s'" % player.prompt.hint_text())


# --- The mission (city) ------------------------------------------------------------

func _load_city() -> void:
	player.queue_free()
	lab.queue_free()
	await _phys(2)
	main = (load("res://scenes/main/city_main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	settings = player.settings
	mission = main.get_node("Mission")
	await _phys(20)


func test_mission_start() -> void:
	_section("Mission: briefing and first objective")
	var hud := main.get_node("MissionHUD") as MissionHUD
	var dn := get_first_node_in_group(DayNight.GROUP) as DayNight
	_check("the city opens at night for the mission", dn != null and dn.night)
	_check("first objective: the drop, clock waiting", mission.phase == Mission.Phase.READY and mission.step_index == 0
			and mission.current_step().name == "Drop" and is_zero_approx(mission.elapsed))
	var beacon := mission.get_node("Beacon") as Node3D
	var package := mission.get_node("Drop/Package") as Node3D
	_check("beacon on the package, package in place", beacon.visible and package.visible
			and beacon.global_position.distance_to(package.global_position) < 0.5)
	await _frames(3)
	_check("HUD shows the objective and where", _hud_text(hud).contains("Intercept the drop") and _hud_text(hud).contains("Hotel roof"),
			_hud_text(hud))
	await _phys(30)
	_check("looking around doesn't start the clock", mission.phase == Mission.Phase.READY and is_zero_approx(mission.elapsed))
	Input.action_press(&"move_forward")
	await _phys(10)
	_release_all()
	_check("moving starts it", mission.phase == Mission.Phase.RUNNING and mission.elapsed > 0.0, "%.2f s" % mission.elapsed)


## The quick way: out of the door, grapple up the walk-up, grapple the hotel's
## water tower, the package, then grapple back down and across home.
func test_mission_route() -> void:
	_section("Mission: street -> grapple -> grapple -> drop -> grapple home")
	mission.restart()
	await _phys(5)
	var reached: Array[StringName] = []
	var on_reached := func(step: MissionStep, _i: int) -> void: reached.append(step.name)
	mission.step_reached.connect(on_reached)
	var done := [false]
	var on_done := func() -> void: done[0] = true
	mission.completed.connect(on_done)
	var ok := await _walk_to([Vector3(-21.0, 0, 34.0), Vector3(-24.5, 0, 30.5)], true)
	ok = ok and (await _grapple_to(_anchor("DenseBlocks/WalkUp/AnchorWalkUpSouth"))).arrived
	ok = ok and await _walk_to([Vector3(-28.0, 0, 12.0)], true)
	ok = ok and (await _grapple_to(_anchor("DenseBlocks/Hotel/WaterTower/Anchor"))).arrived
	_check("up the walk-up and onto the hotel's water tower by grapple", ok, str(player.global_position))
	var package := mission.get_node("Drop/Package") as Node3D
	ok = await _walk_to([Vector3(-29.0, 0, -11.0), Vector3(-28.0, 0, -17.5), Vector3(-24.8, 0, -19.2)], true)
	await _phys(5)
	_check("the drop: package picked up, objective now home", reached.has(&"Drop") and not package.visible
			and mission.current_step().name == "Home", "%s step %d" % [reached, mission.step_index])
	var beacon := mission.get_node("Beacon") as Node3D
	var home := mission.get_node("Home") as MissionStep
	_check("beacon moved to the safehouse roof", beacon.visible and beacon.global_position.distance_to(home.marker_position()) < 0.5)
	ok = await _walk_to([Vector3(-23.0, 0, -12.0), Vector3(-23.5, 0, -4.0)], true)
	ok = ok and await _walk_to([Vector3(-23.5, 0, -2.2)], false)
	ok = ok and (await _grapple_to(_anchor("DenseBlocks/WalkUp/AnchorWalkUpYard"))).arrived
	ok = ok and await _walk_to([Vector3(-21.5, 0, 16.0), Vector3(-21.5, 0, 20.0)], true)
	var slow := [false]
	var on_slow := func() -> void: slow[0] = true
	player.bullet_time.started.connect(on_slow)
	await _grapple_to(_anchor("SafehouseDistrict/Safehouse/AnchorSafehouseRoof"))
	await _wait_until(func() -> bool: return done[0], 2.0)
	player.bullet_time.started.disconnect(on_slow)
	mission.step_reached.disconnect(on_reached)
	mission.completed.disconnect(on_done)
	var r := mission.result
	_check("home: the run completes with a time and a rating", done[0] and mission.phase == Mission.Phase.COMPLETE
			and r.time > 5.0 and r.rating != "", "%s" % r)
	_check("first clean run is saved as the best", r.new_best and is_equal_approx(SaveData.best_time(mission.save_key), r.time),
			"%s best %.2f" % [r, SaveData.best_time(mission.save_key)])
	_check("a beat of slow motion on the finish", slow[0])
	var hud := main.get_node("MissionHUD") as MissionHUD
	await _frames(3)
	_check("HUD: run complete, R to run it again", _hud_text(hud).contains("Run complete"), _hud_text(hud))


## No grapple at all: walk-up roof -> jump the yard -> E in through the Hotel
## corridor (slow time) -> run through -> E out onto the North Ave fire
## escape (a narrow landing: the dive stops on it) -> up two flights -> the drop.
func test_parkour_route() -> void:
	_section("Mission: the drop by parkour alone")
	mission.restart()
	await _phys(5)
	var fired := [0]
	var on_fire := func(_a: GrappleAnchor) -> void: fired[0] += 1
	player.grapple_fired.connect(on_fire)
	var ids := _record_traversals()
	var reached := [false]
	var on_reached := func(step: MissionStep, _i: int) -> void: reached[0] = reached[0] or step.name == "Drop"
	mission.step_reached.connect(on_reached)
	await _place(Vector3(-24.5, 10.55, 16.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	player.camera.yaw = 0.0
	await _wait_until(func() -> bool: return player.global_position.z < 6.5, 3.0)
	Input.action_press(&"jump")
	await _wait_until(func() -> bool: return player.prompt.hint_text() != "", 1.0)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.count(&"window_dive") >= 1 and player.state == Player.State.MOVE, 2.0)
	Input.action_release(&"jump")
	await _wait_until(func() -> bool: return player.global_position.z < -19.5, 3.0)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return ids.count(&"window_dive") >= 2 and player.state == Player.State.MOVE, 3.0)
	_release_all()
	await _phys(20)
	var on_escape := player.is_on_floor() and absf(player.global_position.y - 10.5) < 0.1
	_check("jump the yard, E through the corridor, E out: lands and stays on the fire escape", ids.count(&"window_dive") == 2
			and on_escape, "%s %s" % [ids, player.global_position])
	var ok := await _walk_to([Vector3(-24.8, 0, -23.1), Vector3(-32.3, 0, -23.1), Vector3(-32.3, 0, -24.25), Vector3(-25.0, 0, -24.25),
			Vector3(-25.0, 0, -23.1), Vector3(-32.3, 0, -23.1), Vector3(-32.3, 0, -24.25), Vector3(-25.0, 0, -24.25),
			Vector3(-25.0, 0, -23.1), Vector3(-24.8, 0, -19.2)], false, 20.0)
	await _phys(5)
	_stop_recording()
	player.grapple_fired.disconnect(on_fire)
	mission.step_reached.disconnect(on_reached)
	_check("up two flights onto the roof: the drop, no grapple used", ok and reached[0] and fired[0] == 0,
			"%s reached %s grapples %d" % [player.global_position, reached[0], fired[0]])


## Player-found tech kept by the balance: E out of the safehouse loft's front
## window, turn round in the air, look up, grapple straight back up onto the
## roof above the window.
func test_window_turn_grapple() -> void:
	_section("Window -> turn 180 in the air -> look up -> grapple")
	var anchor := _anchor("SafehouseDistrict/Safehouse/AnchorSafehouseRoof")
	var slow := [false]
	var on_slow := func() -> void: slow[0] = true
	player.bullet_time.started.connect(on_slow)
	await _place(Vector3(-27.1, 3.85, 38.3), 0.0)
	Input.action_press(&"move_forward")
	await _phys(2)
	await _tap(&"traverse")
	await _wait_until(func() -> bool: return player.state == Player.State.TRAVERSAL, 1.0)
	_release_all()
	await _wait_until(func() -> bool: return player.state != Player.State.TRAVERSAL, 2.0)
	var cam := player.camera
	var yaw0 := cam.yaw
	var pitch0 := cam.pitch
	var d := anchor.global_position - cam.global_position
	for i in 20:
		var t := float(i + 1) / 20.0
		cam.yaw = lerp_angle(yaw0, atan2(-d.x, -d.z), t)
		cam.pitch = lerpf(pitch0, atan2(d.y, Vector2(d.x, d.z).length()), t)
		await physics_frame
	var airborne := not player.is_on_floor()
	var r := await _grapple_to(anchor)
	player.bullet_time.started.disconnect(on_slow)
	_check("out of the window (slow time), turned round mid-fall, grapple: back up on the roof (7.7)", slow[0] and airborne
			and r.arrived and absf(player.global_position.y - 7.7) < 0.1, "%s %s" % [r, player.global_position])


func test_mission_restart() -> void:
	_section("Mission: R restarts the run")
	await _tap(&"debug_respawn")
	await _phys(5)
	var package := mission.get_node("Drop/Package") as Node3D
	_check("R: back at the safehouse, first objective, clock reset", mission.phase == Mission.Phase.READY
			and mission.step_index == 0 and is_zero_approx(mission.elapsed) and package.visible
			and player.global_position.distance_to(Vector3(-21.0, 0.0, 42.0)) < 0.3, str(player.global_position))
	_check("a restart is not a debug jump", not mission.assisted)


func test_mission_assisted() -> void:
	_section("Mission: debug jumps don't set records")
	var best := SaveData.best_time(mission.save_key)
	main.get_node("DebugHUD").call(&"teleport_to_section", 2)
	await _phys(5)
	_check("a number-key jump marks the run", mission.assisted)
	await _place(Vector3(-24.8, 17.55, -18.5), 180.0)
	await _wait_until(func() -> bool: return mission.step_index == 1, 1.0)
	await _place(Vector3(-23.0, 7.75, 41.0), 0.0)
	await _wait_until(func() -> bool: return mission.phase == Mission.Phase.COMPLETE, 1.0)
	_check("completes, but the time isn't saved or rated", mission.phase == Mission.Phase.COMPLETE and mission.result.assisted
			and not mission.result.new_best and mission.result.rating == ""
			and is_equal_approx(SaveData.best_time(mission.save_key), best), "%s" % mission.result)
	await _wait_until(func() -> bool: return not player.bullet_time.active, 2.0)
	mission.restart()
	await _phys(5)


func test_pause_and_controls() -> void:
	_section("Pause menu and controls")
	var pause := main.get_node("PauseMenu") as PauseMenu
	_key(KEY_ESCAPE)
	await _frames(3)
	_check("Esc pauses the game", paused and pause.paused)
	var controls := pause.get("_controls") as Control
	_check("paused: the controls panel is shown", controls.visible)
	var labels: Array = controls.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check("controls list the real keys (E windows, Space jump, RMB grapple, C roll)", labels.has("E") and labels.has("SPACE")
			and labels.has("RMB") and labels.has("C / CTRL"), str(labels))
	var before := player.global_position
	for i in 10:
		await process_frame
	_check("nothing moves while paused", player.global_position.is_equal_approx(before))
	_key(KEY_ESCAPE)
	await _frames(3)
	_check("Esc again resumes", not paused and not pause.paused and not controls.visible)
	_key(KEY_F1)
	await _frames(3)
	_check("F1 shows the controls without pausing", controls.visible and not paused)
	_key(KEY_F1)
	await _frames(3)
	_check("F1 again hides them", not controls.visible)
	var debug := main.get_node("DebugHUD") as CanvasLayer
	_check("the debug readout starts hidden", not debug.visible)
	_key(KEY_F3)
	await _frames(3)
	_check("F3 shows it", debug.visible)
	_key(KEY_F3)
	await process_frame


func test_roll_tip() -> void:
	_section("Teaching the roll")
	var hud := main.get_node("MissionHUD") as MissionHUD
	var tip := hud.get("_tip") as Label
	# Off the safehouse roof onto the street, no roll: a stagger and the tip.
	await _place(Vector3(-26.5, 7.75, 40.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var staggered := [false]
	var on_stagger := func(_hard: bool) -> void: staggered[0] = true
	player.staggered.connect(on_stagger)
	await _wait_until(func() -> bool: return staggered[0], 4.0)
	_release_all()
	player.staggered.disconnect(on_stagger)
	await _frames(5)
	_check("first hard landing: a one-off tip to roll (C)", staggered[0] and tip.text.contains("roll") and tip.modulate.a > 0.0,
			"'%s'" % tip.text)
	_check("the tip is remembered", SaveData.flag(&"tip_roll"))


# --- Helpers ---------------------------------------------------------------------

func _hud_text(hud: MissionHUD) -> String:
	var parts: PackedStringArray = []
	for l in hud.find_children("*", "Label", true, false):
		parts.append((l as Label).text)
	return " | ".join(parts)


func _anchor(path: String) -> GrappleAnchor:
	return main.get_node("CityGreybox/" + path) as GrappleAnchor


func _walk_to(points: Array, sprint := false, timeout := 10.0) -> bool:
	for target: Vector3 in points:
		var frames := int(timeout * 60.0)
		var reached := false
		while frames > 0:
			var d := Vector3(target.x - player.global_position.x, 0.0, target.z - player.global_position.z)
			if d.length() < 0.5:
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
	return true


func _grapple_to(anchor: GrappleAnchor) -> Dictionary:
	var out := {seen = false, arrived = false}
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
	await _wait_until(func() -> bool: return done[0], 5.0)
	player.grapple_finished.disconnect(on_finish)
	await _wait_until(func() -> bool: return player.is_on_floor(), 4.0)
	return out


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


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _key_event(action: StringName, pressed: bool) -> void:
	if MOUSE_FOR.has(action):
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_FOR[action]
		event.pressed = pressed
		Input.parse_input_event(event)
		return
	var key := InputEventKey.new()
	key.physical_keycode = KEY_FOR[action]
	key.pressed = pressed
	Input.parse_input_event(key)


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
