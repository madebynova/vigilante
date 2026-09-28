class_name Player
extends CharacterBody3D
## Third-person player controller: locomotion, jumping, crouching and the
## parkour entry points (vault, ledge grab/climb, wall-run, climbing, window
## traversal, grapple).
##
## Responsibilities are split so each piece can grow on its own:
##   Locomotion        - velocity math (walk, sprint, air control, gravity)
##   ParkourSensor     - geometry queries (what can I vault / grab / run along?)
##   ParkourMoves      - turns sensor results into TraversalMotions
##   TraversalWindow   - window openings and their motions
##   InteractionPrompt - on-screen contextual prompt ("[E] DIVE THROUGH")
##   BulletTime        - timed slow-time ability (F)
##   Grapple           - grapple arrow: targeting (camera aim), firing, cable
##   PlayerCamera      - orbit camera and mouse capture
##   PlayerVisual      - character model + light procedural motion

## GRAPPLE_FIRE: the grapple arrow is in flight. GRAPPLE: it has stuck and the
## player is being pulled along the cable. WALL_RUN: running along a wall.
## CLIMB: holding on to a climbable surface (ladder, drainpipe, scaffold).
## ROLL: rolling out of a landing (crouch pressed just before touchdown).
enum State { MOVE, TRAVERSAL, LEDGE_HANG, WINDOW_APPROACH, GRAPPLE_FIRE, GRAPPLE, WALL_RUN, CLIMB, ROLL }

## How long a grapple press is remembered (game seconds), so pressing a hair
## before the grapple becomes possible (e.g. mid-dive) still counts.
const GRAPPLE_BUFFER := 0.2
## How long an E press is remembered for windows (game seconds), so pressing
## a moment before a window comes into reach (mid-jump) still dives.
const TRAVERSE_BUFFER := 0.15
## A pull whose cable is blocked (or that drives the body head-on into a
## wall) for this long lets go: the world wins over the grapple.
const GRAPPLE_BLOCK_TIME := 0.1
## Quick moves whose jump / grapple presses are held until they end.
const CHAINABLE_MOTIONS: Array[StringName] = [&"vault_over", &"vault_onto", &"mantle", &"climb_up"]
## Wall-runs never catch a fall faster than this (m/s)...
const WALL_RUN_MAX_FALL_SPEED := 7.0
## ...or start with less than this much drop below the feet (still on the way
## up from the ground, or about to land).
const WALL_RUN_MIN_HEIGHT := 0.5
## Speed pressing the body against the wall while running on it (m/s).
const WALL_RUN_STICK := 2.0
## Visual body roll away from the wall while running on it (radians).
const WALL_RUN_LEAN := 0.25
## Gap kept between the body and a surface being climbed (m).
const CLIMB_GAP := 0.05

signal state_changed(new_state: State)
signal traversal_started(id: StringName)
signal traversal_finished(id: StringName)
signal landed(impact_speed: float)
## A grapple arrow has been fired at `anchor`.
signal grapple_fired(anchor: GrappleAnchor)
## The grapple arrow has stuck in `anchor`: the pull begins.
signal grapple_started(anchor: GrappleAnchor)
## The grapple is over: arrived, let go, or the arrow missed.
signal grapple_finished(arrived: bool)
## Started running along the wall facing `normal` (animation hook).
signal wall_run_started(normal: Vector3)
## Left the wall: `jumped` = wall-jump, otherwise dropped or ran out.
signal wall_run_finished(jumped: bool)
## Started climbing the surface facing `normal` (animation hook).
signal climb_started(normal: Vector3)
## Stopped climbing: &"top" (pulled up onto the ledge above), &"bottom" (stepped
## off onto the ground), &"jump", &"drop" or &"grapple".
signal climb_finished(reason: StringName)
## Rolled out of a landing (speed kept).
signal rolled
## Took a landing too hard without rolling: `hard` = floored rather than just
## staggered.
signal staggered(hard: bool)
## Moved by teleport() (respawn, debug jumps, a mission restart).
signal teleported
## Sent back to the spawn point (R, or falling out of the world).
signal respawned

@export var settings: MovementSettings

@export_group("Parkour")
## Sprinting into a vaultable obstacle closer than this vaults automatically.
@export var auto_vault_distance := 0.55
## Ledges are only grabbed once upward speed has dropped below this.
@export var ledge_grab_max_rise_speed := 3.5
@export var ledge_regrab_delay := 0.35
@export var shimmy_speed := 1.6

@export_group("Wall run")
## Speed along a wall needed to start running on it (walk is 5, sprint 9.5).
@export var wall_run_min_speed := 7.0
## The run ends if speed along the wall drops below this (e.g. hit something).
@export var wall_run_exit_speed := 4.0
## Longest single wall-run before the player drops off (seconds).
@export var wall_run_max_time := 1.2
## Coming down, feet on the wall hold the fall to this speed (m/s)...
@export var wall_run_slide_speed := 2.0
## ...reached at this fraction of normal gravity. Going up is a normal jump arc.
@export var wall_run_gravity_scale := 0.3
## Push away from the wall on a wall-jump (m/s). The rise is a normal jump and
## speed along the wall is kept.
@export var wall_jump_push := 6.0
## For this long after a wall-jump (game seconds, about the rise of a jump) the
## jump always rises its full height, and air control can't bleed off the push
## away from the wall unless the player steers back toward it. The reach then
## doesn't depend on how long Space is held or on holding forward. Never adds
## speed: steering only turns the momentum along the wall.
@export var wall_jump_carry_time := 0.32

@export_group("Climb")
## Climbing speeds on a climbable surface (m/s). Only surfaces on the sensor's
## climb layers can be climbed (ladders, drainpipes, scaffolding).
@export var climb_up_speed := 2.4
@export var climb_down_speed := 3.5
@export var climb_side_speed := 1.8
## Jumping off a climbable surface pushes away from it at this speed (m/s);
## the rise is a normal jump.
@export var climb_jump_push := 4.5
## After letting go of a climbable surface it can't be grabbed again for this
## long (game seconds), so jumping or dropping off never re-sticks at once.
@export var climb_regrab_delay := 0.4

@export_group("Landing")
## Crouch pressed this long before touching down (game seconds) rolls out of
## the landing: speed kept, no stagger.
@export var roll_window := 0.3
@export var roll_duration := 0.42
## A roll carries on at least this fast (m/s).
@export var roll_min_speed := 6.0
## Touching down faster than this (m/s: about a two-storey drop) without a
## roll staggers for heavy_landing_recovery...
@export var heavy_landing_speed := 22.0
@export var heavy_landing_recovery := 0.35
## ...and faster than this (about three storeys) floors the player for
## hard_landing_recovery. A roll still keeps the speed from that high, but
## staggers at the end.
@export var hard_landing_speed := 30.0
@export var hard_landing_recovery := 0.8

@export_group("Slow time")
## Slow time (F) starts only in the air, with at least this much drop below
## the feet.
@export var bullet_time_min_height := 1.5
## Window dives start slow time at takeoff (if it is ready) for the
## cinematic beat. The dive itself is always a single E press.
@export var window_dive_slow_time := true

