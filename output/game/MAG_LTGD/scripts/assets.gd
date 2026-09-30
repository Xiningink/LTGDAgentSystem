extends RefCounted
class_name Assets

## Central asset access with runtime fallbacks: if the import pipeline has not
## produced a .ctex for a file yet, the raw PNG/OGG/TTF is loaded directly.

const DIR_SPRITES := "res://assets/sprites/"
const DIR_UI := "res://assets/ui/"
const DIR_DECO := "res://assets/deco/"
const DIR_FONTS := "res://assets/fonts/"
const DIR_SFX := "res://assets/sfx/"
const DIR_PARTICLES := "res://assets/particles/"

# tiles
const FLOOR_A := DIR_SPRITES + "floor_a.png"
const FLOOR_B := DIR_SPRITES + "floor_b.png"
const WALL_B := DIR_SPRITES + "wall_b.png"
const CRATE := DIR_SPRITES + "crate_base.png"

# ui 9-slices
const UI_PANEL := DIR_UI + "panel.png"
const UI_BUTTON := DIR_UI + "button.png"
const UI_BUTTON_DEPTH := DIR_UI + "button_depth.png"

# decoration
const DECO := [
	DIR_DECO + "lab_01.png",
	DIR_DECO + "lab_02.png",
	DIR_DECO + "lab_03.png",
	DIR_DECO + "lab_04.png",
	DIR_DECO + "lab_05.png",
	DIR_DECO + "lab_06.png",
]

# particles
const P_FLARE := DIR_PARTICLES + "flare.png"
const P_SPARK := DIR_PARTICLES + "spark.png"
const P_SMOKE := DIR_PARTICLES + "smoke.png"

# fonts
const FONT_TITLE := DIR_FONTS + "title.ttf"
const FONT_HUD := DIR_FONTS + "hud.ttf"

static var _textures := {}
static var _fonts := {}
static var _streams := {}
static var _fallback: Texture2D = null


static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var result: Texture2D = null
	var res: Variant = ResourceLoader.load(path)
	if res is Texture2D:
		result = res
	if result == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			result = ImageTexture.create_from_image(img)
	if result == null:
		result = _fallback_texture()
		push_warning("Assets: missing texture %s" % path)
	_textures[path] = result
	return result


static func _fallback_texture() -> Texture2D:
	if _fallback != null:
		return _fallback
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.2, 0.7, 1.0))
	_fallback = ImageTexture.create_from_image(img)
	return _fallback


static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var result: Font = null
	var ff := FontFile.new()
	if ff.load_dynamic_font(path) == OK:
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		result = ff
	else:
		var res: Variant = ResourceLoader.load(path)
		if res is Font:
			result = res
	if result == null:
		result = ThemeDB.fallback_font
		push_warning("Assets: missing font %s" % path)
	_fonts[path] = result
	return result


static func stream(name: String) -> AudioStream:
	var path := DIR_SFX + name + ".ogg"
	if _streams.has(path):
		return _streams[path]
	var result: AudioStream = null
	var res: Variant = ResourceLoader.load(path)
	if res is AudioStream:
		result = res
	if result == null and FileAccess.file_exists(path):
		result = AudioStreamOggVorbis.load_from_file(path)
	_streams[path] = result
	return result


## Releases cached audio resources so a mid-jingle exit leaves nothing behind.
static func clear_stream_cache() -> void:
	_streams.clear()
