extends CanvasLayer
## Developer readout (state, last move, speeds, wall-run hint), hidden by
## default: F3 shows it. Debug keys work either way: 1-5 jump to the
## traversal playground sections / city districts, N toggles day / night
## where the scene has a DayNight node (the city). The controls list lives in
## the pause menu (Esc) and the F1 panel.

## Marker3Ds a number key can jump to, named Start1..Start5.
const START_GROUP := &"playground_start"

@export var player: Player
## Start with the readout on screen.
@export var show_readout := false

@onready var _label: Label = $Label


func _ready() -> void:
	if player != null:
		player.debug_wall_run_hint = true
	visible = show_readout


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.is_action_pressed(&"debug_day_night"):
		var day_night := get_tree().get_first_node_in_group(DayNight.GROUP) as DayNight
		if day_night != null:
			day_night.toggle()
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_F3:
		visible = not visible
	elif key >= KEY_1 and key <= KEY_5:
		teleport_to_section(key - KEY_1 + 1)


## Moves the player to the start of playground section `number` (1-5).
func teleport_to_section(number: int) -> void:
	if player == null:
		return
	for marker in get_tree().get_nodes_in_group(START_GROUP):
		if marker.name == "Start%d" % number:
			player.teleport((marker as Node3D).global_transform)
			player.last_action = &"section_%d" % number
			return


func _process(_delta: float) -> void:
	if player == null:
		return
	var bt := player.bullet_time
	var slow := "ACTIVE %.1fs" % bt.time_left() if bt.active \
			else ("READY" if bt.is_ready() else "RECHARGING %.1fs" % bt.cooldown_left())
	var target := player.grapple.target
	var day_night := get_tree().get_first_node_in_group(DayNight.GROUP) as DayNight
	_label.text = "FPS %d%s\nState: %s   Last move: %s   Slow time: %s   Grapple target: %s\nSpeed %.1f m/s   Vertical %.1f   %s%s%s%s\n1-5 sections / districts  |  N day / night  |  F3 hide" % [
		Engine.get_frames_per_second(),
		("   %s (N)" % day_night.label()) if day_night != null else "",
		Player.State.keys()[player.state],
		player.last_action,
		slow,
		String(target.name) if target != null else "-",
		player.horizontal_speed(),
		player.velocity.y,
		"GROUNDED" if player.is_on_floor() else "AIR",
		"  SPRINT" if player.is_sprinting else "",
		"  CROUCH" if player.is_crouching else "",
		"     [%s]" % player.wall_run_hint if player.wall_run_hint != "" else "",
	]
