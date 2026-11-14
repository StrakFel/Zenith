extends SceneTree
var _f := 0
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://Missions/Mission1/mission1.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var m := current_scene
	if m == null or _f < 5:
		return false
	if _f == 3:
		root.size = Vector2i(1280, 720)
	if _f == 5:
		m.dev_skip_briefing()
		m.dev_auto_design()
		for step in [["engine", "kestrel"], ["tank", "m"], ["nose", "aero"], ["upper", "u_s"]]:
			m.assembly._on_install(step[0], step[1])
		return false
	if _f == 40:
		var st := M1Parts.compute(m.assembly.build, m.assembly.payload_mass, m.assembly.sat_cost)
		print("disabled=", m.assembly._launch.disabled, " can=", M1Parts.can_launch(st), " twr=", st["twr"], " cost=", st["cost"], " complete=", st["complete"], " msgs=", M1Parts.readiness(st))
		print("btn visible=", m.assembly._launch.is_visible_in_tree(), " rect=", m.assembly._launch.get_global_rect(), " win=", root.size)
		quit()
	return false
