extends SceneTree
## End-to-end test of mission 2 (lunar expedition) through the real scene with the built-in test autopilot:
## design -> review -> launch -> TLI -> landing -> rover science -> uplink -> result.
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/e2e_m2.gd -- [site=pole,tank=l,...] [timescale]

var _frames := 0
var _started := false
var _design := {}
var _last_state := -1


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_design = LunarDesign.default_design()
	if a.size() > 0 and a[0] != "-":
		for kv in a[0].split(","):
			var p := kv.split("=")
			if p.size() == 2:
				_design[p[0]] = p[1]
	Engine.time_scale = float(a[1]) if a.size() > 1 else 6.0
	root.get_node("GameState").progress.clear()
	change_scene_to_file("res://Missions/Mission2/mission2.tscn")


func _process(_d: float) -> bool:
	_frames += 1
	var m := current_scene
	if m == null or _frames < 5:
		return false
	if not _started:
		_started = true
		m.dev_skip_briefing()
		m.dev_auto_design(_design)
		m._on_launch()
		m.dev_autopilot = true
		print("design=", _design, " can_launch=", LunarDesign.can_launch(_design))
		return false
	if m.state != _last_state:
		_last_state = m.state
		print("state -> ", m.state, " (frame ", _frames, ")")
	for c in m.overlay.get_children():
		if c.has_method("show_result"):
			var gs := root.get_node("GameState")
			print("RESULT_SCREEN shown. progress=", gs.progress)
			if m.lm != null:
				print("landing: speed=", snappedf(m.lm.touch_speed.y, 0.1), " vx=", snappedf(m.lm.touch_speed.x, 0.1),
					" off=", snappedf(m.lm.pos.x, 0.1), " angle=", snappedf(rad_to_deg(m.lm.touch_angle), 0.1),
					" outcome=", m.lm.outcome, " fuel=", snappedf(m.lm.fuel, 1.0), " start=", snappedf(m.start_fuel, 1.0))
			print("samples=", m.r_samples, " energy=", snappedf(m.r_energy, 1.0), " exec_dv=", snappedf(m.exec_dv, 0.1),
				" corr=", snappedf(m.corr_dv, 0.1))
			quit(0)
			return true
	if _frames > 80000:
		print("TIMEOUT state=", m.state)
		quit(1)
		return true
	return false
