class_name Mission
extends Node3D
## A short objective run: its MissionStep children, in order, each a place the
## player has to reach, however they choose to get there. The clock starts on
## the player's first move and stops on the last step; the best time is kept
## (SaveData). R (respawn) restarts the run from the spawn point.
##
## Deliberately small: a mission is data (steps in a scene) plus this one
## script, so later missions are new scenes rather than new code.

signal started
## `step` is now the objective (index in steps).
signal step_started(step: MissionStep, index: int)
## `step` was just reached.
signal step_reached(step: MissionStep, index: int)
## The run is over: see `result`.
signal completed

enum Phase { READY, RUNNING, COMPLETE }

## Shown big on the intro card, e.g. "DEAD DROP".
@export var title := ""
## A line or two of context under the title.
@export_multiline var briefing := ""
## Best times are saved under this key.
@export var save_key: StringName = &"mission"
@export var player: Player
## Par times (seconds) for the three ratings.
@export var par_gold := 40.0
@export var par_silver := 60.0
@export var par_bronze := 90.0
## Switch the city to night when the mission starts.
@export var start_at_night := true

var steps: Array[MissionStep] = []
var phase := Phase.READY
var step_index := -1
## Game seconds since the player first moved (bullet time runs it slower, a
## pause stops it).
var elapsed := 0.0
## A debug jump (number keys) was used during this run: its time isn't saved.
var assisted := false
## {time, best, new_best, rating, assisted} of the last finished run.
var result := {}

var _beacon: ObjectiveBeacon


func _ready() -> void:
	for child in get_children():
		if child is MissionStep:
			var step := child as MissionStep
			steps.append(step)
			step.reached.connect(_on_step_reached.bind(step))
	_beacon = ObjectiveBeacon.new()
	_beacon.name = "Beacon"
	add_child(_beacon)
	if player != null:
		player.respawned.connect(start)
		player.teleported.connect(_on_teleported)
	if start_at_night:
		_set_night.call_deferred()
	start.call_deferred()


## (Re)starts the run: every step back in place, the first one active, the
## clock waiting for the player to move.
func start() -> void:
	phase = Phase.READY
	elapsed = 0.0
	assisted = false
	result = {}
	for step in steps:
		step.reset()
	started.emit()
	_begin_step(0)


## Restarts from the spawn point (same as R).
func restart() -> void:
	if player != null:
		player.respawn() # -> respawned -> start()
	else:
		start()


func current_step() -> MissionStep:
	return steps[step_index] if step_index >= 0 and step_index < steps.size() else null


func best_time() -> float:
	return SaveData.best_time(save_key)


## "GOLD" / "SILVER" / "BRONZE" / "" for a run of `seconds`.
func rating_for(seconds: float) -> String:
	if seconds <= par_gold:
		return "GOLD"
	if seconds <= par_silver:
		return "SILVER"
	if seconds <= par_bronze:
		return "BRONZE"
	return ""


## The next rating to aim for after `seconds` ("" at gold), with its par.
func next_par(seconds: float) -> Dictionary:
	if seconds > par_bronze:
		return {rating = "BRONZE", time = par_bronze}
	if seconds > par_silver:
		return {rating = "SILVER", time = par_silver}
	if seconds > par_gold:
		return {rating = "GOLD", time = par_gold}
	return {}


func _physics_process(delta: float) -> void:
	if player == null:
		return
	match phase:
		Phase.READY:
			# The first real move (not settling onto the floor, not looking around).
			if player.wish_dir.length() > 0.1 or player.horizontal_speed() > 0.5 or player.velocity.y > 1.0:
				phase = Phase.RUNNING
		Phase.RUNNING:
			elapsed += delta


func _begin_step(index: int) -> void:
	step_index = index
	var step := current_step()
	if step == null:
		_beacon.visible = false
		return
	step.activate()
	if step.active:
		_beacon.place(step.marker_position())
		step_started.emit(step, index)


func _on_step_reached(step: MissionStep) -> void:
	var index := steps.find(step)
	if index != step_index or phase == Phase.COMPLETE:
		return
	if phase == Phase.READY:
		phase = Phase.RUNNING # reached without moving first (e.g. dropped in)
	step_reached.emit(step, index)
	if index + 1 < steps.size():
		_begin_step(index + 1)
	else:
		_complete()


func _complete() -> void:
	phase = Phase.COMPLETE
	step_index = steps.size()
	_beacon.visible = false
	var new_best := false
	if not assisted:
		new_best = SaveData.submit_time(save_key, elapsed)
	result = {time = elapsed, best = best_time(), new_best = new_best,
			rating = "" if assisted else rating_for(elapsed), assisted = assisted}
	if player != null:
		# A beat of slow motion to land the finish.
		player.bullet_time.reset()
		player.bullet_time.activate()
	completed.emit()


func _on_teleported() -> void:
	if phase != Phase.COMPLETE:
		assisted = true # cleared again by start() when this was a respawn


func _set_night() -> void:
	var day_night := get_tree().get_first_node_in_group(DayNight.GROUP) as DayNight
	if day_night != null:
		day_night.set_night(true, true)
