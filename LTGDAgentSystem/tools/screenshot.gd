extends SceneTree

# Run with a real display driver. Headless mode has no viewport texture.
const DEFAULT_FRAMES := 30


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var out_path: String = args.get("out", "")
	if out_path.is_empty():
		push_error("screenshot.gd: --out <path> is required")
		quit(2)
		return

	var frames: int = int(args.get("frames", DEFAULT_FRAMES))
	if frames < 1:
		push_error("screenshot.gd: --frames must be positive")
		quit(2)
		return

	var scene_path: String = args.get(
		"scene", ProjectSettings.get_setting("application/run/main_scene", "")
	)
	if scene_path.is_empty():
		push_error("screenshot.gd: no scene specified and project has no main scene")
		quit(2)
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("screenshot.gd: failed to load scene %s" % scene_path)
		quit(3)
		return

	root.add_child(packed.instantiate())
	for _i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("screenshot.gd: viewport returned no image")
		quit(4)
		return

	var err: int = image.save_png(out_path)
	if err != OK:
		push_error("screenshot.gd: save_png returned %d for %s" % [err, out_path])
		quit(5)
		return

	print("screenshot saved: %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit(0)


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		var arg: String = argv[i]
		if not arg.begins_with("--"):
			i += 1
			continue
		var key: String = arg.substr(2)
		var value: String = "true"
		if "=" in key:
			var parts: PackedStringArray = key.split("=", true, 1)
			key = parts[0]
			value = parts[1]
		elif i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
			value = argv[i + 1]
			i += 1
		out[key] = value
		i += 1
	return out
