extends SceneTree
## Developer tool: opens a scene, lets it run for N frames, optionally calls
## hook methods on the current scene, and saves a screenshot.
##   Godot --path . --script res://Tools/shot.gd -- res://Menus/TempMenu/temp_main_menu.tscn out.png 90 [locale] [hook,hook,...]
## A hook is "method" or "method:arg" (arg is passed as a string) and runs on the
## first frame after the scene is up. Used for visual checks - not part of the game.

var _scene := ""
var _out := ""
var _frames := 60
var _hooks: Array = []
var _locale := ""
var _i := 0
var _started := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_scene = a[0]
	_out = a[1]
	_frames = int(a[2]) if a.size() > 2 else 60
	if a.size() > 3 and a[3] != "":
		_locale = a[3]
	if a.size() > 4 and a[4] != "":
		_hooks = a[4].split(",")
	if OS.get_environment("ZENITH_SCALE") != "":
		var sp := OS.get_environment("ZENITH_SCALE").split("x")
		root.content_scale_size = Vector2i(int(sp[0]), int(sp[1]))   # simulate a smaller layout space
	if OS.get_environment("ZENITH_VIEW_ALT") != "":
		ProjectSettings.set_setting("zenith/view_alt", float(OS.get_environment("ZENITH_VIEW_ALT")))
		ProjectSettings.set_setting("zenith/view_down", float(OS.get_environment("ZENITH_VIEW_DOWN")))
	change_scene_to_file(_scene)


func _process(_d: float) -> bool:
	_i += 1
	if not _started and current_scene != null and _i > 3:
		_started = true
		if _locale != "":
			# switched AFTER the scene exists: proves instant re-translation (not saved to disk)
			var gs := root.get_node("GameState")
			gs.settings["locale"] = _locale
			gs.apply_settings()
		for h in _hooks:
			var parts: PackedStringArray = str(h).split(":")
			var cs := current_scene
			if parts.size() > 1:
				cs.call(parts[0], parts[1])
			else:
				cs.call(parts[0])
	if _i >= _frames:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("SHOT_SAVED ", _out, " ", img.get_size(), " fps=", Engine.get_frames_per_second())
		quit()
	return false

