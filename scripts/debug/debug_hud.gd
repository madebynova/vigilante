extends CanvasLayer
## On-screen readout for movement testing. F1 toggles the controls list.

const CONTROLS := """
WASD move  |  Shift sprint  |  Space jump (in the air, high up: slow time)  |  C / Ctrl crouch
Window: E to dive through (from either side)  |  E elsewhere: vault / climb
Hanging: Space/E climb, A/D shimmy, C drop
Mouse orbit  |  Esc release mouse  |  Click recapture  |  R respawn  |  F1 hide help"""

@export var player: Player

var _show_help := true

@onready var _label: Label = $Label


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F1:
		_show_help = not _show_help


func _process(_delta: float) -> void:
	if player == null:
		return
	var bt := player.bullet_time
	var slow := "ACTIVE %.1fs" % bt.time_left() if bt.active \
			else ("READY" if bt.is_ready() else "RECHARGING %.1fs" % bt.cooldown_left())
	var text := "FPS %d\nState: %s   Last move: %s   Slow time: %s\nSpeed %.1f m/s   Vertical %.1f   %s%s%s" % [
		Engine.get_frames_per_second(),
		Player.State.keys()[player.state],
		player.last_action,
		slow,
		player.horizontal_speed(),
		player.velocity.y,
		"GROUNDED" if player.is_on_floor() else "AIR",
		"  SPRINT" if player.is_sprinting else "",
		"  CROUCH" if player.is_crouching else "",
	]
	if _show_help:
		text += "\n" + CONTROLS
	_label.text = text
