extends Control
## Transcript / log panel. Types out the locked signal and keeps a chip list of
## every carrier recovered so far.

var selected := -1
var _text: RichTextLabel
var _typing := false
var _chars := 0.0
var _speed := 46.0
var _tick_accum := 0.0
var _t := 0.0
var _chips: Array = []
var _empty_hint := true
var draw_chip_count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("normal_font", UIKit.font_mono())
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_constant_override("line_separation", 5)
	_text.add_theme_color_override("default_color", Palette.TEXT)
	add_child(_text)
	resized.connect(_layout)
	_layout()
	_show_placeholder()


func _layout() -> void:
	if _text == null:
		return
	_text.position = Vector2(16.0, 62.0)
	_text.size = Vector2(size.x - 32.0, size.y - 62.0 - 44.0)


func _show_placeholder() -> void:
	_empty_hint = true
	_text.text = "[color=#4b6a60]NO CARRIER SELECTED.\n\nTUNE THE RECEIVER TO PULL A DISTRESS SIGNAL OUT OF THE STATIC.\nEACH LOCKED SIGNAL LOGS A COORDINATE.\nPLOT THREE COORDINATES ON THE CHART TO TRIANGULATE A SOURCE.[/color]"
	_text.visible_characters = -1
	_typing = false


func show_signal(index: int) -> void:
	selected = index
	_empty_hint = false
	var s: Dictionary = SignalDB.signals[index]
	var tone := String(s.get("tone", "voice"))
	var name_col := "#74f7b4"
	if tone == "entity":
		name_col = "#ff8a94"
	elif tone == "machine":
		name_col = "#66dcff"
	elif tone == "self":
		name_col = "#ffb454"
	var bb := "[color=%s]%s[/color]\n" % [name_col, String(s["caller"])]
	bb += "[color=#4b6a60]%s[/color]\n\n" % String(s["tag"])
	for line in s["lines"]:
		var col := "#cfe9dc"
		if tone == "entity":
			col = "#e6a6ac"
		bb += "[color=%s]%s[/color]\n" % [col, String(line)]
	bb += "\n[color=#ffb454]>> POSITION  %s  /  %s[/color]" % [SignalDB.format_lat(s["lat"]), SignalDB.format_lon(s["lon"])]
	_text.text = bb
	_chars = 0.0
	_text.visible_characters = 0
	_typing = true
	_tick_accum = 0.0


func skip_typing() -> void:
	if _typing:
		_typing = false
		_text.visible_characters = -1


func _process(delta: float) -> void:
	_t += delta
	if _typing:
		_chars += _speed * delta
		_text.visible_characters = int(_chars)
		_tick_accum += delta
		if _tick_accum > 0.045:
			_tick_accum = 0.0
			Audio.play("tick_002.ogg", -30.0, randf_range(1.4, 1.9))
		if int(_chars) >= _text.get_total_character_count():
			_typing = false
			_text.visible_characters = -1
	queue_redraw()


func _chip_rects() -> Array:
	_chips = []
	var y := size.y - 40.0
	var x := 16.0
	var w := 104.0
	var gap := 6.0
	for i in GameState.discovered:
		if int(SignalDB.signals[i]["chapter"]) != GameState.chapter:
			continue
		var r := Rect2(x, y, w, 30.0)
		_chips.append({"rect": r, "index": i})
		x += w + gap
		if x + w > size.x - 16.0:
			break
	draw_chip_count = GameState.discovered.size()
	return _chips


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		for c in _chip_rects():
			if (c["rect"] as Rect2).has_point(p):
				show_signal(c["index"])
				Audio.play("select_005.ogg", -12.0)
				return
		skip_typing()


func _draw() -> void:
	draw_style_box(UIKit.panel_box(Color(0.10, 0.17, 0.19)), Rect2(Vector2.ZERO, size))
	UIKit.draw_bar(self, Rect2(14, 10, size.x - 28, 26), Color(0.85, 0.9, 0.85, 0.9))
	UIKit.text(self, Vector2(24, 30), "RECEIVER LOG", 15, Color(0.82, 0.95, 0.88, 0.9))
	if selected >= 0:
		UIKit.text_right(self, Vector2(size.x - 24, 30), String(SignalDB.signals[selected]["caller"]), 14, Color(0.7, 0.95, 0.85, 0.85))

	# Coordinate strip.
	var strip := Rect2(14, 42, size.x - 28, 20)
	draw_rect(strip, Color(0.08, 0.14, 0.14))
	if selected >= 0:
		var pinned := GameState.has_pin(selected)
		var st := "PINNED" if pinned else "AWAITING PLOT"
		var st_col := Color("74f7b4") if pinned else Color("ffb454")
		UIKit.text(self, strip.position + Vector2(8, 15), "COORD  %s  /  %s" % [SignalDB.format_lat(SignalDB.signals[selected]["lat"]), SignalDB.format_lon(SignalDB.signals[selected]["lon"])], 14, Color("ffb454"))
		UIKit.text_right(self, Vector2(strip.end.x - 8, strip.position.y + 15), st, 13, st_col)
	else:
		UIKit.text(self, strip.position + Vector2(8, 15), "COORD  --  /  --", 14, Color(0.35, 0.5, 0.45))

	# Log chips.
	for c in _chip_rects():
		var r: Rect2 = c["rect"]
		var i: int = c["index"]
		var s: Dictionary = SignalDB.signals[i]
		var is_sel := i == selected
		var col: Color = [Color("ffb454"), Color("66dcff"), Color("74f7b4"), Color("ff4f5e")][clampi(int(s["chapter"]) - 1, 0, 3)]
		draw_rect(r, Color(col.r * 0.14, col.g * 0.14, col.b * 0.14, 1.0))
		draw_rect(r, col if is_sel else Color(0.22, 0.34, 0.32), false, 2.0 if is_sel else 1.0)
		UIKit.text(self, r.position + Vector2(7, 14), "SIG %02d" % (i + 1), 13, col)
		UIKit.text(self, r.position + Vector2(7, 26), String(s["caller"]).substr(0, 12), 10, Color(0.55, 0.72, 0.66))
		if GameState.has_pin(i):
			draw_circle(r.end - Vector2(9, 9), 3.0, Color("74f7b4"))

	UIKit.text_right(self, Vector2(size.x - 24, size.y - 10), "LOG  %d  CARRIERS   /   CLICK A CHIP TO RE-READ" % draw_chip_count, 11, Color(0.35, 0.52, 0.46))
	draw_rect(Rect2(Vector2.ZERO, size), Color("152a2a"), false, 3.0)
