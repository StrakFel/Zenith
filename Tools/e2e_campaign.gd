extends SceneTree
## End-to-end test of the whole campaign through the REAL scenes (launch segment -> hand-off -> operations -> results) with the
## built-in test autopilots. Godot --headless --fixed-fps 60 --path . --script res://Tools/e2e_campaign.gd -- [m2,m3,m4,m5] [timescale]
var _plan: Array = []
var _i := -1
var _f := 0
var _phase := 0           # 0 = launch scene, 1 = operations scene
var _t_scene := 0
var _lines: Array = []
var _scale := 10.0
var _ret_wait := 0

var _specs := {
	"m2": {"design": {"o2": "m", "n2": "m", "suit": "std"}, "build": {"nose": "std", "tank": "m", "engine": "kestrel", "upper": "", "booster": ""}},
	"m3": {"design": {"experiment": "crystals", "launcher": "medium", "rcs": "m"}, "build": {"nose": "std", "tank": "m", "engine": "kestrel", "upper": "", "booster": ""}},
	"m4": {"design": {"sat": "small", "count": "6", "disp": "precision"}, "build": {"nose": "std", "tank": "m", "engine": "kestrel", "upper": "u_s", "booster": "b_s"}},
	"m5": {"design": {"site": "mare", "rover": "scout", "instrument": "cam", "solar": "m", "battery": "m", "comm": "hga", "tank": "m", "capsule": "heavy", "ascent": "m"},
		"build": {"nose": "std", "tank": "xl", "engine": "titan", "upper": "u_t", "booster": ""}},
}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var which := (a[0] if a.size() > 0 and a[0] != "-" else "m2,m3,m4,m5").split(",")
	_scale = float(a[1]) if a.size() > 1 else 10.0
	for w in which:
		_plan.append(w)
	Engine.time_scale = _scale
	_next()

func _next() -> void:
	_i += 1
	_f = 0
	_phase = 0
	_t_scene = 0
	if _i >= _plan.size():
		print("\nSUMMARY")
		for l in _lines:
			print(l)
		quit(0)
		return
	var id: String = _plan[_i]
	root.get_node("GameState").progress.clear()
	root.get_node("GameState").session = {}
	var scene: String = {"m2": "res://Missions/Mission2/space_ops.tscn", "m3": "res://Missions/Mission3/iss_launch.tscn",
		"m4": "res://Missions/Mission4/constellation_launch.tscn", "m5": "res://Missions/Mission5/moon_launch.tscn"}[id]
	change_scene_to_file(scene)

func _process(_d: float) -> bool:
	if _i >= _plan.size():
		return false
	_f += 1
	var m := current_scene
	if m == null or _f < 5:
		return false
	var id: String = _plan[_i]
	var spec: Dictionary = _specs[id]
	if _phase == 0:
		if _f == 5:
			m.dev_skip_briefing()
			m._on_design_done(spec["design"])
			var st := M1Parts.compute(spec["build"], float(m.sat["mass"]), int(m.sat["cost"]))
			print("[%s] payload %d kg | rocket cost %d/%d dv %d (need %d) twr %.2f can_launch %s" % [id, int(m.sat["mass"]), int(st["cost"]), M1Parts.active_budget, int(st["dv"]), int(LaunchProfiles.required_dv(id)), float(st["twr"]), M1Parts.can_launch(st)])
			m.state = m.S.REVIEW
			m._on_launch(spec["build"])
			m.dev_autopilot = true
			m.flight.skip_intro()
			return false
		if m.scene_file_path != "" and not m.scene_file_path.contains("launch") and not m.scene_file_path.contains("space_ops"):
			pass
		if m.ended and m.last_stars >= 0:
			_lines.append("[%s] LAUNCH FAILED in the launch segment (stars=%d)" % [id, m.last_stars])
			print(_lines[-1])
			_next()
			return false
		if not root.get_node("GameState").session.is_empty() and root.get_node("GameState").session.get("profile", "") == id and m._handoff_started:
			_phase = 1
			_t_scene = _f
			var L: Dictionary = root.get_node("GameState").session["launch"]
			print("   hand-off: hull %d%% orbit %.0f km orbit_q %.2f dv_left %d cost %d/%d" % [int(L["hull"]), float(L["mean_km"]), float(L["orbit_q"]), int(L["dv_left"]), int(L["cost"]), int(L["budget"])])
		if _f > 90000:
			_lines.append("[%s] TIMEOUT in launch" % id)
			_next()
		return false
	# ---- operations scene
	if m.scene_file_path.contains("launch") or m.scene_file_path.contains("space_ops"):
		return false       # still fading to the next scene
	if _f - _t_scene < 10:
		return false
	if not ("started" in m and m.started) and m.has_method("dev_skip_briefing") and _f - _t_scene < 600 and not ("_ops_begun" in m):
		pass
	if not m.get_meta("zen_begun", false):
		m.set_meta("zen_begun", true)
		m.dev_skip_briefing()
		m.dev_autopilot = true
		return false
	# Mission 5: drive the return legs
	if id == "m5" and "_ret_panel" in m and m._ret_panel != null and is_instance_valid(m._ret_panel):
		_ret_wait += 1
		if _ret_wait > 30:
			_ret_wait = 0
			match m._ret_step:
				0:
					if not m._ret_btn.disabled:
						m._ret_execute()
				1:
					m._ret_slider.value = 1000.0
					m._ret_execute()
				2:
					m._ret_slider.value = -6.0
					m._ret_execute()
	if m.ended and m.last_stars >= 0:
		var line := "[%s] RESULT: success=%s stars=%d" % [id, m.last_success, m.last_stars]
		_lines.append(line)
		print(line)
		_next()
	elif _f > 160000:
		_lines.append("[%s] TIMEOUT in operations (state %s)" % [id, str(m.get("state"))])
		print(_lines[-1])
		_next()
	return false
