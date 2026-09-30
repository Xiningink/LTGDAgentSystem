## Loads and indexes the chamber manifest (res://assets/levels.json).
class_name Levels
extends RefCounted

const PATH := "res://assets/levels.json"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		if text.is_empty():
			push_error("Levels: cannot read %s" % PATH)
			return {"chapters": [], "levels": []}
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Levels: malformed JSON in %s" % PATH)
			return {"chapters": [], "levels": []}
		_cache = parsed
	return _cache


static func chapters() -> Array:
	return data().get("chapters", [])


static func levels() -> Array:
	return data().get("levels", [])


static func count() -> int:
	return levels().size()


static func level_at(index: int) -> Dictionary:
	var list := levels()
	if index < 0 or index >= list.size():
		return {}
	return list[index]


static func index_of_id(id: String) -> int:
	var list := levels()
	for i in range(list.size()):
		if String(list[i].get("id", "")) == id:
			return i
	return -1


static func chapter_of(level: Dictionary) -> Dictionary:
	var list := chapters()
	var idx := int(level.get("chapter", 0))
	if idx < 0 or idx >= list.size():
		return {"name": "CHAMBER", "code": "?", "color": "#49e0d0", "blurb": ""}
	return list[idx]


static func chapter_index(level: Dictionary) -> int:
	return int(level.get("chapter", 0))


static func chapter_color(level: Dictionary) -> Color:
	var chapter := chapter_of(level)
	return Color(String(chapter.get("color", "#49e0d0")))