@export_group("Safety")
@export var fall_respawn_height := -25.0

var state := State.MOVE
var is_sprinting := false
var is_crouching := false
## Camera-relative desired move direction (length 0..1).
var wish_dir := Vector3.ZERO
var current_motion: TraversalMotion
var current_ledge: ParkourSensor.Ledge
## Normal of the wall being run along (ZERO when not wall-running).
var wall_normal := Vector3.ZERO
# Debug readout.
var last_action: StringName = &"-"
## Debug readout (only kept up to date while debug_wall_run_hint is on):
## "WALL RUN READY", "WALL RUN", "WALL JUMP", or why a wall beside the player
## isn't runnable yet ("wall: too slow along it", ...). Empty otherwise.
var wall_run_hint := ""
var debug_wall_run_hint := false

var _input_dir := Vector2.ZERO
var _sprint_held := false
var _crouch_held := false
var _crouch_pressed := false
var _jump_held := false
var _jump_pressed := false
var _traverse_pressed := false
var _traverse_buffer := 0.0
var _bullet_time_pressed := false
var _jump_buffer := 0.0
## Game seconds left in which touching down rolls (see roll_window).
var _roll_buffer := 0.0
var _roll_time := 0.0
var _roll_dir := Vector3.ZERO
var _roll_speed := 0.0
## The roll came out of a landing too hard to shrug off: stagger at its end.
var _roll_stagger := false
var _coyote := 0.0
var _recovery := 0.0
var _ledge_cooldown := 0.0
var _was_on_floor := true
var _spawn := Transform3D()
var _windows: Array[TraversalWindow] = []
var _approach_window: TraversalWindow
var _approach_start := Vector3.ZERO
var _approach_target := Vector3.ZERO
var _approach_entry_speed := 0.0
var _approach_time := 0.0
## Window being dived through (and the side the dive started on), so a grapple
## can cut the dive short once the player is clear of the frame.
var _dive_window: TraversalWindow
var _dive_side := 0.0
var _grapple_buffer := 0.0
var _grapple_time := 0.0
var _grapple_best := INF
var _grapple_stall := 0.0
## Speed of the current pull (see Grapple.pull_speed_for) and how long it has
## been obstructed.
var _pull_speed := 0.0
var _grapple_blocked := 0.0
## Direction of travel along the wall being run on.
var _wall_tangent := Vector3.ZERO
var _wall_run_time := 0.0
## Game seconds left showing "WALL JUMP" in the debug readout.
var _wall_jump_flash := 0.0
## Game seconds left of the wall-jump carry (see wall_jump_carry_time), and the
## normal of the wall it pushed off.
var _wall_jump_carry := 0.0
var _wall_jump_normal := Vector3.ZERO
## Normal of the surface being climbed (ZERO when not climbing).
var climb_normal := Vector3.ZERO
var _climb_cooldown := 0.0
## Surface a climb-on-from-above motion ends on (see _try_climb_down).
var _pending_climb_normal := Vector3.ZERO
## Normal of the last wall left: it can't be run on again until the player
## lands or fires the grapple (no re-sticking to the same wall).
var _used_wall := Vector3.ZERO

@onready var camera: PlayerCamera = $CameraRig
@onready var grapple: Grapple = $Grapple
@onready var sensor: ParkourSensor = $ParkourSensor
@onready var prompt: InteractionPrompt = $PromptLayer/InteractionPrompt
@onready var bullet_time: BulletTime = $BulletTime
@onready var visual: PlayerVisual = $Visual
@onready var _shape_node: CollisionShape3D = $CollisionShape3D
@onready var _shape: CapsuleShape3D = _shape_node.shape


func _ready() -> void:
	if settings == null:
		settings = MovementSettings.new()
	sensor.body_radius = _shape.radius
	sensor.standing_height = settings.standing_height
	sensor.crouch_height = settings.crouch_height
	visual.standing_height = settings.standing_height
	visual.crouch_height = settings.crouch_height
	_apply_body_height(settings.standing_height)
	_spawn = global_transform


func _physics_process(delta: float) -> void:
	_read_input()
	_ledge_cooldown = maxf(_ledge_cooldown - delta, 0.0)
	_update_grapple_target()
	match state:
		State.MOVE:
			_process_move(delta)
		State.TRAVERSAL:
			_process_traversal(delta)
		State.LEDGE_HANG:
			_process_hang(delta)
		State.WINDOW_APPROACH:
			_process_window_approach(delta)
		State.GRAPPLE_FIRE:
			_process_grapple_fire(delta)
		State.GRAPPLE:
			_process_grapple(delta)
		State.WALL_RUN:
			_process_wall_run(delta)
		State.CLIMB:
			_process_climb(delta)
		State.ROLL:
			_process_roll(delta)
	# A jump or grapple pressed during a quick vault or mantle is kept for its
	# end, so the move chains straight into the next one.
	var hold_buffers := state == State.TRAVERSAL and current_motion != null \
			and current_motion.id in CHAINABLE_MOTIONS
	if not hold_buffers:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
		_grapple_buffer = maxf(_grapple_buffer - delta, 0.0)
	_traverse_buffer = maxf(_traverse_buffer - delta, 0.0)
	_roll_buffer = maxf(_roll_buffer - delta, 0.0)
	_wall_jump_carry = maxf(_wall_jump_carry - delta, 0.0)
	_climb_cooldown = maxf(_climb_cooldown - delta, 0.0)
	_update_prompt()
	if debug_wall_run_hint:
		_update_wall_run_hint(delta)

	var sprint_amount := clampf((horizontal_speed() - settings.walk_speed)
			/ (settings.sprint_speed - settings.walk_speed), 0.0, 1.0)
	camera.speed_amount = sprint_amount
	if state == State.WINDOW_APPROACH:
		camera.speed_amount = 1.0
	elif state == State.GRAPPLE:
		# A steep pull is fast even with little speed across: widen for it too.
		camera.speed_amount = clampf((velocity.length() - settings.walk_speed)
				/ (settings.sprint_speed - settings.walk_speed), 0.0, 1.0)
	# Slow time keeps the tightened FOV the window sequence used to apply.
	camera.focus_amount = 1.0 if bullet_time.active else 0.0
	visual.standing_still = state == State.MOVE and is_on_floor() and horizontal_speed() < 0.3 \
			and wish_dir.length() < 0.1
	visual.tick(delta, velocity, sprint_amount if state == State.MOVE else 0.0)

	if global_position.y < fall_respawn_height:
		respawn()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Moves the player to `xform` and clears any in-progress action.
