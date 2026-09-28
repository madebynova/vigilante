class_name PauseMenu
extends CanvasLayer
## Esc pauses the game: resume, restart the run, quit, with the controls
## beside them. F1 shows the same controls panel over the running game
## without pausing. Key names come from the Input Map, so they always match
## the bindings.

## Optional: "Restart run" restarts this mission (otherwise it respawns).
@export var mission: Mission
@export var player: Player

var paused := false

var _dim: ColorRect
var _menu: VBoxContainer
var _controls: PanelContainer
var _resume: Button
var _subtitle: Label


const GROUP := &"pause_menu"


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_build()
	_apply()


## The menu or the controls panel is on screen (other overlays step aside).
func is_open() -> bool:
	return paused or _controls.visible


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			set_paused(not paused)
			get_viewport().set_input_as_handled()
		KEY_F1:
			if not paused:
				_controls.visible = not _controls.visible
				get_viewport().set_input_as_handled()


func set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	_apply()
	if value:
		_resume.grab_focus()


func _apply() -> void:
	_dim.visible = paused
	_menu.visible = paused
	_controls.visible = paused
	if paused and mission != null:
		var best := mission.best_time()
		_subtitle.text = "%s  ·  best %s" % [mission.title, UiStyle.format_time(best)] if not is_inf(best) else mission.title
	elif paused:
		_subtitle.text = ""


func _on_restart() -> void:
	set_paused(false)
	if mission != null:
		mission.restart()
	elif player != null:
		player.respawn()


# --- Layout --------------------------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_menu.offset_left = 180.0
	_menu.offset_top = -220.0
	_menu.add_theme_constant_override(&"separation", 14)
	add_child(_menu)
	var title := UiStyle.label(72, UiStyle.TEXT, true, 12)
	title.text = "PAUSED"
	_menu.add_child(title)
	_subtitle = UiStyle.label(24, UiStyle.ACCENT, false, 6)
	_menu.add_child(_subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	_menu.add_child(gap)
	_resume = _button("RESUME", func() -> void: set_paused(false))
	_button("RESTART RUN" if mission != null else "RESPAWN", _on_restart)
	_button("QUIT", func() -> void: get_tree().quit())

	_controls = PanelContainer.new()
	_controls.add_theme_stylebox_override(&"panel", UiStyle.panel_style())
	_controls.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_controls.grow_vertical = Control.GROW_DIRECTION_BOTH
	_controls.offset_right = -140.0
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_controls)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_controls.add_child(column)
	var heading := UiStyle.label(26, UiStyle.ACCENT, true, 6)
	heading.text = "CONTROLS"
	column.add_child(heading)
	for group: Array in _control_groups():
		var group_title := UiStyle.label(18, UiStyle.DIM, true, 4)
		group_title.text = group[0]
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		column.add_child(spacer)
		column.add_child(group_title)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override(&"h_separation", 26)
		grid.add_theme_constant_override(&"v_separation", 4)
		column.add_child(grid)
		for row: Array in group[1]:
			var key := UiStyle.label(22, UiStyle.ACCENT, false, 5)
			key.text = row[0]
			key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			key.custom_minimum_size = Vector2(170, 0)
			var what := UiStyle.label(22, UiStyle.TEXT, false, 5)
			what.text = row[1]
			grid.add_child(key)
			grid.add_child(what)


func _button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = false
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 62)
	b.add_theme_font_override(&"font", UiStyle.title_font())
	b.add_theme_font_size_override(&"font_size", 30)
	b.add_theme_color_override(&"font_color", UiStyle.TEXT)
	b.add_theme_color_override(&"font_hover_color", UiStyle.ACCENT)
	b.add_theme_color_override(&"font_focus_color", UiStyle.ACCENT)
	b.add_theme_color_override(&"font_pressed_color", UiStyle.ACCENT)
	var normal := UiStyle.panel_style(Color(1, 1, 1, 0.0), 10)
	normal.content_margin_left = 22
	var hover := UiStyle.panel_style(Color(1, 1, 1, 0.08), 10)
	hover.content_margin_left = 22
	hover.border_width_left = 4
	hover.border_color = UiStyle.ACCENT
	for state: StringName in [&"normal", &"disabled"]:
		b.add_theme_stylebox_override(state, normal)
	for state: StringName in [&"hover", &"pressed", &"focus", &"hover_pressed"]:
		b.add_theme_stylebox_override(state, hover)
	b.pressed.connect(pressed)
	_menu.add_child(b)
	return b


## [group title, [[keys, what it does], ...]] with the current key bindings.
static func _control_groups() -> Array:
	var move := "%s %s %s %s" % [_keys(&"move_forward"), _keys(&"move_left"), _keys(&"move_back"), _keys(&"move_right")]
	return [
		["MOVE", [
			[move, "Move"],
			[_keys(&"sprint"), "Sprint"],
			[_keys(&"jump"), "Jump · wall-jump off a wall-run"],
			[_keys(&"crouch"), "Crouch · tap just before landing to roll"],
		]],
		["TRAVERSAL", [
			[_keys(&"jump"), "Vault · climb up from a ledge"],
			["Sprint + jump", "Wall-run along a tall wall"],
			[_keys(&"traverse"), "Dive through a window · grab a ladder"],
			[_keys(&"grapple"), "Grapple arrow at a glowing anchor (again: let go)"],
			[_keys(&"bullet_time"), "Slow time, in the air over a drop"],
		]],
		["GAME", [
			["ESC", "Pause"],
			[_keys(&"debug_respawn"), "Restart the run"],
			["F1", "Show / hide controls"],
			["F3", "Debug readout  ·  1-5 districts  ·  N day / night"],
		]],
	]


## Every key (or mouse button) bound to `action`, first-letter keys only
## where arrows duplicate them (W, not W / UP).
static func _keys(action: StringName) -> String:
	var names: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		var key_name := ""
		if event is InputEventMouseButton:
			key_name = UiStyle.key_text(action)
		elif event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			if code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
				continue
			key_name = OS.get_keycode_string(code).to_upper()
		if key_name != "" and not names.has(key_name):
			names.append(key_name)
	return " / ".join(names) if not names.is_empty() else String(action).to_upper()
