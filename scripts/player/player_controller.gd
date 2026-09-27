class_name Player
extends CharacterBody3D
## Third-person player controller: locomotion, jumping, crouching and the
## parkour entry points (vault, ledge grab/climb, window traversal, grapple).
##
## Responsibilities are split so each piece can grow on its own:
##   Locomotion        - velocity math (walk, sprint, air control, gravity)
##   ParkourSensor     - geometry queries (what can I vault / grab?)
##   ParkourMoves      - turns sensor results into TraversalMotions
##   TraversalWindow   - window openings and their motions
##   InteractionPrompt - on-screen contextual prompt ("[E] DIVE THROUGH")
##   BulletTime        - timed slow-time ability (Space)
##   Grapple           - grapple targeting (camera aim) and rope
##   PlayerCamera      - orbit camera and mouse capture
##   PlayerVisual      - character model + light procedural motion

enum State { MOVE, TRAVERSAL, LEDGE_HANG, WINDOW_APPROACH, GRAPPLE }

## How long a grapple press is remembered (game seconds), so pressing a hair
## before the grapple becomes possible (e.g. mid-dive) still counts.
const GRAPPLE_BUFFER := 0.2

signal state_changed(new_state: State)
signal traversal_started(id: StringName)
signal traversal_finished(id: StringName)
signal landed(impact_speed: float)
signal grapple_started(anchor: GrappleAnchor)
signal grapple_finished(arrived: bool)

@export var settings: MovementSettings

@export_group("Parkour")
## Sprinting into a vaultable obstacle closer than this vaults automatically.
@export var auto_vault_distance := 0.55
## Ledges are only grabbed once upward speed has dropped below this.
@export var ledge_grab_max_rise_speed := 3.5
@export var ledge_regrab_delay := 0.35
@export var shimmy_speed := 1.6

@export_group("Slow time")
## In the air, Space starts slow time only with at least this much drop
## below the feet, so ordinary jumps (and buffered jumps) are unaffected.
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
# Debug readout.
var last_action: StringName = &"-"

var _input_dir := Vector2.ZERO
var _sprint_held := false
var _crouch_held := false
var _crouch_pressed := false
var _jump_held := false
var _jump_pressed := false
var _traverse_pressed := false
var _jump_buffer := 0.0
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
		State.GRAPPLE:
			_process_grapple(delta)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_grapple_buffer = maxf(_grapple_buffer - delta, 0.0)
	_update_window_hint()

	var sprint_amount := clampf((horizontal_speed() - settings.walk_speed)
			/ (settings.sprint_speed - settings.walk_speed), 0.0, 1.0)
	camera.speed_amount = 1.0 if state == State.WINDOW_APPROACH else sprint_amount
	# Slow time keeps the tightened FOV the window sequence used to apply.
	camera.focus_amount = 1.0 if bullet_time.active else 0.0
	visual.tick(delta, velocity, sprint_amount if state == State.MOVE else 0.0)

	if global_position.y < fall_respawn_height:
		respawn()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Moves the player to `xform` and clears any in-progress action.
func teleport(xform: Transform3D) -> void:
	bullet_time.reset()
	grapple.detach()
	current_motion = null
	current_ledge = null
	_approach_window = null
	_dive_window = null
	_grapple_buffer = 0.0
	_recovery = 0.0
	velocity = Vector3.ZERO
	global_transform = xform
	_set_crouched(false)
	visual.tucked = false
	visual.traversal_pitch = 0.0
	visual.tumble = 0.0
	_set_state(State.MOVE)
	reset_physics_interpolation()
	camera.yaw = rotation.y
	camera.snap()


func respawn() -> void:
	teleport(_spawn)
	last_action = &"respawn"


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
	_jump_held = Input.is_action_pressed(&"jump")
	_traverse_pressed = Input.is_action_just_pressed(&"traverse")
	_jump_pressed = Input.is_action_just_pressed(&"jump")
	if _jump_pressed:
		_jump_buffer = settings.jump_buffer_time
	if Input.is_action_just_pressed(&"grapple"):
		_grapple_buffer = GRAPPLE_BUFFER
	if Input.is_action_just_pressed(&"debug_respawn"):
		respawn()


# --- Free movement -----------------------------------------------------------

func _process_move(delta: float) -> void:
	var on_floor := is_on_floor()
	_coyote = settings.coyote_time if on_floor else maxf(_coyote - delta, 0.0)
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
		if (_jump_buffer > 0.0 or _traverse_pressed) and _try_vault(false):
			return
		if is_sprinting and _try_vault(true):
			return
	elif _try_window() or _try_ledge(): # in the air only dive windows (E) apply
		return
	elif _jump_pressed and _coyote <= 0.0 and _try_air_bullet_time():
		_jump_buffer = 0.0 # the press was used for slow time, not a buffered jump

	var target_speed := settings.walk_speed
	if is_crouching:
		target_speed = settings.crouch_speed
	elif is_sprinting:
		target_speed = settings.sprint_speed
	if _recovery > 0.0:
		target_speed *= 0.45

	var hvel: Vector3
	if on_floor:
		hvel = Locomotion.ground(velocity, wish_dir, target_speed, settings, delta)
	else:
		hvel = Locomotion.air(velocity, wish_dir, target_speed, settings, delta)
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
		velocity.y = Locomotion.apply_gravity(velocity.y, _jump_held, settings, delta)

	if wish_dir.length() > 0.1:
		_face(wish_dir, settings.turn_sharpness if on_floor else settings.air_turn_sharpness, delta)

	var fall_speed := -velocity.y
	move_and_slide()
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		visual.on_landed(fall_speed)
		if fall_speed > 12.0:
			camera.add_shake(clampf((fall_speed - 12.0) / 20.0, 0.0, 0.4))
		landed.emit(fall_speed)
	_was_on_floor = grounded


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
	for window in _windows:
		if window.dive_window and window.covers_point(obstacle.wall_point):
			return false # dive windows are only taken with the Traverse button
	_jump_buffer = 0.0
	_start_motion(ParkourMoves.vault(obstacle, global_position, speed))
	return true