func teleport(xform: Transform3D) -> void:
	bullet_time.reset()
	grapple.detach()
	grapple.nock()
	current_motion = null
	current_ledge = null
	_approach_window = null
	_dive_window = null
	_grapple_buffer = 0.0
	_traverse_buffer = 0.0
	_roll_buffer = 0.0
	_roll_stagger = false
	_recovery = 0.0
	_wall_jump_carry = 0.0
	_climb_cooldown = 0.0
	climb_normal = Vector3.ZERO
	wall_normal = Vector3.ZERO
	_used_wall = Vector3.ZERO
	velocity = Vector3.ZERO
	global_transform = xform
	_set_crouched(false)
	visual.tucked = false
	visual.traversal_pitch = 0.0
	visual.tumble = 0.0
	visual.wall_roll = 0.0
	camera.wall_normal = Vector3.ZERO
	_set_state(State.MOVE)
	reset_physics_interpolation()
	camera.yaw = rotation.y
	camera.snap()
	teleported.emit()


func respawn() -> void:
	teleport(_spawn)
	last_action = &"respawn"
	respawned.emit()


func register_window(window: TraversalWindow) -> void:
	if not _windows.has(window):
		_windows.append(window)


func unregister_window(window: TraversalWindow) -> void:
	_windows.erase(window)


# --- Input -------------------------------------------------------------------

func _read_input() -> void:
	_input_dir = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	wish_dir = camera.yaw_basis() * Vector3(_input_dir.x, 0.0, _input_dir.y)
	_sprint_held = Input.is_action_pressed(&"sprint")
	_crouch_held = Input.is_action_pressed(&"crouch")
	_crouch_pressed = Input.is_action_just_pressed(&"crouch")
	if _crouch_pressed:
		_roll_buffer = roll_window
	_jump_held = Input.is_action_pressed(&"jump")
	_traverse_pressed = Input.is_action_just_pressed(&"traverse")
	if _traverse_pressed:
		_traverse_buffer = TRAVERSE_BUFFER
	_jump_pressed = Input.is_action_just_pressed(&"jump")
	if _jump_pressed:
		_jump_buffer = settings.jump_buffer_time
	if Input.is_action_just_pressed(&"grapple"):
		_grapple_buffer = GRAPPLE_BUFFER
	_bullet_time_pressed = Input.is_action_just_pressed(&"bullet_time")
	if Input.is_action_just_pressed(&"debug_respawn"):
		respawn()


# --- Free movement -----------------------------------------------------------

func _process_move(delta: float) -> void:
	var on_floor := is_on_floor()
	_coyote = settings.coyote_time if on_floor else maxf(_coyote - delta, 0.0)
	if on_floor:
		_used_wall = Vector3.ZERO # back on the ground: any wall can be run on again
	_recovery = maxf(_recovery - delta, 0.0)
	_update_crouch()
	is_sprinting = _sprint_held and not is_crouching and _recovery <= 0.0 and _input_dir.length() > 0.2

	# Deliberate actions (grapple, E at a window) and parkour take priority
	# over plain movement.
	if _try_grapple():
		return
	if on_floor:
		if _try_window():
			return
		if _try_climb(true) or _try_climb_down():
			return
		# Space vaults; E is for windows and ladders only.
		if _jump_buffer > 0.0 and _try_vault(false):
			return
		if is_sprinting and _try_vault(true):
			return
	elif _try_window() or _try_ledge(): # in the air only dive windows (E) apply
		return
	elif _coyote <= 0.0 and _try_wall_run():
		# Not in coyote time: just off an edge, Space is still a normal jump
		# (the run then starts on the way up), never an instant wall-jump.
		_process_wall_run(delta)
		return
	elif _try_climb(false):
		return
	elif _bullet_time_pressed:
		_try_air_bullet_time()

	var target_speed := settings.walk_speed
	if is_crouching:
		target_speed = settings.crouch_speed
	elif is_sprinting:
		target_speed = settings.sprint_speed
	if _recovery > 0.0:
		target_speed *= 0.45

	var carrying := _wall_jump_carry > 0.0 and not on_floor
	var hvel: Vector3
	if on_floor:
		hvel = Locomotion.ground(velocity, wish_dir, target_speed, settings, delta)
	else:
		hvel = Locomotion.air(velocity, wish_dir, target_speed, settings, delta)
		if carrying:
			hvel = _keep_wall_jump_push(hvel, target_speed)
	velocity.x = hvel.x
	velocity.z = hvel.z

	if _jump_buffer > 0.0 and _coyote > 0.0 and _recovery <= 0.0 and (not is_crouching or _try_stand()):
		velocity.y = settings.jump_velocity()
		_jump_buffer = 0.0
		_coyote = 0.0
		on_floor = false
		last_action = &"jump"
		visual.on_jump()
	if not on_floor:
		velocity.y = Locomotion.apply_gravity(velocity.y, _jump_held or carrying, settings, delta)

	if wish_dir.length() > 0.1:
		_face(wish_dir, settings.turn_sharpness if on_floor else settings.air_turn_sharpness, delta)

	var fall_speed := -velocity.y
	move_and_slide()
	var grounded := is_on_floor()
	var touched_down := grounded and not _was_on_floor
	_was_on_floor = grounded
	if touched_down:
		_land(fall_speed)


## Touchdown from a jump or fall. Crouch pressed just before rolls out of it
## with the speed kept. Otherwise a hard landing staggers briefly and a very
## hard one floors the player for a moment: height matters, and rolling is
## how to carry momentum down from it.
func _land(fall_speed: float) -> void:
	landed.emit(fall_speed)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if _roll_buffer > 0.0 and (flat.length() > 2.0 or fall_speed >= heavy_landing_speed):
		visual.on_landed(minf(fall_speed, 8.0))
		camera.add_shake(0.08)
		_start_roll(fall_speed >= hard_landing_speed)
		return
	visual.on_landed(fall_speed)
	if fall_speed >= hard_landing_speed:
		_stagger(hard_landing_recovery, 0.1, 0.45)
		staggered.emit(true)
	elif fall_speed >= heavy_landing_speed:
		_stagger(heavy_landing_recovery, 0.4, 0.25)
		staggered.emit(false)
	elif fall_speed > 12.0:
		camera.add_shake(clampf((fall_speed - 12.0) / 20.0, 0.0, 0.4))


## Stumbles on landing: `keep` of the speed across survives, then reduced
## control for `recovery` seconds (see _recovery).
func _stagger(recovery: float, keep: float, shake: float) -> void:
	velocity.x *= keep
	velocity.z *= keep
	_recovery = maxf(_recovery, recovery)
	_jump_buffer = 0.0
	visual.stumble()
	camera.add_shake(shake)
	last_action = &"hard_landing"


# --- Roll --------------------------------------------------------------------

## Rolls out of a landing along the way the player was going (or steering, if
## that is roughly the same way), at least roll_min_speed, body tucked.
func _start_roll(stagger_after: bool) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	_roll_dir = flat.normalized() if flat.length() > 1.0 else -global_basis.z
	if wish_dir.length() > 0.3 and wish_dir.normalized().dot(_roll_dir) > 0.0:
		_roll_dir = wish_dir.normalized()
	_roll_speed = maxf(flat.length(), roll_min_speed)
	_roll_time = 0.0
	_roll_buffer = 0.0
	_roll_stagger = stagger_after
	grapple.nock()
	_set_crouched(true)
	visual.tucked = true
	last_action = &"roll"
	_set_state(State.ROLL)
	rolled.emit()


