extends SceneTree
## End-to-end test for missions 2 and 3 using each mission's built-in test autopilot.
##   Godot --headless --path . --script res://Tools/e2e_generic.gd -- res://Missions/Mission2/mission2.tscn [timescale]

var _frames := 0
var _stage := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	Engine.time_scale = float(a[1]) if a.size() > 1 else 5.0
	root.get_node("GameState").progress.clear()
	change_scene_to_file(a[0])


func _collect(n: Node, out: Array[String]) -> void:
	if n is Label:
		out.append(str((n as Label).text))
	for ch in n.get_children():
		_collect(ch, out)


func _process(_d: float) -> bool:
	_frames += 1
	var m := current_scene
	if m == null or _frames < 5:
		return false
	if _stage == 0:
		_stage = 1
		m.dev_skip_briefing()
		m.dev_autopilot = true
		return false
	if _frames % 300 == 0 and "world" in m and m.world != null:
		var w = m.world
		print("t=", _frames / 60, " pos=", w.pos.snappedf(0.1), " vel=", w.vel.snappedf(0.01), " fuel=", snappedf(w.fuel, 0.1),
			(" done=" + str(w.done)) if "done" in w else (" angle=" + str(snappedf(w.angle, 0.01))))
	for c in m.overlay.get_children():
		if c.has_method("show_result"):
			var gs := root.get_node("GameState")
			print("RESULT_SCREEN shown. progress=", gs.progress)
			var texts: Array[String] = []
			_collect(c, texts)
			print("RESULT_TEXTS: ", " | ".join(texts))
			quit(0)
			return true
	if _frames > 40000:
		print("TIMEOUT")
		quit(1)
	return false

