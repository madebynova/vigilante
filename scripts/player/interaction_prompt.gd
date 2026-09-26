class_name InteractionPrompt
extends Control
## Small contextual prompt, e.g. "[E] DIVE THROUGH": the key for an input
## action (read from the Input Map) plus a short label, in the lower part of
## the screen. Sizes are 1920x1080 base pixels; the canvas_items stretch mode
## scales them with the window.

## Vertical position as a fraction of the screen height (lower fifth, clear
## of the character in the middle of the frame).
const ANCHOR_Y := 0.8
const CAP_HEIGHT := 70.0
const KEY_FONT := 34
const LABEL_FONT := 30
const COLOR_TEXT := Color(0.96, 0.97, 1.0)
const COLOR_OUTLINE := Color(0, 0, 0, 0.85)

var _action: StringName = &""
var _label := ""
var _cap_style := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_cap_style.bg_color = Color(0.05, 0.07, 0.1, 0.85)
	_cap_style.set_corner_radius_all(22)
	_cap_style.set_border_width_all(3)
	_cap_style.border_color = Color(COLOR_TEXT, 0.9)
	_cap_style.anti_aliasing = true
	_cap_style.shadow_color = Color(0, 0, 0, 0.35)
	_cap_style.shadow_size = 10


## Shows the key for `action` with a short label.
func set_hint(action: StringName, label: String) -> void:
	if action == _action and label == _label and visible:
		return
	_action = action
	_label = label
	visible = true
	queue_redraw()


func clear_hint() -> void:
	if _action == &"":
		return
	_action = &""
	visible = false


## "E DIVE THROUGH" while shown, "" otherwise.
func hint_text() -> String:
	return "" if _action == &"" else "%s %s" % [action_key_text(_action), _label]


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if _action == &"":
		return
	var font := ThemeDB.fallback_font
	var center := Vector2(size.x * 0.5, size.y * ANCHOR_Y)
	var key_text := action_key_text(_action)
	var key_width := font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT).x
	var label_width := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT).x
	var cap := Vector2(maxf(key_width + 40.0, 80.0), CAP_HEIGHT)
	var total := cap.x + 20.0 + label_width
	var cap_center := Vector2(center.x - total * 0.5 + cap.x * 0.5, center.y)
	draw_style_box(_cap_style, Rect2(cap_center - cap * 0.5, cap))
	var key_pos := Vector2(cap_center.x - key_width * 0.5,
			cap_center.y + (font.get_ascent(KEY_FONT) - font.get_descent(KEY_FONT)) * 0.5)
	draw_string_outline(font, key_pos, key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT, 8, COLOR_OUTLINE)
	draw_string(font, key_pos, key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT, COLOR_TEXT)
	var label_pos := Vector2(cap_center.x + cap.x * 0.5 + 20.0, center.y + 11.0)
	draw_string_outline(font, label_pos, _label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, 6, COLOR_OUTLINE)
	draw_string(font, label_pos, _label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, COLOR_TEXT)


## Display name of the first keyboard key bound to `action`, e.g. "E".
static func action_key_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code).to_upper()
	return String(action).to_upper()
