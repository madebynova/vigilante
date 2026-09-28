@tool
class_name MissionStep
extends Area3D
## One objective of a Mission: get the player into this area. Its collision
## shapes are the goal (a small zone around a package, a whole building...);
## any way in counts. Children can be props that belong to the step (the
## package): they are hidden once the step is done and shown again on a
## restart.

signal reached

## Objective line on the HUD, e.g. "Intercept the drop".
@export var objective := ""
## Where, e.g. "Hotel roof" (shown under the objective).
@export var location := ""
## Big line shown when the step is done, e.g. "PACKAGE SECURED" (optional).
@export var done_title := ""
## Where the marker and the beacon point, relative to this node.
@export var marker_offset := Vector3.ZERO
## Props under this node are hidden once reached.
@export var hide_children_when_reached := true

var active := false
var done := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	monitorable = false
	body_entered.connect(_on_body_entered)


func marker_position() -> Vector3:
	return global_position + global_basis * marker_offset


## Makes this the current objective (the player entering it now completes it).
func activate() -> void:
	active = true
	done = false
	_show_props(true)
	# Already standing in it (e.g. a restart right on top of it).
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func reset() -> void:
	active = false
	done = false
	_show_props(true)


func _on_body_entered(body: Node3D) -> void:
	if not active or done or not (body is Player):
		return
	done = true
	active = false
	if hide_children_when_reached:
		_show_props(false)
	reached.emit()


func _show_props(value: bool) -> void:
	for child in get_children():
		if child is Node3D and not (child is CollisionShape3D):
			(child as Node3D).visible = value
