class_name PlayerHUD
extends Control
## The player's own feedback, drawn over the view: the grapple reticle and the
## slow-time meter. Sizes are 1920x1080 base pixels (the canvas_items stretch
## mode scales them with the window).
##
## Grapple reticle:
##   - a faint dot at the screen centre (where the camera aims),
##   - a circle around the anchor a press would fire at (valid target),
##   - a crossed circle around an aimed-at anchor that can't be used, with why
##     (out of range, too close, no line of sight).
## Slow-time meter: a thin bar under the prompt while slow time runs or
## recharges, gone once it's ready again.

const COLOR_VALID := Color(1.0, 0.76, 0.28)
const COLOR_INVALID := Color(1.0, 0.36, 0.3)
const COLOR_DOT := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_OUTLINE := Color(0.0, 0.0, 0.0, 0.6)
const RING_RADIUS := 26.0
const FONT_SIZE := 20

const BLOCK_TEXT := {
	Grapple.Block.TOO_FAR: "OUT OF RANGE",
	Grapple.Block.TOO_CLOSE: "TOO CLOSE",
	Grapple.Block.BLOCKED: "NO LINE OF SIGHT",
}

## The player whose grapple and slow time are shown (defaults to the owner).
@export var player: Player

var _pulse := 0.0
var _last_target: GrappleAnchor
var _meter_alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if player == null:
		player = owner as Player


func _process(delta: float) -> void:
	if player == null:
		return
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	var target := _shown_target()
	if target != _last_target:
		_last_target = target
		_pulse = 1.0 if target != null else 0.0
	_pulse = move_toward(_pulse, 0.0, real_delta * 6.0)
	var bt := player.bullet_time
	var meter_on := bt.active or not bt.is_ready()
	_meter_alpha = move_toward(_meter_alpha, 1.0 if meter_on else 0.0, real_delta * (6.0 if meter_on else 2.0))
	queue_redraw()


## The anchor the reticle circles: the current target, or the arrow's anchor
## while it flies and pulls.
func _shown_target() -> GrappleAnchor:
	var g := player.grapple
	if g.anchor != null and is_instance_valid(g.anchor):
		return g.anchor
	return g.target


func _draw() -> void:
	if player == null or not player.visible:
		return
	var cam := player.camera.camera
	var center := size * 0.5
	var target := _shown_target()
	var g := player.grapple
	if target != null:
		var p := _project(cam, target.global_position)
		if p.x != INF:
			var r := RING_RADIUS * (1.0 + _pulse * 0.5)
			_ring(p, r, COLOR_VALID, 3.0)
			if g.arrow != null:
				draw_circle(p, 6.0, COLOR_VALID) # fired: the arrow is on its way / holding
			else:
				_label(p + Vector2(r + 10.0, 7.0), UiStyle.key_text(&"grapple"), COLOR_VALID, HORIZONTAL_ALIGNMENT_LEFT)
	elif g.aimed != null and is_instance_valid(g.aimed):
		var p := _project(cam, g.aimed.global_position)
		if p.x != INF:
			var c := Color(COLOR_INVALID, 0.85)
			_ring(p, RING_RADIUS, c, 2.5)
			var d := RING_RADIUS * 0.62
			_line(p + Vector2(-d, -d), p + Vector2(d, d), c)
			_line(p + Vector2(-d, d), p + Vector2(d, -d), c)
			_label(p + Vector2(0.0, RING_RADIUS + 24.0), BLOCK_TEXT.get(g.aimed_block, ""), c, HORIZONTAL_ALIGNMENT_CENTER)
	if player.state != Player.State.TRAVERSAL:
		draw_circle(center, 3.5, COLOR_OUTLINE)
		draw_circle(center, 2.2, COLOR_DOT)
	_draw_slow_time_meter()


func _draw_slow_time_meter() -> void:
	if _meter_alpha <= 0.0:
		return
	var bt := player.bullet_time
	var fill := 0.0
	var color := Color(0.62, 0.8, 1.0)
	if bt.active:
		fill = bt.time_left() / maxf(bt.duration, 0.01)
		color = Color(0.75, 0.9, 1.0)
	elif not bt.is_ready():
		fill = 1.0 - bt.cooldown_left() / maxf(bt.cooldown, 0.01)
		color = Color(0.5, 0.58, 0.68)
	else:
		fill = 1.0
	var w := 170.0
	var rect := Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y * 0.9), Vector2(w, 6.0))
	draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.45 * _meter_alpha))
	draw_rect(Rect2(rect.position, Vector2(w * clampf(fill, 0.0, 1.0), rect.size.y)), Color(color, _meter_alpha))
	_label(rect.position + Vector2(w * 0.5, -10.0), "SLOW TIME", Color(1, 1, 1, 0.8 * _meter_alpha), HORIZONTAL_ALIGNMENT_CENTER)


## Canvas position of `world` (unproject_position already works in the
## stretched 1920x1080 canvas), or (INF, INF) if it's behind the camera.
func _project(cam: Camera3D, world: Vector3) -> Vector2:
	if cam.is_position_behind(world):
		return Vector2(INF, INF)
	return cam.unproject_position(world)


func _ring(p: Vector2, r: float, color: Color, width: float) -> void:
	draw_arc(p, r, 0.0, TAU, 40, COLOR_OUTLINE, width + 3.0, true)
	draw_arc(p, r, 0.0, TAU, 40, color, width, true)


func _line(a: Vector2, b: Vector2, color: Color) -> void:
	draw_line(a, b, COLOR_OUTLINE, 5.5, true)
	draw_line(a, b, color, 2.5, true)


func _label(pos: Vector2, text: String, color: Color, align: HorizontalAlignment) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var at := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		at.x -= w * 0.5
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 5, COLOR_OUTLINE)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)

