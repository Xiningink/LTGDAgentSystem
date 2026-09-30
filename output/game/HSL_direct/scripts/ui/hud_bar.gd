extends Control
## Top status bar: station identity, objective, battery, presence, cells.

signal cell_pressed()
signal mute_pressed()

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _regions() -> Dictionary:
	var right := size.x - 16.0
	var mute := Rect2(right - 36.0, 10.0, 36.0, 34.0)
	right -= 46.0
	var cell := Rect2(right - 116.0, 10.0, 116.0, 34.0)
	right -= 128.0
	var pres := Rect2(right - 150.0, 24.0, 150.0, 14.0)
	right -= 162.0
	var bat := Rect2(right - 170.0, 24.0, 170.0, 14.0)
	return {"mute": mute, "cell": cell, "pres": pres, "bat": bat}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		var r := _regions()
		if (r["cell"] as Rect2).has_point(p):
			cell_pressed.emit()
		elif (r["mute"] as Rect2).has_point(p):
			mute_pressed.emit()


func _draw() -> void:
	var w := size.x
	draw_rect(Rect2(0, 0, w, size.y), Color("081113"))
	draw_rect(Rect2(0, size.y - 2.0, w, 2.0), Color(0.22, 0.42, 0.38, 0.8))

	# Identity.
	UIKit.text(self, Vector2(18, 24), "STATION K-7", 21, Color(0.72, 1.0, 0.85, 0.95))
	UIKit.text(self, Vector2(18, 42), "BARENTS COAST RELAY", 11, Color(0.45, 0.68, 0.6, 0.8))
	UIKit.text(self, Vector2(230, 24), GameState.clock_text(), 20, Color(0.6, 0.9, 0.8, 0.9))
	UIKit.text(self, Vector2(230, 42), "LOCAL TIME", 11, Color(0.4, 0.6, 0.55, 0.7))

	# Objective.
	var obj := GameState.objective_text()
	UIKit.text(self, Vector2(392, 22), obj, 14, Color(0.85, 0.78, 0.5, 0.95))
	var prog := "%d SIGNALS  /  %d PINS" % [GameState.discovered.size(), GameState.pins.size()]
	UIKit.text(self, Vector2(392, 40), prog, 12, Color(0.5, 0.72, 0.64, 0.8))

	var r := _regions()

	# Battery.
	var bat: Rect2 = r["bat"]
	_draw_gauge(bat, GameState.battery / 100.0, _battery_color(), "POWER", "%d%%" % int(ceil(GameState.battery)))
	# Presence.
	var pres: Rect2 = r["pres"]
	_draw_gauge(pres, GameState.presence / 100.0, _presence_color(), "INTERFERENCE", "%d%%" % int(GameState.presence))

	# Cells button.
	var cell: Rect2 = r["cell"]
	var has: bool = GameState.cells > 0
	var enabled: bool = has and not GameState.ended
	var col := Color("ffb454") if enabled else Color(0.3, 0.36, 0.34)
	draw_rect(cell, Color(col.r * 0.16, col.g * 0.16, col.b * 0.16, 1.0))
	draw_rect(cell, col, false, 2.0)
	var t := UIKit.tex("res://assets/icons/power.png")
	draw_texture_rect(t, Rect2(cell.position + Vector2(8, 6), Vector2(22, 22)), false, col)
	UIKit.text(self, cell.position + Vector2(36, 24), "CELL  x%d" % GameState.cells, 15, col)

	# Mute.
	var mute: Rect2 = r["mute"]
	var muted := Audio.is_muted()
	var mcol := Color(0.35, 0.5, 0.45) if muted else Color(0.6, 0.9, 0.8)
	draw_rect(mute, Color("0b1416"))
	draw_rect(mute, mcol, false, 2.0)
	var it := UIKit.tex("res://assets/icons/audioOff.png" if muted else "res://assets/icons/audioOn.png")
	draw_texture_rect(it, Rect2(mute.position + Vector2(7, 7), Vector2(22, 22)), false, mcol)


func _battery_color() -> Color:
	if GameState.battery > 55.0:
		return Color("74f7b4")
	if GameState.battery > 25.0:
		return Color("ffb454")
	return Color("ff4f5e")


func _presence_color() -> Color:
	var p := GameState.presence
	if p > 66.0:
		return Color("ff4f5e")
	if p > 33.0:
		return Color("ff8a4f")
	return Color("7f5fd8")


func _draw_gauge(rect: Rect2, ratio: float, col: Color, label: String, value: String) -> void:
	UIKit.text(self, Vector2(rect.position.x, rect.position.y - 6.0), label, 12, Color(0.5, 0.72, 0.64, 0.85))
	UIKit.text_right(self, Vector2(rect.end.x, rect.position.y - 6.0), value, 13, col)
	draw_rect(rect, Color("0a1315"))
	var seg := 20
	var gap := 2.0
	var sw := (rect.size.x - gap * float(seg - 1)) / float(seg)
	var lit := int(ceil(ratio * float(seg)))
	for i in seg:
		var x := rect.position.x + float(i) * (sw + gap)
		var on := i < lit
		var c: Color = col if on else Color(0.12, 0.18, 0.17)
		draw_rect(Rect2(x, rect.position.y, sw, rect.size.y), c)
	draw_rect(rect, Color(0.28, 0.42, 0.38, 0.7), false, 1.0)
