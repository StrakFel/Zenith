extends SceneTree
## Mission 5 story flow test: runs the whole Moon & Return operations phase (LOI -> descent -> EVA -> ascent -> docking -> crew transfer
## -> TEI -> re-entry -> parachutes -> splashdown) with the DEFAULT autopilot (no test pilot) and prints every stage.
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/m5_flow_test.gd --quit-after 400000 -- [ascent: s|m] [capsule: light|heavy] [timescale]
var _m: Node
var _last := ""
var _t := 0
var _fail := 0
var _stages: Array = []
var _manual_dock := false
var _manual_done := false
var _gs_session: Dictionary = {}


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var asc := a[0] if a.size() > 0 else "m"
	var cap := a[1] if a.size() > 1 else "heavy"
	Engine.time_scale = float(a[2]) if a.size() > 2 else 8.0
	_manual_dock = a.size() > 3 and a[3] == "manual_dock"
	var gs := root.get_node("GameState")
	gs.session = {"design": {"site": "mare", "launcher": "heavy", "engine": "std", "tank": "m", "rover": "scout", "instrument": "cam",
		"solar": "m", "battery": "m", "comm": "hga", "capsule": cap, "ascent": asc, "ascent_stage": asc},
		"launch": {"hull": 100.0, "orbit_q": 1.0, "dv_left": 3300.0, "cost": 300, "budget": 560, "waste": 0.0, "booster_waste": 0.0, "fairing_early": false}}
	change_scene_to_file("res://Missions/Mission5/mission5_ops.tscn")


func _process(_d: float) -> bool:
	_t += 1
	_m = current_scene
	if _m == null or _t < 5:
		return false
	if _t == 5:
		var gs := root.get_node("GameState")
		gs.progress.clear()
		gs.settings["autoflight"] = true
		_m.dev_skip_briefing()
		print("DBG setting=", root.get_node("GameState").settings["autoflight"], " auto_flight=", _m.auto_flight)
	if _m._rs == "dock" and not _manual_done and _manual_dock:
		_manual_done = true
		_m._set_auto(false)
		print("MANUAL docking: autopilot off (no input -> must end in a clean failure)")
	var tag := "%s|%d|%s%s" % [_m._rs, _m.state, "EVA:" + _m._eva if _m._eva != "" else "", "H" if _m._homing else ""]
	if tag != _last:
		_last = tag
		_stages.append(tag)
		print("t=%d  %s" % [_t, tag])
	if _m.ended:
		var ok: bool = _m.get("last_success") if "last_success" in _m else false
		print("RESULT ended success=%s ret=%s" % [str(ok), str(_m.ret)])
		quit(0)
		return true
	if _t > 400000:
		print("TIMEOUT stage ", _last)
		quit(1)
	return false
