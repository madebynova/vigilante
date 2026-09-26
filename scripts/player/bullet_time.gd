class_name BulletTime
extends Node
## Timed slow-time ability. activate() slows the whole game to `time_scale`
## for `duration` seconds, then it ends by itself and recharges over
## `cooldown` seconds. Durations are real seconds, so the slow-down itself
## doesn't stretch them.

signal started
signal ended

## Engine.time_scale while active.
@export_range(0.05, 1.0) var time_scale := 0.3
## How long slow time lasts, in real seconds.
@export var duration := 0.4
## Recharge time after it ends, in real seconds.
@export var cooldown := 4.0

var active := false

var _end_usec := 0
var _ready_usec := 0


func is_ready() -> bool:
	return not active and Time.get_ticks_usec() >= _ready_usec


## Starts slow time if it's available. Returns true if it started.
func activate() -> bool:
	if not is_ready():
		return false
	active = true
	_end_usec = Time.get_ticks_usec() + int(duration * 1_000_000)
	Engine.time_scale = time_scale
	started.emit()
	return true


## Real seconds of slow time left (0 when inactive).
func time_left() -> float:
	return maxf((_end_usec - Time.get_ticks_usec()) / 1_000_000.0, 0.0) if active else 0.0


## Real seconds until it can be used again (0 when ready).
func cooldown_left() -> float:
	return 0.0 if active else maxf((_ready_usec - Time.get_ticks_usec()) / 1_000_000.0, 0.0)


## Ends slow time now and makes the ability ready again (respawn / reset).
func reset() -> void:
	if active:
		active = false
		Engine.time_scale = 1.0
		ended.emit()
	_ready_usec = 0


func _process(_delta: float) -> void:
	if active and Time.get_ticks_usec() >= _end_usec:
		active = false
		Engine.time_scale = 1.0
		_ready_usec = Time.get_ticks_usec() + int(cooldown * 1_000_000)
		ended.emit()