## One forward roll along the ground, steerable a little, speed kept (bonus
## speed bleeds off as when sprinting). Jump late in the roll springs out of
## it; grapple fires as usual. Rolling off an edge or into a wall ends it.
func _process_roll(delta: float) -> void:
	_roll_time += delta
	var p := clampf(_roll_time / roll_duration, 0.0, 1.0)
	if _can_grapple():
		var anchor := grapple.target
		_end_roll()
		_fire_grapple(anchor)
		return
	if _jump_buffer > 0.0 and p > 0.4 and not _roll_stagger:
		_end_roll()
		_process_move(delta) # the buffered jump goes off from here
		return
	if wish_dir.length() > 0.3:
		var steer := _roll_dir.slerp(wish_dir.normalized(), clampf(3.0 * delta, 0.0, 1.0))
		steer.y = 0.0
		if steer.length() > 0.01:
			_roll_dir = steer.normalized()
	if _roll_speed > settings.sprint_speed:
		_roll_speed = move_toward(_roll_speed, settings.sprint_speed, settings.overspeed_decay * delta)
	velocity.x = _roll_dir.x * _roll_speed
	velocity.z = _roll_dir.z * _roll_speed
	velocity.y = Locomotion.apply_gravity(minf(velocity.y, 0.0), false, settings, delta)
	_face(_roll_dir, 20.0, delta)
	visual.tumble = -TAU * smoothstep(0.0, 1.0, p)
	move_and_slide()
	var blocked := horizontal_speed() < _roll_speed * 0.4
	if not is_on_floor() and not _ground_within(0.3):
		_end_roll() # rolled off an edge: fall on with the speed
	elif blocked or p >= 1.0:
		_end_roll()


func _end_roll() -> void:
	visual.tumble = 0.0
	visual.tucked = false
	if not _crouch_held:
		_try_stand() # stays low under a ceiling, like crouching
	var grounded := is_on_floor()
	_coyote = settings.coyote_time if grounded else 0.0
	_was_on_floor = grounded
	if _roll_stagger:
		_roll_stagger = false
		_stagger(heavy_landing_recovery, 0.6, 0.2)
		staggered.emit(false)
	_set_state(State.MOVE)


func _update_crouch() -> void:
	if _crouch_held and not is_crouching:
		_set_crouched(true)
	elif not _crouch_held and is_crouching:
		_try_stand()


func _try_stand() -> bool:
	if not sensor.has_clearance(global_position, settings.standing_height):
		return false
	_set_crouched(false)
	return true


func _set_crouched(value: bool) -> void:
	is_crouching = value
	_apply_body_height(settings.crouch_height if value else settings.standing_height)
	visual.crouched = value
	camera.crouched = value


func _apply_body_height(height: float) -> void:
	_shape.height = height
	_shape_node.position.y = height * 0.5


func _move_or_facing_dir() -> Vector3:
	return wish_dir.normalized() if wish_dir.length() > 0.2 else -global_basis.z


func _face(dir: Vector3, sharpness: float, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-sharpness * delta))


# --- Vault / ledge -----------------------------------------------------------

func _try_vault(automatic: bool) -> bool:
	if is_crouching:
		return false
	var dir := _move_or_facing_dir()
	var speed := horizontal_speed()
	if automatic and (speed < settings.walk_speed + 0.5 or wish_dir.normalized().dot(dir) < 0.7):
		return false
	var obstacle := sensor.detect_obstacle(global_position, dir)
	if obstacle == null or (automatic and obstacle.distance > auto_vault_distance):
		return false
	if _on_window_sill(obstacle.wall_point):
		return false # windows are only ever taken with the Traverse button
	_jump_buffer = 0.0
	_start_motion(ParkourMoves.vault(obstacle, global_position, speed))
	return true


func _try_ledge() -> bool:
	if _ledge_cooldown > 0.0 or velocity.y > ledge_grab_max_rise_speed or wish_dir.length() < 0.3:
		return false
	var ledge := sensor.detect_ledge(global_position, wish_dir)
	if ledge == null or wish_dir.normalized().dot(-ledge.wall_normal) < 0.5:
		return false
	if _on_window_sill(ledge.wall_point):
		return false # a window sill is never a ledge: E takes the window
	if ledge.can_hang:
		current_ledge = ledge
		velocity = Vector3.ZERO
		last_action = &"ledge_grab"
		grapple.nock()
		_set_state(State.LEDGE_HANG)
	else:
		_start_motion(ParkourMoves.climb_up(ledge, global_position, true))
	return true


func _process_hang(delta: float) -> void:
	var ledge := current_ledge
	velocity = Vector3.ZERO
	global_position = global_position.lerp(ledge.hang_position, 1.0 - exp(-18.0 * delta))
	_face(-ledge.wall_normal, 20.0, delta)

	if _jump_buffer > 0.0 or _traverse_pressed:
		_jump_buffer = 0.0
		_start_motion(ParkourMoves.climb_up(ledge, global_position, false))
		return
	# Down onto a climbable surface below the edge (a ladder, a drainpipe):
	# climb down it instead of dropping. C always just lets go.
	if not _crouch_pressed and (_input_dir.y > 0.5 or wish_dir.dot(ledge.wall_normal) > 0.6):
		var below := sensor.detect_climb(global_position, -ledge.wall_normal)
		if below != null:
			current_ledge = null
			_start_climb(below.normal)
			return
	if _crouch_pressed or wish_dir.dot(ledge.wall_normal) > 0.6:
		_drop_from_ledge()
		return

	# Shimmy: only move if the ledge continues at the same height.
	var tangent := Vector3.UP.cross(ledge.wall_normal).normalized()
	var side := wish_dir.dot(tangent)
	if absf(side) > 0.3:
		var step := tangent * signf(side) * shimmy_speed * delta
		var next := sensor.detect_ledge(ledge.hang_position + step, -ledge.wall_normal)
		if next != null and next.can_hang and absf(next.top_y - ledge.top_y) < 0.3:
			current_ledge = next
			last_action = &"shimmy"


func _drop_from_ledge() -> void:
	velocity = current_ledge.wall_normal * 1.5
	current_ledge = null
	_ledge_cooldown = ledge_regrab_delay
	_was_on_floor = false
	last_action = &"ledge_drop"
	_set_state(State.MOVE)


# --- Wall run ----------------------------------------------------------------

## In the air, moving fast alongside a tall vertical wall and steering along it:
## start running on it. Needs real speed along the wall (not into it), and never
## re-sticks to the wall just left.
func _try_wall_run() -> bool:
	var check := _wall_run_check()
	if not check.has("normal") or _ground_within(WALL_RUN_MIN_HEIGHT):
		return false
	_start_wall_run(check.normal, check.tangent)
	return true


