extends SceneTree
## Visual check of the stage separation: flies a two-stage rocket with the test autopilot (real renderer needed) and
## saves screenshots around the separation moment.  Godot --path . --resolution 1280x720 --script res://Tools/shot_stage.gd -- outdir
var _dir := "."
var _f := 0
var _m: Node
var _t_sep := -1
var _shots := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_dir = a[0]
	Engine.time_scale = 4.0
	change_scene_to_file("res://Missions/Mission1/mission1.tscn")

func _process(_d: float) -> bool:
	_f += 1
	if current_scene == null or _f < 5:
		return false
	_m = current_scene
	if _f == 5:
		_m.dev_quick("kestrel/m/aero/u_s")
		_m.dev_autopilot = true
		_m.flight.skip_intro()
		return false
	if _m.model != null and _m.model.stage == 2 and _t_sep < 0:
		_t_sep = _f
	if _t_sep >= 0:
		var k := _f - _t_sep
		for mark in [4, 22, 50, 90]:
			if k == mark:
				var img := root.get_viewport().get_texture().get_image()
				img.save_png("%s/stage_%d.png" % [_dir, mark])
				print("SHOT ", mark)
				_shots += 1
		if _shots >= 4:
			quit()
	if _f > 40000:
		print("TIMEOUT")
		quit(1)
	return false
