class_name MissionHUD
extends CanvasLayer
## The mission's side of the screen, kept small: the objective (top left),
## the run clock (top right), a marker on the objective (clamped to the screen
## edge when it's off screen), and short centre cards for the briefing, each
## step reached and the finish. One-off tips go above the prompt.

const MARKER_MARGIN := 70.0
## Hide the marker this close to the objective: the beacon is right there.
const MARKER_HIDE_DISTANCE := 5.0
const INTRO_HOLD := 6.0
const STEP_HOLD := 2.8
const FINISH_HOLD := 9.0
const TIP_HOLD := 6.0

@export var mission: Mission
@export var player: Player

var _root: Control
var _marker: Control
var _mission_label: Label
var _objective_label: Label
var _detail_label: Label
var _timer_label: Label
var _best_label: Label
var _card: VBoxContainer
var _card_title: Label
var _card_lines: Label
var _card_small: Label
var _tip: Label
var _card_time := 0.0
var _card_hold := 0.0
var _tip_time := 0.0
var _tip_hold := 0.0
var _first_start := true


func _ready() -> void:
	layer = 5
	# Keeps running while paused, to step aside for the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if mission != null:
		mission.started.connect(_on_started)
		mission.step_reached.connect(_on_step_reached)
		mission.completed.connect(_on_completed)
	if player != null:
		player.staggered.connect(_on_staggered)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_root.add_child(_marker)

	var objective := VBoxContainer.new()
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective.position = Vector2(56, 40)
	objective.add_theme_constant_override(&"separation", 2)
	_root.add_child(objective)
	_mission_label = UiStyle.label(20, UiStyle.ACCENT, true, 6)
	_objective_label = UiStyle.label(34)
	_detail_label = UiStyle.label(22, UiStyle.DIM, false, 6)
	objective.add_child(_mission_label)
	objective.add_child(_objective_label)
	objective.add_child(_detail_label)

	var clock := VBoxContainer.new()
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.offset_left = -520.0
	clock.offset_right = -56.0
	clock.offset_top = 36.0
	clock.add_theme_constant_override(&"separation", 0)
	_root.add_child(clock)
	_timer_label = UiStyle.label(40, UiStyle.TEXT, true)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_best_label = UiStyle.label(20, UiStyle.DIM, false, 6)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.add_child(_timer_label)
	clock.add_child(_best_label)

	_card = VBoxContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_card.offset_top = 250.0
	_card.alignment = BoxContainer.ALIGNMENT_BEGIN
	_card.add_theme_constant_override(&"separation", 10)
	_root.add_child(_card)
	_card_title = UiStyle.label(64, UiStyle.TEXT, true, 12)
	_card_lines = UiStyle.label(28, UiStyle.TEXT, false, 8)
	_card_small = UiStyle.label(22, UiStyle.DIM, false, 6)
	for l: Label in [_card_title, _card_lines, _card_small]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_card.add_child(l)
	_card.modulate.a = 0.0

	_tip = UiStyle.label(24, UiStyle.TEXT, false, 7)
	_tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tip.offset_top = -330.0
	_tip.offset_bottom = -290.0
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.modulate.a = 0.0
	_root.add_child(_tip)


func _process(delta: float) -> void:
	var real_delta := 0.0 if get_tree().paused else delta / maxf(Engine.time_scale, 0.01)
	_update_objective()
	_update_clock()
	_card_time += real_delta
	_card.modulate.a = _fade(_card_time, _card_hold, 0.25, 0.7)
	# Out of the way of the pause menu and the controls panel.
	var menu := get_tree().get_first_node_in_group(PauseMenu.GROUP) as PauseMenu
	_card.visible = menu == null or not menu.is_open()
	_tip_time += real_delta
	_tip.modulate.a = _fade(_tip_time, _tip_hold, 0.3, 0.8)
	_marker.queue_redraw()


func _update_objective() -> void:
	if mission == null:
		return
	_set_text(_mission_label, mission.title)
	var step := mission.current_step()
	if mission.phase == Mission.Phase.COMPLETE:
		_set_text(_objective_label, "Run complete")
		_set_text(_detail_label, "%s  run it again" % UiStyle.key_text(&"debug_respawn"))
	elif step != null:
		_set_text(_objective_label, step.objective)
		var parts: PackedStringArray = []
		if step.location != "":
			parts.append(step.location)
		if player != null:
			parts.append("%d m" % roundi(player.global_position.distance_to(step.marker_position())))
		_set_text(_detail_label, "  ·  ".join(parts))


func _update_clock() -> void:
	if mission == null:
		_set_text(_timer_label, "")
		_set_text(_best_label, "")
		return
	var best := mission.best_time()
	if mission.phase == Mission.Phase.COMPLETE:
		_set_text(_timer_label, UiStyle.format_time(mission.result.get("time", 0.0)))
	else:
		_set_text(_timer_label, UiStyle.format_time(mission.elapsed))
	_timer_label.modulate.a = 0.55 if mission.phase == Mission.Phase.READY else 1.0
	_set_text(_best_label, "BEST %s" % UiStyle.format_time(best) if not is_inf(best) else "")