## Whether a wall-run could start from here, ignoring being in the air (shared
## by the real entry and the debug readout). {normal, tangent} of the wall if
## so, otherwise {reason} (empty if there's no runnable wall beside at all).
func _wall_run_check() -> Dictionary:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	# Probe beside the direction of travel (or the facing when nearly still, so
	# the readout can still name a wall that's there but too slow for).
	var heading := flat / speed if speed > 0.1 else -global_basis.z
	var right := heading.cross(Vector3.UP)
	var wish := wish_dir.normalized()
	var reason := &""
	for side: Vector3 in [right, -right]:
		var wall := sensor.detect_run_wall(global_position, side)
		if wall == null:
			continue
		if _used_wall != Vector3.ZERO and wall.normal.dot(_used_wall) > 0.9:
			reason = &"same wall: land first"
			continue
		var tangent := _along_wall(wall.normal, heading)
		var along := flat.dot(tangent)
		if along < wall_run_min_speed or along < speed * 0.6:
			reason = &"too slow along it" if along < wall_run_min_speed else &"heading into it"
			continue
		if wish_dir.length() < 0.3 or wish.dot(tangent) < 0.6:
			reason = &"steer along it" # into or away from the wall, or no input
			continue
		if is_crouching:
			reason = &"crouching"
			continue
		if velocity.y < -WALL_RUN_MAX_FALL_SPEED:
			reason = &"falling too fast"
			continue
		return {normal = wall.normal, tangent = tangent}
	return {reason = reason}


func _start_wall_run(normal: Vector3, tangent: Vector3) -> void:
	wall_normal = normal
	_wall_tangent = tangent
	_wall_run_time = 0.0
	_jump_buffer = 0.0 # only a press on the wall jumps off it
	grapple.nock()
	current_ledge = null
	last_action = &"wall_run"
	_set_state(State.WALL_RUN)
	wall_run_started.emit(normal)


## Running along the wall: speed along it is kept (bonus momentum bleeds off as
## when sprinting on the ground), going up is a normal jump arc, coming down the
## feet on the wall hold the fall to a slide. Space jumps off, grapple fires as
## usual; crouch, letting go of the direction or steering away drops off. Also
## ends when the wall does, after wall_run_max_time, when blocked, or on landing.
func _process_wall_run(delta: float) -> void:
	_wall_run_time += delta
	if _can_grapple():
		var anchor := grapple.target
		_end_wall_run(false)
		_fire_grapple(anchor)
		return
	if _jump_pressed:
		_wall_jump()
		return
	var wall := sensor.detect_run_wall(global_position, -wall_normal)
	if wall != null:
		wall_normal = wall.normal # follow gently curving walls
		_wall_tangent = _along_wall(wall.normal, _wall_tangent)
	var wish := wish_dir.normalized()
	var steering := wish_dir.length() >= 0.3 and wish.dot(_wall_tangent) >= 0.2 and wish.dot(wall_normal) <= 0.5
	var along := velocity.dot(_wall_tangent)
	if wall == null or not steering or _crouch_pressed or along < wall_run_exit_speed \
			or _wall_run_time > wall_run_max_time:
		_end_wall_run(false)
		return
	var target := settings.sprint_speed
	along = move_toward(along, target, (settings.overspeed_decay if along > target else settings.air_acceleration) * delta)
	var vy := velocity.y
	if vy > 0.0:
		vy -= settings.gravity * delta
	else:
		vy = move_toward(vy, -wall_run_slide_speed, settings.gravity * wall_run_gravity_scale * delta)
	velocity = _wall_tangent * along - wall_normal * WALL_RUN_STICK + Vector3.UP * vy
	_face(_wall_tangent, 14.0, delta)
	camera.wall_normal = wall_normal
	visual.wall_roll = -signf((global_basis.inverse() * wall_normal).x) * WALL_RUN_LEAN
	move_and_slide()
	if is_on_floor():
		_end_wall_run(false) # ran down onto the ground


## Jump off the wall: a normal jump's rise, a push away from the wall, and the
## speed along it kept. Normal air control applies straight away.
func _wall_jump() -> void:
	velocity = _wall_tangent * velocity.dot(_wall_tangent) + wall_normal * wall_jump_push \
			+ Vector3.UP * settings.jump_velocity()
	_jump_buffer = 0.0
	_wall_jump_flash = 0.5
	_wall_jump_carry = wall_jump_carry_time
	_wall_jump_normal = wall_normal
	visual.on_jump()
	_end_wall_run(true)


## Air control during the wall-jump carry: the push away from the wall just
## left is kept (steering along the wall turns the momentum along it instead of
## bending the push back), within the same speed cap as normal air control.
## Steering back toward that wall is ordinary air control.
func _keep_wall_jump_push(hvel: Vector3, target_speed: float) -> Vector3:
	var n := _wall_jump_normal
	if wish_dir.normalized().dot(n) < -0.3:
		return hvel
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var away := maxf(flat.dot(n), hvel.dot(n))
	var cap := maxf(target_speed, flat.length())
	var along := hvel - n * hvel.dot(n)
	along = along.limit_length(sqrt(maxf(cap * cap - away * away, 0.0)))
	return along + n * away


## Back to normal movement with the current momentum (minus the push that held
## the body against the wall). That wall can't be run on again until landing.
func _end_wall_run(jumped: bool) -> void:
	var into_wall := velocity.dot(-wall_normal)
	if into_wall > 0.0:
		velocity += wall_normal * into_wall
	_used_wall = wall_normal
	wall_normal = Vector3.ZERO
	camera.wall_normal = Vector3.ZERO
	visual.wall_roll = 0.0
	_coyote = 0.0
	_was_on_floor = false
	last_action = &"wall_jump" if jumped else &"wall_run_end"
	_set_state(State.MOVE)
	wall_run_finished.emit(jumped)


## Debug readout of where the player stands with wall-running (see wall_run_hint).
func _update_wall_run_hint(delta: float) -> void:
	_wall_jump_flash = maxf(_wall_jump_flash - delta, 0.0)
	if state == State.WALL_RUN:
		wall_run_hint = "WALL RUN"
	elif _wall_jump_flash > 0.0:
		wall_run_hint = "WALL JUMP"
	elif state != State.MOVE:
		wall_run_hint = ""
	else:
		var check := _wall_run_check()
		if check.has("normal"):
			wall_run_hint = "WALL RUN READY"
		elif check.reason != &"":
			wall_run_hint = "wall: %s" % check.reason
		elif _runnable_wall_near():
			wall_run_hint = "wall: get closer"
		else:
			wall_run_hint = ""


## A runnable wall beside the player, but further than the wall-run reach
## (debug readout only).
func _runnable_wall_near() -> bool:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var heading := flat.normalized() if flat.length() > 0.1 else -global_basis.z
	var right := heading.cross(Vector3.UP)
	return sensor.detect_run_wall(global_position, right, 1.2) != null \
			or sensor.detect_run_wall(global_position, -right, 1.2) != null


