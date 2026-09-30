extends Control
# End of watch card. Two outcomes: the station answered, or the dark arrived.

signal restart_requested
signal title_requested

const ENDINGS := {
	"signal_lost": {
		"kicker": "END OF WATCH",
		"title": "SIGNAL LOST",
		"tint": Color(0.95, 0.32, 0.24),
		"body": [
			"FIVE BEARINGS. ONE ORIGIN.",
			"THE TRIANGULATION RESOLVED TO 52.0 N / 18.0 W.",
			"YOUR OWN DESK.",
			"",
			"THE INTERFERENCE WAS NEVER JAMMING YOU.",
			"IT WAS ANSWERING.",
			"",
			"THE DOOR OPENS ON ITS OWN. THE LAMPS GO DOWN ONE BY ONE.",
			"THE BAND IS QUIET NOW.",
			"NO CARRIER."
		]
	},
	"dark": {
		"kicker": "END OF WATCH",
		"title": "THE DARK TOOK YOU",
		"tint": Color(0.80, 0.20, 0.18),
		"body": [
			"THE CELL BANK DIED.",
			"THE LAMPS WENT WITH IT.",
			"",
			"IN THE DARK, SOMETHING CROSSED THE ROOM.",
			"IT DID NOT NEED THE WINDOW.",
			"IT HAD THE KNOB. IT HAD THE WHOLE TIME.",
			"",
			"THE LAST THING YOU HEARD WAS YOUR OWN",
			"DISTRESS CALL, PLAYED BACK A HEARTBEAT LATE.",
			"",
			"NO CARRIER."
		]
	}
}

var kind := "signal_lost"
var stats: Dictionary = {}

var _title: Label
var _kicker: Label
var _body: RichTextLabel
var _stats_label: Label
var _reveal := 0.0
var _shown := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _static: ColorRect
var _entity: Control


func _ready() -> void:
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_PASS
	var font_ui: Font = load("res://assets/fonts/KenneyFutureNarrow.ttf")
	var font_mono: Font = load("res://assets/fonts/KenneyMiniSquareMono.ttf")

	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.010, 0.013)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_entity = load("res://scripts/EntitySilhouette.gd").new()
	_entity.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_entity)

	_static = ColorRect.new()
	_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/radio_scope.gdshader")
	mat.set_shader_parameter("noise_strength", 0.11)
	mat.set_shader_parameter("signal_strength", 0.0)
	mat.set_shader_parameter("jam_level", 0.08)
	mat.set_shader_parameter("glow", Color(0.30, 0.46, 0.40))
	mat.set_shader_parameter("base_color", Color(0.002, 0.004, 0.005))
	_static.material = mat
	add_child(_static)

	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.026, 0.030, 0.72)
	panel.position = Vector2(200, 96)
	panel.size = Vector2(880, 528)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_kicker = Label.new()
	_kicker.add_theme_font_override("font", font_mono)
	_kicker.add_theme_font_size_override("font_size", 14)
	_kicker.add_theme_color_override("font_color", Color(0.46, 0.62, 0.58))
	_kicker.position = Vector2(240, 122)
	_kicker.text = "END OF WATCH"
	add_child(_kicker)

	_title = Label.new()
	_title.add_theme_font_override("font", font_ui)
	_title.add_theme_font_size_override("font_size", 58)
	_title.add_theme_color_override("font_color", Color(0.94, 0.91, 0.86))
	_title.position = Vector2(240, 144)
	_title.size = Vector2(820, 70)
	add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.add_theme_font_override("normal_font", font_mono)
	_body.add_theme_font_size_override("normal_font_size", 16)
	_body.add_theme_color_override("default_color", Color(0.78, 0.88, 0.84))
	_body.position = Vector2(240, 224)
	_body.size = Vector2(500, 300)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	_stats_label = Label.new()
	_stats_label.add_theme_font_override("font", font_mono)
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.add_theme_color_override("font_color", Color(0.55, 0.74, 0.68))
	_stats_label.position = Vector2(760, 224)
	_stats_label.size = Vector2(280, 220)
	add_child(_stats_label)

	var restart := _make_button("REBROADCAST", font_ui)
	restart.position = Vector2(240, 546)
	restart.size = Vector2(200, 46)
	restart.pressed.connect(func() -> void: restart_requested.emit())
	add_child(restart)

	var to_title := _make_button("RETURN TO TITLE", font_ui)
	to_title.position = Vector2(456, 546)
	to_title.size = Vector2(220, 46)
	to_title.pressed.connect(func() -> void: title_requested.emit())
	add_child(to_title)


func _make_button(text: String, font: Font) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(0.86, 0.90, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.52))
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.075, 0.095, 0.10), Color(0.26, 0.40, 0.36)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.13, 0.17, 0.17), Color(0.55, 0.92, 0.62)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.05, 0.07, 0.07), Color(0.85, 0.5, 0.3)))
	b.focus_mode = Control.FOCUS_NONE
	return b


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	return sb


func show_ending(kind_id: String, run_stats: Dictionary) -> void:
	kind = kind_id if ENDINGS.has(kind_id) else "signal_lost"
	stats = run_stats
	var data: Dictionary = ENDINGS[kind]
	_title.text = str(data["title"])
	_title.add_theme_color_override("font_color", data["tint"])
	_kicker.text = "%s  //  %s" % [str(data["kicker"]), str(stats.get("outcome_code", "----"))]
	_body.text = "[color=#82a89e]%s[/color]" % "\n".join(PackedStringArray(data["body"]))
	_body.visible_characters = 0
	_reveal = 0.0
	_shown = 0.0
	_stats_label.text = "SIGNALS TRIANGULATED   %d / 5\nBEARINGS LOGGED        %d\nCACHES RECOVERED       %d\nCELL RESERVE           %d%%\nTIME ON WATCH          %s\nINTERFERENCE PEAK      %d%%\n\n%s" % [
		int(stats.get("signals", 0)),
		int(stats.get("pins", 0)),
		int(stats.get("caches", 0)),
		int(stats.get("battery", 0)),
		str(stats.get("time", "00:00")),
		int(stats.get("corruption", 0)),
		str(stats.get("note", ""))
	]
	_entity.set("mode", kind)
	start_reveal()


func start_reveal() -> void:
	_reveal = 0.0


func finish_reveal() -> void:
	_reveal = 1.0
	if _body != null:
		_body.visible_characters = -1


func fx_state() -> Dictionary:
	return {
		"glitch": 0.05 + 0.08 * _rng.randf() * (1.0 - minf(_reveal, 1.0)) + 0.015,
		"corruption": 0.25,
		"tint": Color(0.97, 1.0, 0.98),
		"brightness": 1.0
	}


func _process(delta: float) -> void:
	_t += delta
	_reveal = minf(1.0, _reveal + delta * 0.22)
	if _body != null:
		var total := _body.get_total_character_count()
		_shown = minf(float(total), float(total) * _reveal / 0.85)
		_body.visible_characters = int(_shown)
	if _static != null:
		var m: ShaderMaterial = _static.material
		m.set_shader_parameter("noise_strength", 0.09 + 0.07 * absf(sin(_t * 1.9)))


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_R or ke.keycode == KEY_SPACE or ke.keycode == KEY_ENTER:
				restart_requested.emit()
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ESCAPE:
				title_requested.emit()
				get_viewport().set_input_as_handled()