func _try_ledge() -> bool:
	if _ledge_cooldown > 0.0 or velocity.y > ledge_grab_max_rise_speed or wish_dir.length() < 0.3:
		return false
	var ledge := sensor.detect_ledge(global_position, wish_dir)
	if ledge == null or wish_dir.normalized().dot(-ledge.wall_normal) < 0.5:
		return false
	if ledge.can_hang:
		current_ledge = ledge
		velocity = Vector3.ZERO
		last_action = &"ledge_grab"
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


# --- Scripted traversal ------------------------------------------------------

func _start_motion(motion: TraversalMotion) -> void:
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
	if motion.id == &"window_dive" and _grapple_buffer > 0.0 and grapple.target != null \
			and _clear_of_dive_window():
		var anchor := grapple.target
		_end_motion(false)
		_start_grapple(anchor)
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
				if airborne:
					_start_window_dive(window, maxf(speed, settings.sprint_speed)) # already in the air: dive now
				else:
					_begin_window_dive(window, maxf(speed, settings.sprint_speed))
				return true
			continue
		if airborne:
			continue # plain windows keep their on-foot behaviour only
		var sprinting_at := speed >= window.auto_speed and window.is_lined_up(pos, hvel)
		if sprinting_at and dist <= window.takeoff_distance + 0.2:
			_start_motion(window.build_motion(pos, speed, TraversalWindow.Style.VAULT))
			return true
		if (_traverse_pressed or _jump_buffer > 0.0) and dist <= window.climb_distance \
				and window.is_lined_up(pos, _move_or_facing_dir()):
			_jump_buffer = 0.0
			var style := TraversalWindow.Style.CLIMB
			if speed > settings.walk_speed * 0.8:
				style = TraversalWindow.Style.VAULT
			_start_motion(window.build_motion(pos, maxf(speed, settings.walk_speed), style))
			return true
	return false


## True if pressing E right now would dive through `window` (also drives the
## prompt, so the prompt only shows when E will actually work).
func _can_dive_position(window: TraversalWindow) -> bool:
	return window.dive_window and window.distance_to_wall(global_position) <= window.dive_distance \
			and window.feet_in_reach(global_position) \
			and window.is_lined_up(global_position, _move_or_facing_dir())


func _can_dive(window: TraversalWindow) -> bool:
	return _traverse_pressed and _can_dive_position(window)


## Shows "[E] DIVE THROUGH" exactly when pressing E would start the dive.
func _update_window_hint() -> void:
	var show := false
	if state == State.MOVE and not is_crouching: # on foot or mid-jump
		for window in _windows:
			if _can_dive_position(window):
				show = true
	if show:
		prompt.set_hint(&"traverse", "DIVE THROUGH")
	else:
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
		State.MOVE, State.TRAVERSAL:
			grapple.update_target(global_position + Vector3.UP * 1.2, camera.camera)
		State.GRAPPLE:
			pass # keep the attached anchor highlighted
		_:
			grapple.clear_target()


## Grapple press with a valid target: start the pull (on the ground or in the air).
func _try_grapple() -> bool:
	if _grapple_buffer <= 0.0 or grapple.target == null:
		return false
	_start_grapple(grapple.target)
	return true


func _start_grapple(anchor: GrappleAnchor) -> void:
	_grapple_buffer = 0.0
	if is_crouching:
		_try_stand()
	grapple.attach(anchor)
	_grapple_time = 0.0
	_grapple_best = global_position.distance_to(anchor.global_position)
	_grapple_stall = 0.0
	current_ledge = null
	last_action = &"grapple"
	_set_state(State.GRAPPLE)
	grapple_started.emit(anchor)


## Pulled straight toward the anchor. Ends on arrival, when blocked, on timeout,
## if the anchor goes away, or when grapple is pressed again (let go).
func _process_grapple(delta: float) -> void:
	var anchor := grapple.attached
	if anchor == null or not is_instance_valid(anchor) or not anchor.enabled:
		_end_grapple(false)
		return
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
	velocity = velocity.move_toward(to_target / distance * grapple.pull_speed, grapple.pull_acceleration * delta)
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length() > 0.3:
		_face(flat, 14.0, delta)
	move_and_slide()
	if distance < _grapple_best - 0.05:
		_grapple_best = distance
		_grapple_stall = 0.0
	else:
		_grapple_stall += delta
	if _grapple_stall > 0.3 or _grapple_time > grapple.max_pull_time:
		_end_grapple(false) # blocked by geometry or taking too long


func _end_grapple(arrived: bool) -> void:
	var pull := velocity
	grapple.detach()
	if arrived:
		# Hop up and over the ledge the anchor sits on.
		var flat := Vector3(pull.x, 0.0, pull.z)
		if flat.length() < 0.1:
			flat = -global_basis.z
		velocity = flat.normalized() * grapple.hop_forward_speed + Vector3.UP * grapple.hop_up_speed
		last_action = &"grapple_arrive"
	else:
		last_action = &"grapple_release"
	_coyote = 0.0
	_was_on_floor = false
	_ledge_cooldown = maxf(_ledge_cooldown, 0.25)
	_set_state(State.MOVE)
	grapple_finished.emit(arrived)


## Space in the air starts slow time when it's ready and there's a real drop
## below (so it never steals a normal or buffered jump near the ground).
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
