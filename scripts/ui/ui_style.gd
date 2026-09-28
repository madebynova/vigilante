class_name UiStyle
extends RefCounted
## Shared look for the game's UI (mission HUD, pause menu, controls panel):
## colours, fonts and small builders. Sizes are 1920x1080 base pixels; the
## canvas_items stretch mode scales everything with the window.

const TEXT := Color(0.96, 0.97, 1.0)
const DIM := Color(0.74, 0.79, 0.87)
const ACCENT := Color(1.0, 0.72, 0.3)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const PANEL := Color(0.04, 0.05, 0.08, 0.82)

static var _title_font: FontVariation


## The default font, letter-spaced and a little bolder, for titles.
static func title_font() -> Font:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = ThemeDB.fallback_font
		_title_font.spacing_glyph = 5
		_title_font.variation_embolden = 0.55
	return _title_font


## An outlined label that never takes the mouse.
static func label(size: int, color := TEXT, title := false, outline := 8) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", OUTLINE)
	l.add_theme_constant_override(&"outline_size", outline)
	if title:
		l.add_theme_font_override(&"font", title_font())
	return l


static func panel_style(color := PANEL, radius := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(28)
	s.anti_aliasing = true
	return s


## m:ss.t, e.g. 1:04.3 ("-:--.-" for INF).
static func format_time(seconds: float) -> String:
	if is_inf(seconds) or is_nan(seconds):
		return "-:--.-"
	var tenths := floori(seconds * 10.0)
	return "%d:%02d.%d" % [floori(tenths / 600.0), floori(tenths / 10.0) % 60, tenths % 10]


## Display name of the key (or mouse button) bound to `action`.
static func key_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_LEFT:
					return "LMB"
				_:
					return "MOUSE"
	return InteractionPrompt.action_key_text(action)