## Unit direction along the wall with `normal`, on the side `heading` points to.
func _along_wall(normal: Vector3, heading: Vector3) -> Vector3:
	var t := Vector3.UP.cross(normal).normalized()
	return t if t.dot(heading) >= 0.0 else -t


## True if there is ground within `distance` below the feet.
func _ground_within(distance: float) -> bool:
	var from := global_position + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (distance + 0.1), sensor.collision_mask)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Climb -------------------------------------------------------------------

## Grab a climbable surface ahead (ladder, drainpipe, scaffold): in the air by
## moving into it, on the ground with Jump or E while facing it. Walking or
## sprinting into one never grabs it, and plain walls are never climbable (see
## ParkourSensor.climb_mask).
func _try_climb(on_floor: bool) -> bool:
	if _climb_cooldown > 0.0 or is_crouching or _crouch_held:
		return false
	if on_floor and _jump_buffer <= 0.0 and not _traverse_pressed:
		return false
	if not on_floor and wish_dir.length() < 0.3:
		return false
	var dir := _move_or_facing_dir()
	var surface := sensor.detect_climb(global_position, dir)
	if surface == null or dir.dot(-surface.normal) < 0.6:
		return false
	_start_climb(surface.normal)
	return true


## E at a drop with a climbable surface on the face below the edge: swing over
## the edge onto it, ready to climb down (no jump, no fall).
func _try_climb_down() -> bool:
	if not _traverse_pressed or _climb_cooldown > 0.0 or is_crouching:
		return false
	var surface := sensor.detect_climb_below(global_position, _move_or_facing_dir())
	if surface == null:
		return false
	var n := surface.normal
	var mount := surface.mount_position
	var lip := Vector3(surface.point.x, global_position.y + 0.15, surface.point.z) + n * (_shape.radius + 0.2)
	var pts := PackedVector3Array([global_position, lip, mount + n * 0.2 + Vector3.UP * 0.9, mount])
	var motion := TraversalMotion.new(&"climb_on", pts, 0.55)
	motion.ease_out = 0.4
	motion.body_pitch = 0.2
	_pending_climb_normal = n
	_traverse_pressed = false
	_start_motion(motion)
	return true


func _start_climb(normal: Vector3) -> void:
	grapple.nock()
	climb_normal = normal
	velocity = Vector3.ZERO
	_jump_buffer = 0.0
	_traverse_pressed = false
	current_ledge = null
	last_action = &"climb"
	_set_state(State.CLIMB)
	climb_started.emit(normal)


## On a climbable surface: W / S climb up and down, A / D sideways (as the
## camera sees it), each only while the surface carries on that way. At the
## top, holding W pulls up onto whatever the surface leads to (if anything).
## At the bottom, S steps off onto the ground, or lets go of a surface that
## ends in mid-air. Space jumps away, C lets go, grapple fires as usual.
func _process_climb(delta: float) -> void:
	if _can_grapple():
		var anchor := grapple.target
		_end_climb(&"grapple")
		_fire_grapple(anchor)
		return
	if _jump_pressed:
		_end_climb(&"jump", climb_normal * climb_jump_push + Vector3.UP * settings.jump_velocity())
		visual.on_jump()
		return
	if _crouch_pressed:
		_end_climb(&"drop", climb_normal)
		return
	var surface := sensor.detect_climb(global_position, -climb_normal)
	if surface == null:
		_end_climb(&"drop") # the surface isn't there any more
		return
	var n := surface.normal
	climb_normal = n
	var pos := global_position
	var up := -_input_dir.y
	var vy := 0.0
	if up > 0.2:
		if sensor.climb_continues(pos, n, ParkourSensor.CLIMB_REACH_HEIGHT):
			vy = climb_up_speed * up
		else:
			var ledge := sensor.detect_ledge(pos, -n)
			if ledge != null:
				_end_climb(&"top")
				_start_motion(ParkourMoves.climb_up(ledge, pos, false))
				return
	elif up < -0.2:
		if _ground_within(0.15):
			_end_climb(&"bottom")
			return
		if not sensor.climb_continues(pos, n, ParkourSensor.CLIMB_FOOT_HEIGHT):
			_end_climb(&"drop") # climbed off the bottom of a surface that ends in the air
			return
		vy = climb_down_speed * up
	var side := Vector3.ZERO
	if absf(_input_dir.x) > 0.2:
		var tangent := Vector3.UP.cross(n).normalized()
		if tangent.dot(camera.yaw_basis().x) < 0.0:
			tangent = -tangent
		var dir := tangent * signf(_input_dir.x)
		if sensor.detect_climb(pos + dir * 0.4, -n) != null:
			side = dir * climb_side_speed * absf(_input_dir.x)
	# Hold the body a steady small gap off the surface.
	var hold := clampf((surface.distance - CLIMB_GAP) * 10.0, -2.0, 2.0)
	velocity = Vector3.UP * vy + side - n * hold
	_face(-n, 20.0, delta)
	move_and_slide()


## Back to normal movement with `new_velocity`. The surface can't be grabbed
## again for climb_regrab_delay.
func _end_climb(reason: StringName, new_velocity := Vector3.ZERO) -> void:
	velocity = new_velocity
	climb_normal = Vector3.ZERO
	_climb_cooldown = climb_regrab_delay
	_jump_buffer = 0.0
	_coyote = 0.0
	_was_on_floor = false
	last_action = StringName("climb_%s" % reason)
	_set_state(State.MOVE)
	climb_finished.emit(reason)


# --- Scripted traversal ------------------------------------------------------

func _start_motion(motion: TraversalMotion) -> void:
	grapple.nock() # every parkour move readies the next arrow
	current_motion = motion
	current_ledge = null
	velocity = Vector3.ZERO
	last_action = motion.id
	visual.tucked = motion.tuck
	if motion.start_shake > 0.0:
		camera.add_shake(motion.start_shake)
	_set_state(State.TRAVERSAL)
	traversal_started.emit(motion.id)


func _process_traversal(delta: float) -> void:
	var motion := current_motion
	var before := global_position
	global_position = motion.advance(delta)
	velocity = (global_position - before) / delta
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.5:
		_face(flat, 18.0, delta)
	var p := motion.progress()
	visual.traversal_pitch = motion.body_pitch * sin(PI * p)
	visual.tumble = -TAU * motion.tumble_turns * smoothstep(0.5, 1.0, p)
	# Grapple out of a window dive (the bullet-time moment) once clear of it.
	if motion.id == &"window_dive" and _can_grapple() \
			and _clear_of_dive_window():
		var anchor := grapple.target
		_end_motion(false)
		_fire_grapple(anchor)
		return
	if motion.is_finished():
		_end_motion(true)


