## Animated laboratory backdrop: gradient, drifting grid, motes and a soft
## scan sweep. Cheap enough to sit under every screen.
class_name Backdrop
extends ColorRect

var _drift: float = 0.0
var _motes: Array = []
var _t: float = 0.0
var _energy: float = 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists("res://assets/shaders/backdrop.gdshader"):
		mat.shader = load("res://assets/shaders/backdrop.gdshader")
	material = mat
	_seed_motes()


func _seed_motes() -> void:
	_motes.clear()
	for i in range(70):
		_motes.append({
			"pos": Vector2(randf(), randf()),
			"vel": Vector2(randf_range(-0.006, 0.006), randf_range(-0.02, -0.004)),
			"size": randf_range(0.8, 2.4),
			"phase": randf() * TAU,
			"alpha": randf_range(0.15, 0.5),
		})


func set_energy(value: float) -> void:
	_energy = clampf(value, 0.0, 1.0)
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("glow_amount", 0.6 + 0.6 * _energy)


func _process(delta: float) -> void:
	_t += delta
	_drift += delta * (0.06 + _energy * 0.2)
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("drift", _drift)
	for mote in _motes:
		mote["pos"] += mote["vel"] * delta
		if mote["pos"].y < -0.05:
			mote["pos"].y = 1.05
			mote["pos"].x = randf()
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 4.0 or s.y < 4.0:
		return
	# rising energy motes
	for mote in _motes:
		var p: Vector2 = mote["pos"]
		var wobble := sin(_t * 1.2 + mote["phase"]) * 8.0
		var pos := Vector2(p.x * s.x + wobble, p.y * s.y)
		var a: float = mote["alpha"] * (0.5 + 0.5 * sin(_t * 2.0 + mote["phase"]))
		var c := Palette.SWITCH if int(mote["size"] * 10.0) % 2 == 0 else Palette.GOLD
		draw_circle(pos, mote["size"], Color(c.r, c.g, c.b, a))
	# sweeping scan bar
	var sweep := fmod(_t * 0.08, 1.4) - 0.2
	var bar_y := sweep * s.y
	var grad := 120.0
	for i in range(6):
		var a := (1.0 - float(i) / 6.0) * 0.03
		draw_rect(Rect2(0, bar_y - i * grad * 0.3, s.x, grad * 0.3), Color(0.35, 0.9, 0.95, a))
