extends SceneTree
## End-to-end test of mission 1 through the real scene (assembly -> countdown ->
## autopilot flight -> deploy -> result screen -> saved progress).
##   Godot --headless --path . --script res://Tools/e2e_m1.gd -- kestrel/l/aero [scale]

var _frames := 0
var _scene_started := false
var _launched := false
var _spec := "kestrel/l/aero"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_spec = a[0]
	Engine.time_scale = float(a[1]) if a.size() > 1 else 6.0
	var gs := root.get_node("GameState")
	gs.progress.clear()
	change_scene_to_file("res://Missions/Mission1/mission1.tscn")


func _process(_d: float) -> bool:
	_frames += 1
	var m := current_scene
	if m == null or _frames < 5:
		return false
	if not _scene_started:
		_scene_started = true
		m.dev_skip_briefing()
		m.dev_auto_design()
		return false
	if not _launched:
		_launched = true
		var p := _spec.split("/")
		m._on_launch({"engine": p[0], "tank": p[1], "nose": p[2], "upper": p[3] if p.size() > 3 else ""})
		m.dev_autopilot = true
		return false
	for c in m.overlay.get_children():
		if c.has_method("show_result"):
			var gs := root.get_node("GameState")
			print("RESULT_SCREEN shown. state=", m.state, " progress=", gs.progress)
			if m.model != null:
				print("stage=", m.model.stage, " sep_waste=", snappedf(m.model.sep_waste, 0.01), " dead_t=", snappedf(m.model.dead_mass_time, 0.1),
					" fairing_on=", m.model.fairing_on, " early=", m.model.fairing_early, " rel=", snappedf(float(m.stats["rel"]), 0.01),
					" dv=", int(m.stats["dv"]), " twr=", snappedf(float(m.stats["twr"]), 0.01), " cost=", m.stats["cost"])
				print("flight time=", int(m.model.time), "s fuel=", snappedf(m.model.fuel_fraction(), 0.01),
					" integrity=", int(m.model.integrity))
			quit(0)
			return true
	if _frames > 60000:
		print("TIMEOUT state=", m.state, " alt=", m.model.altitude() if m.model else -1)
		quit(1)
	return false