## Ends the current traversal. `completed` = played to the end (hand over its
## exit velocity, land unless it ends in mid-air); otherwise it was cut short
## in mid-air and keeps its current velocity.
func _end_motion(completed: bool) -> void:
	var motion := current_motion
	current_motion = null
	_dive_window = null
	visual.tucked = false
	visual.traversal_pitch = 0.0
	visual.tumble = 0.0
	if completed and motion.id == &"climb_on":
		_start_climb(_pending_climb_normal) # over the edge and onto the surface below
		traversal_finished.emit(motion.id)
		return
	if not completed:
		_coyote = 0.0
		_was_on_floor = false
		_set_state(State.MOVE)
		traversal_finished.emit(motion.id)
		return
	velocity = motion.exit_velocity
	_recovery = motion.recovery_time
	_ledge_cooldown = maxf(_ledge_cooldown, 0.2)
	if motion.end_crouched:
		_set_crouched(true)
	if motion.recovery_time > 0.0:
		visual.stumble()
	if motion.ends_airborne:
		# Out into the open air: no landing, no coyote jump - just fall.
		_coyote = 0.0
		_was_on_floor = false
	else:
		_coyote = settings.coyote_time
		_was_on_floor = true
		if motion.landing_shake > 0.0:
			camera.add_shake(motion.landing_shake)
		visual.on_landed(4.0)
	_set_state(State.MOVE)
	traversal_finished.emit(motion.id)


# --- Windows -----------------------------------------------------------------

func _try_window() -> bool:
	if _windows.is_empty() or is_crouching:
		return false
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var speed := hvel.length()
	var pos := global_position
	var airborne := not is_on_floor()
	for window in _windows:
		var dist := window.distance_to_wall(pos)
		if window.dive_window:
			# E is the only way through: running or jumping into it does nothing.
			# Works from either side: the side the player is on decides the way.
			if _can_dive(window):
				_traverse_buffer = 0.0
				if airborne:
					_start_window_dive(window, maxf(speed, settings.sprint_speed)) # already in the air: dive now
				else:
					_begin_window_dive(window, maxf(speed, settings.sprint_speed))
				return true
			continue
		if airborne:
			continue # plain windows are taken on foot only
		# Plain window: only E climbs through (vaults through when moving fast).
		# Running, sprinting or jumping into it does nothing on its own.
		if _traverse_buffer > 0.0 and dist <= window.climb_distance and window.feet_in_reach(pos) \
				and window.is_lined_up(pos, _move_or_facing_dir()):
			_traverse_buffer = 0.0
			var style := TraversalWindow.Style.CLIMB
			if speed > settings.walk_speed * 0.8:
				style = TraversalWindow.Style.VAULT
			_start_motion(window.build_motion(pos, maxf(speed, settings.walk_speed), style))
			return true
	return false


## True if `point` (a vault face or ledge edge) is on a window's sill.
func _on_window_sill(point: Vector3) -> bool:
	for window in _windows:
		if window.covers_point(point):
			return true
	return false


## True if pressing E right now would dive through `window` (also drives the
## prompt, so the prompt only shows when E will actually work).
func _can_dive_position(window: TraversalWindow) -> bool:
	return window.dive_window and window.distance_to_wall(global_position) <= window.dive_distance \
			and window.feet_in_reach(global_position) \
			and window.is_lined_up(global_position, _move_or_facing_dir())


## E pressed just now, or a moment ago (TRAVERSE_BUFFER), and the dive works.
func _can_dive(window: TraversalWindow) -> bool:
	return _traverse_buffer > 0.0 and _can_dive_position(window)


## Shows "[E] DIVE THROUGH" exactly when pressing E would start the dive,
## "[SPACE] CLIMB UP" while hanging from a ledge, otherwise "[E] CLIMB" /
## "[E] CLIMB DOWN" exactly when E would grab a climbable surface ahead /
## climb down onto one below the edge.
func _update_prompt() -> void:
	var dive_available := false
	if state == State.MOVE and not is_crouching: # on foot or mid-jump
		for window in _windows:
			if _can_dive_position(window):
				dive_available = true
	if dive_available:
		prompt.set_hint(&"traverse", "DIVE THROUGH")
		return
	if state == State.LEDGE_HANG:
		prompt.set_hint(&"jump", "CLIMB UP")
		return
	if state == State.MOVE and not is_crouching and _climb_cooldown <= 0.0 and is_on_floor():
		var dir := _move_or_facing_dir()
		var ahead := sensor.detect_climb(global_position, dir)
		if ahead != null and dir.dot(-ahead.normal) >= 0.6:
			prompt.set_hint(&"traverse", "CLIMB")
			return
		if sensor.detect_climb_below(global_position, dir) != null:
			prompt.set_hint(&"traverse", "CLIMB DOWN")
			return
	prompt.clear_hint()


## E at a dive window: run the short distance to the takeoff point, then dive.
## No momentum needed first: the dive always uses at least sprint pace.
func _begin_window_dive(window: TraversalWindow, speed: float) -> void:
	_approach_window = window
	_approach_entry_speed = speed
	_approach_start = global_position
	_approach_target = window.takeoff_point(global_position)
	_approach_time = 0.0
	_traverse_pressed = false
	last_action = &"window_approach"
	_set_state(State.WINDOW_APPROACH)


func _process_window_approach(delta: float) -> void:
	_approach_time += delta
	var speed := _approach_entry_speed
	var to_target := _approach_target - global_position
	to_target.y = 0.0
	if to_target.length() <= speed * delta or _approach_time > 1.5:
		var window := _approach_window
		_approach_window = null
		_start_window_dive(window, _approach_entry_speed)
		return
	var hvel := to_target.normalized() * speed
	velocity.x = hvel.x
	velocity.z = hvel.z
	velocity.y = 0.0 if is_on_floor() else Locomotion.apply_gravity(velocity.y, false, settings, delta)
	_face(_approach_window.through_direction(global_position), 16.0, delta)
	move_and_slide()


## Dives through `window` from where the player is now. Slow time starts here,
## at takeoff, so its short duration covers the dive itself.
func _start_window_dive(window: TraversalWindow, speed: float) -> void:
	_traverse_pressed = false
	if window_dive_slow_time:
		bullet_time.activate()
	_dive_window = window
	_dive_side = window.side_of(global_position)
	_start_motion(window.build_motion(global_position, speed, TraversalWindow.Style.DIVE))


## True once a window dive has carried the player fully out of the frame.
func _clear_of_dive_window() -> bool:
	return _dive_window != null and is_instance_valid(_dive_window) \
			and _dive_window.side_of(global_position) != _dive_side \
			and _dive_window.distance_to_wall(global_position) > _dive_window.wall_thickness * 0.5 + _shape.radius + 0.1


# --- Grapple -----------------------------------------------------------------

## Keeps the highlighted anchor in sync with where the camera aims.
func _update_grapple_target() -> void:
	match state:
		State.MOVE, State.TRAVERSAL, State.WALL_RUN, State.CLIMB, State.ROLL:
			grapple.update_target(global_position + Vector3.UP * 1.2, camera.camera)
		State.GRAPPLE_FIRE, State.GRAPPLE:
			pass # keep the arrow's anchor highlighted
		_:
			grapple.clear_target()


