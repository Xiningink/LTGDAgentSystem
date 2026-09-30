## Screen router + runtime input map + screenshot scenario support.
extends Control

var _title: TitleScreen
var _index: LevelSelectScreen
var _gameplay: GameplayScreen
var _help: HelpScreen
var _fade: ColorRect
var _current: Control
var instant_mode: bool = false


func _ready() -> void:
	theme = UIKit.theme()
	_setup_input()
	_build_screens()
	_build_fade()
	show_title()
	_apply_scenario()


func _setup_input() -> void:
	_add_action("pm_up", [KEY_W, KEY_UP])
	_add_action("pm_down", [KEY_S, KEY_DOWN])
	_add_action("pm_left", [KEY_A, KEY_LEFT])
	_add_action("pm_right", [KEY_D, KEY_RIGHT])
	_add_action("pm_undo", [KEY_Z, KEY_BACKSPACE])
	_add_action("pm_reset", [KEY_R])
	_add_action("pm_menu", [KEY_ESCAPE])
	_add_action("pm_help", [KEY_H])
	_add_action("pm_accept", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


## Screens are composed in code so startup is deterministic and the paired
## scenes in scenes/*.tscn stay usable on their own (see README).
func _build_screens() -> void:
	_title = TitleScreen.new()
	_title.name = "TitleScreen"
	add_child(_title)
	_title.start_game.connect(play_level)
	_title.open_index.connect(show_index)
	_title.open_help.connect(show_help)
	_title.quit_game.connect(func(): get_tree().quit())

	_index = LevelSelectScreen.new()
	_index.name = "LevelSelectScreen"
	add_child(_index)
	_index.select_level.connect(play_level)
	_index.back.connect(show_title)

	_gameplay = GameplayScreen.new()
	_gameplay.name = "GameplayScreen"
	add_child(_gameplay)
	_gameplay.request_index.connect(show_index)
	_gameplay.request_level.connect(play_level)

	_help = HelpScreen.new()
	_help.name = "HelpScreen"
	add_child(_help)
	_help.back.connect(show_title)

	_show(_title)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.02, 0.03, 0.05, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	add_child(_fade)


func _show(screen: Control) -> void:
	for child in [_title, _index, _gameplay, _help]:
		child.visible = false
	screen.visible = true
	_current = screen
	if screen == _index:
		_index.rebuild()


func _transition(screen: Control) -> void:
	if instant_mode:
		_fade.visible = false
		_show(screen)
		return
	if _current == screen:
		_show(screen)
		return
	_fade.visible = true
	_fade.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.13)
	tw.tween_callback(func(): _show(screen))
	tw.tween_property(_fade, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func(): _fade.visible = false)


func show_title() -> void:
	_transition(_title)
	Sfx.music("hum", -26.0)


func show_index() -> void:
	_transition(_index)


func show_help() -> void:
	_transition(_help)


func play_level(index: int) -> void:
	_transition(_gameplay)
	_gameplay.open_level(index)


func _exit_tree() -> void:
	UIKit.release()


# --- screenshot / QA scenarios ----------------------------------------------

func _apply_scenario() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario := ""
	var level_override := -1
	var i := 0
	while i < args.size():
		var arg: String = args[i]
		if arg.begins_with("--scenario="):
			scenario = arg.split("=", true, 1)[1]
		elif arg == "--scenario" and i + 1 < args.size():
			scenario = args[i + 1]
			i += 1
		elif arg.begins_with("--level="):
			level_override = int(arg.split("=", true, 1)[1])
		elif arg == "--level" and i + 1 < args.size():
			level_override = int(args[i + 1])
			i += 1
		i += 1
	if scenario.is_empty() and level_override < 0:
		return
	# Capture mode: cut straight to the requested state so the frame we save is
	# never caught mid-fade.
	instant_mode = true
	# Let the container layout settle so board effects land on real pixels.
	await get_tree().process_frame
	await get_tree().process_frame
	match scenario:
		"title":
			show_title()
		"levels", "index":
			show_index()
		"help", "rules":
			show_help()
		"play":
			play_level(0)
		"victory", "solved":
			play_level(0)
			_gameplay.debug_win()
		"near_victory", "nearly":
			play_level(0)
			_gameplay.debug_near_victory()
		"mid":
			play_level(8)
			_gameplay.debug_walk("RRRD")
		"burn":
			play_level(4)
			_gameplay.debug_burn()
		"cascade":
			play_level(6)
			_gameplay.debug_cascade()
		"final":
			play_level(Levels.count() - 1)
		"hazard":
			play_level(1)
		_:
			if scenario.begins_with("level_"):
				play_level(int(scenario.substr(6)) - 1)
	if level_override >= 0:
		play_level(level_override - 1)