## Diamond on the objective with its distance; clamped to the screen edge
## (pointing the way) when it's off screen or behind.
func _draw_marker() -> void:
	if mission == null or player == null or mission.phase == Mission.Phase.COMPLETE:
		return
	var step := mission.current_step()
	if step == null:
		return
	var cam := player.camera.camera
	var world := step.marker_position() + Vector3.UP * 1.3
	var distance := player.global_position.distance_to(step.marker_position())
	if distance < MARKER_HIDE_DISTANCE:
		return
	var size := _marker.size
	var center := size * 0.5
	var behind := cam.is_position_behind(world)
	var half := center - Vector2(MARKER_MARGIN, MARKER_MARGIN)
	var p := cam.unproject_position(world)
	var d := p - center
	if behind:
		# Behind the camera: pin it to the side to turn toward, at a height
		# that says above or below.
		var local := cam.global_transform.affine_inverse() * world
		var up := clampf(local.y / maxf(Vector2(local.x, local.z).length(), 0.1), -1.0, 1.0)
		d = Vector2(1.0 if local.x >= 0.0 else -1.0, -up * 0.8)
	var edge := behind or absf(d.x) > half.x or absf(d.y) > half.y
	if edge:
		if d.length() < 1.0:
			d = Vector2(0.0, 1.0)
		var s := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
		p = center + d * s
	var c := UiStyle.ACCENT
	var r := 13.0
	var diamond := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	_marker.draw_colored_polygon(diamond, Color(0, 0, 0, 0.35))
	var outline := diamond.duplicate()
	outline.append(diamond[0])
	_marker.draw_polyline(outline, UiStyle.OUTLINE, 6.0, true)
	_marker.draw_polyline(outline, c, 3.0, true)
	_marker.draw_circle(p, 3.5, c)
	if edge:
		var dir := d.normalized()
		var tip := p + dir * (r + 16.0)
		var side := Vector2(-dir.y, dir.x) * 8.0
		_marker.draw_colored_polygon(PackedVector2Array([tip, p + dir * (r + 5.0) + side, p + dir * (r + 5.0) - side]), c)
	var font := ThemeDB.fallback_font
	var text := "%d m" % roundi(distance)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var at := p + Vector2(-w * 0.5, r + 26.0)
	if edge and d.y > 0.0 and absf(d.y) * half.x >= absf(d.x) * half.y:
		at.y = p.y - r - 12.0 # bottom edge: label above
	_marker.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, UiStyle.OUTLINE)
	_marker.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiStyle.TEXT)


# --- Cards and tips ------------------------------------------------------------

func _on_started() -> void:
	if _first_start:
		_first_start = false
		_show_card(mission.title, mission.briefing, "Move to start the clock  ·  Esc pause  ·  F1 controls", INTRO_HOLD)
	else:
		_show_card(mission.title, "", "Move to start the clock", 2.5)


func _on_step_reached(step: MissionStep, index: int) -> void:
	if index + 1 >= mission.steps.size():
		return # the finish card covers the last one
	var next := mission.steps[index + 1]
	_show_card(step.done_title, next.objective, next.location, STEP_HOLD)


func _on_completed() -> void:
	var r := mission.result
	var last := mission.steps.back() as MissionStep
	var lines := "%s" % UiStyle.format_time(r.time)
	var small: PackedStringArray = []
	if r.assisted:
		small.append("Debug jump used: time not saved")
	elif r.new_best:
		small.append("NEW BEST")
	else:
		small.append("BEST %s" % UiStyle.format_time(r.best))
	if r.rating != "":
		small.append("%s  (par %s)" % [r.rating, UiStyle.format_time(_par_for(r.rating))])
	var next := mission.next_par(r.time) if not r.assisted else {}
	if not next.is_empty():
		small.append("%s at %s" % [next.rating.capitalize(), UiStyle.format_time(next.time)])
	small.append("%s  run it again" % UiStyle.key_text(&"debug_respawn"))
	_show_card(last.done_title if last.done_title != "" else "COMPLETE", lines, "\n".join(small), FINISH_HOLD)
	_card_lines.add_theme_font_size_override(&"font_size", 56)


func _on_staggered(_hard: bool) -> void:
	if SaveData.flag(&"tip_roll"):
		return
	SaveData.set_flag(&"tip_roll")
	show_tip("Tip: tap %s just before you land to roll out of it and keep your speed." % UiStyle.key_text(&"crouch"))


func show_tip(text: String) -> void:
	_tip.text = text
	_tip_time = 0.0
	_tip_hold = TIP_HOLD


func _show_card(title: String, lines: String, small: String, hold: float) -> void:
	_card_title.text = title
	_card_title.visible = title != ""
	_card_lines.text = lines
	_card_lines.visible = lines != ""
	_card_lines.add_theme_font_size_override(&"font_size", 28)
	_card_small.text = small
	_card_small.visible = small != ""
	_card_time = 0.0
	_card_hold = hold


func _par_for(rating: String) -> float:
	match rating:
		"GOLD":
			return mission.par_gold
		"SILVER":
			return mission.par_silver
	return mission.par_bronze


## Alpha for something shown `t` seconds ago that holds for `hold` seconds.
static func _fade(t: float, hold: float, fade_in: float, fade_out: float) -> float:
	if hold <= 0.0:
		return 0.0
	if t < fade_in:
		return t / fade_in
	if t < hold:
		return 1.0
	return clampf(1.0 - (t - hold) / fade_out, 0.0, 1.0)


static func _set_text(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text