## Grapple press with a valid target: fire the grapple arrow (on the ground or
## in the air).
func _try_grapple() -> bool:
	if not _can_grapple():
		return false
	_fire_grapple(grapple.target)
	return true


## Grapple pressed (or buffered), an anchor targeted and an arrow nocked.
func _can_grapple() -> bool:
	return _grapple_buffer > 0.0 and grapple.target != null and grapple.is_ready()


## Fires the grapple arrow at `anchor`. The pull starts once it has stuck
## (see _process_grapple_fire).
func _fire_grapple(anchor: GrappleAnchor) -> void:
	_grapple_buffer = 0.0
	if is_crouching:
		_try_stand()
	current_ledge = null
	_used_wall = Vector3.ZERO # a fresh grapple: any wall can be run on again
	grapple.fire(anchor)
	last_action = &"grapple_fire"
	_set_state(State.GRAPPLE_FIRE)
	grapple_fired.emit(anchor)


## Grapple arrow in flight: the player carries their momentum (braking on the
## ground, falling in the air) and turns toward the shot. Once the arrow
## sticks the pull starts; if it misses (blocked, timed out, anchor gone) or
## grapple is pressed again, the grapple ends without a pull.
func _process_grapple_fire(delta: float) -> void:
	if _grapple_buffer > 0.0:
		_grapple_buffer = 0.0 # this press lets go; don't re-grapple with it
		_end_grapple(false)
		return
	if grapple.is_attached():
		_start_pull()
		_process_grapple(delta)
		return
	if not grapple.is_arrow_flying():
		_end_grapple(false, &"grapple_miss")
		return
	var on_floor := is_on_floor()
	var hvel: Vector3
	if on_floor:
		hvel = Locomotion.ground(velocity, Vector3.ZERO, 0.0, settings, delta)
	else:
		hvel = Locomotion.air(velocity, Vector3.ZERO, 0.0, settings, delta)
		velocity.y = Locomotion.apply_gravity(velocity.y, false, settings, delta)
	velocity.x = hvel.x
	velocity.z = hvel.z
	var to_anchor := grapple.anchor.global_position - global_position
	var flat := Vector3(to_anchor.x, 0.0, to_anchor.z)
	if flat.length() > 0.3:
		_face(flat, 14.0, delta)
	move_and_slide()


## The arrow has stuck and the cable is connected: start pulling toward it.
func _start_pull() -> void:
	var anchor := grapple.anchor
	_grapple_time = 0.0
	_grapple_best = global_position.distance_to(anchor.global_position)
	_grapple_stall = 0.0
	_grapple_blocked = 0.0
	# Strongest when it extends a movement line: fired on the move (sprint,
	# jump, dive, fall) it pulls at full speed, from a standstill it winches.
	_pull_speed = grapple.pull_speed_for(velocity.length())
	last_action = &"grapple"
	_set_state(State.GRAPPLE)
	grapple_started.emit(anchor)


## Pulled straight toward the stuck arrow's anchor. Ends on arrival, when
## the world gets in the way (see _pull_obstructed), when stalled, on timeout,
## if the anchor goes away, or when grapple is pressed again (let go).
func _process_grapple(delta: float) -> void:
	if not grapple.is_attached():
		_end_grapple(false) # the anchor went away (disabled or removed)
		return
	var anchor := grapple.anchor
	if _grapple_buffer > 0.0:
		_grapple_buffer = 0.0 # this press lets go; don't re-grapple with it
		_end_grapple(false)
		return
	_grapple_time += delta
	var to_target := anchor.global_position - global_position
	var distance := to_target.length()
	# Arrive once close AND up level with the anchor, so a steep pull from below
	# carries the player over the ledge before the hop (never under its lip).
	var close := distance <= maxf(grapple.arrive_distance, velocity.length() * delta)
	if (close and to_target.y <= 0.25) or distance <= 0.3:
		_end_grapple(true)
		return
	var dir := to_target / distance
	velocity = velocity.move_toward(dir * _pull_speed, grapple.pull_acceleration * delta)
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length() > 0.3:
		_face(flat, 14.0, delta)
	move_and_slide()
	if _pull_obstructed(anchor, dir, distance):
		_grapple_blocked += delta
		if _grapple_blocked >= GRAPPLE_BLOCK_TIME:
			_end_grapple(false, &"grapple_blocked")
			return
	else:
		_grapple_blocked = 0.0
	if distance < _grapple_best - 0.05:
		_grapple_best = distance
		_grapple_stall = 0.0
	else:
		_grapple_stall += delta
	if _grapple_stall > 0.3 or _grapple_time > grapple.max_pull_time:
		_end_grapple(false) # blocked by geometry or taking too long


## The world is in the way of the pull: something between the chest and the
## anchor (the cable would pass through it), or the body driven head-on into
## a wall or overhang short of the ledge. Collisions already stop the body;
## this lets go instead of grinding it along the obstacle, so the usual moves
## (ledge grab, wall-run, window, a fall and a roll) take over.
func _pull_obstructed(anchor: GrappleAnchor, dir: Vector3, distance: float) -> bool:
	if not grapple.has_line_of_sight(global_position + Vector3.UP * 1.2, anchor.global_position):
		return true
	if distance > 2.0: # the last metres may brush the ledge's own face
		for i in get_slide_collision_count():
			var n := get_slide_collision(i).get_normal()
			if n.y <= 0.7 and n.dot(-dir) > 0.8:
				return true
	return false


## Ends the grapple (arrow in flight or pull) and removes the arrow and cable.
## `action` is the debug readout for an ending without arrival.
func _end_grapple(arrived: bool, action := &"grapple_release") -> void:
	var pull := velocity
	var pulling := state == State.GRAPPLE
	grapple.detach()
	grapple.start_nock()
	if arrived:
		# Hop up and over the ledge the anchor sits on.
		var flat := Vector3(pull.x, 0.0, pull.z)
		if flat.length() < 0.1:
			flat = -global_basis.z
		velocity = flat.normalized() * grapple.hop_forward_speed + Vector3.UP * grapple.hop_up_speed
		last_action = &"grapple_arrive"
		_ledge_cooldown = maxf(_ledge_cooldown, 0.25)
	else:
		# Let go: hand control back to normal movement with the way the player
		# was going. Never adds anything; out of a pull only the part a body
		# carries on with stays (see Grapple.release_speed), so letting go by a
		# wall or under a ledge isn't a launch. Ledges can be caught at once.
		if pulling:
			velocity = grapple.release_velocity(velocity)
		last_action = action
	_coyote = 0.0
	# Letting go of a shot fired on the ground is not a landing.
	_was_on_floor = is_on_floor() and not arrived
	_set_state(State.MOVE)
	grapple_finished.emit(arrived)


## F in the air starts slow time when it's ready and there's a real drop below.
func _try_air_bullet_time() -> bool:
	if not bullet_time.is_ready():
		return false
	var from := global_position + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (bullet_time_min_height + 0.1), sensor.collision_mask)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	if bullet_time.activate():
		last_action = &"slow_time"
		return true
	return false


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)
