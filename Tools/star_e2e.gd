extends SceneTree
## Plays REAL Mission 1 scenes (autopilot flight) for designs picked from the balance CSV, one per outcome class, and
## compares the stars the game awards with the balance analysis.
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/star_e2e.gd -- balance.csv [rows_per_class] [timescale]
var _rows: Array = []
var _queue: Array = []
var _cur := {}
var _f := 0
var _started := false
var _results: Array = []
var _timescale := 10.0
var _shot_dir := ""
var _shot_wait := -1

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var per := int(a[1]) if a.size() > 1 else 2
	_timescale = float(a[2]) if a.size() > 2 else 10.0
	_shot_dir = a[3] if a.size() > 3 else ""
	var fa := FileAccess.open(a[0], FileAccess.READ)
	var head := fa.get_csv_line()
	while not fa.eof_reached():
		var l := fa.get_csv_line()
		if l.size() == head.size():
			var d := {}
			for i in head.size():
				d[head[i]] = l[i]
			_rows.append(d)
	# pick rows spread over goals for every class; class 0 = orbit reached but science failed
	var want := {3: [], 2: [], 1: [], 0: []}
	var seen := {}
	for r in _rows:
		var st := int(r["stars"])
		if st == 0 and r["cause"] == "orbit":
			continue
		var key := "%d|%s" % [st, r["goal"]]
		if st == 3:
			# three-star builds: show that DIFFERENT rockets work (one row per distinct rocket, 3 per goal)
			var rk := "%s/%s/%s/%s" % [r["nose"], r["tank"], r["engine"], r["upper"]]
			if seen.has(key + rk) or int(seen.get(key, 0)) >= 3:
				continue
			seen[key + rk] = 1
		elif int(seen.get(key, 0)) >= per:
			continue
		seen[key] = int(seen.get(key, 0)) + 1
		want[st].append(r)
	var classes: Array = [3, 2, 1, 0]
	if a.size() > 4:
		classes = []
		for c in a[4].split(","):
			classes.append(int(c))
	for st in classes:
		for r in want[st]:
			if _shot_dir != "" and want[st].find(r) > 0:
				continue
			_queue.append(r)
	Engine.time_scale = _timescale
	_next()

func _next() -> void:
	_started = false
	_f = 0
	if _queue.is_empty():
		var tot := {}
		var ok := {}
		for r in _results:
			var k: int = r["expect"]
			tot[k] = int(tot.get(k, 0)) + 1
			if r["got"] == r["expect"]:
				ok[k] = int(ok.get(k, 0)) + 1
		for k in [3, 2, 1, 0]:
			print("class %d stars: matched %d of %d" % [k, int(ok.get(k, 0)), int(tot.get(k, 0))])
		var reached := {}
		for r in _results:
			reached[int(r["got"])] = true
		print("star levels actually awarded by the real game: ", reached.keys())
		quit(0)
		return
	_cur = _queue.pop_front()
	var gs := root.get_node("GameState")
	gs.progress.clear()
	change_scene_to_file("res://Missions/Mission1/mission1.tscn")

func _process(_d: float) -> bool:
	_f += 1
	var m := current_scene
	if m == null or _f < 5 or _cur.is_empty():
		return false
	if not _started:
		_started = true
		m.dev_skip_briefing()
		var sat := {"goal": _cur["goal"], "instrument": _cur["instrument"], "solar": _cur["solar"], "battery": _cur["battery"], "comm": _cur["comm"]}
		m._on_design_done(sat)
		m._on_review_request_dev({"nose": _cur["nose"], "tank": _cur["tank"], "engine": _cur["engine"], "upper": _cur["upper"]}) if m.has_method("_on_review_request_dev") else null
		m.design = sat
		m.sat = M1Design.sat_stats(sat)
		m._on_launch({"nose": _cur["nose"], "tank": _cur["tank"], "engine": _cur["engine"], "upper": _cur["upper"]})
		m.dev_autopilot = true
		m.flight.skip_intro()
		return false
	if m.ended and m.last_stars >= 0 and _shot_dir != "":
		# visual mode: let the result screen animate, save a screenshot, then continue
		if _shot_wait < 0:
			_shot_wait = 150
		_shot_wait -= 1
		if _shot_wait == 0:
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/result_%s_%s.png" % [_shot_dir, _cur["stars"], _cur["goal"]])
		if _shot_wait > 0:
			return false
		_shot_wait = -1
	if m.ended and m.last_stars >= 0:
		_results.append({"expect": int(_cur["stars"]), "got": m.last_stars})
		var px: Dictionary = m.last_prox
		var okn := 0
		if not px.is_empty():
			for r in px["reqs"]:
				if bool(r["ok"]):
					okn += 1
		print("expect %s star(s), game awarded %d | PROXIMITY %d%% reqs_ok=%d/7 best=%d | %s/%s/%s/%s | %s %s %s%s%s | cost %s" % [_cur["stars"], m.last_stars,
			int(px.get("percent", -1)), okn, int(px.get("best", -1)),
			_cur["nose"], _cur["tank"], _cur["engine"], _cur["upper"], _cur["goal"], _cur["instrument"], _cur["solar"], _cur["battery"], _cur["comm"], _cur["cost"]])
		_cur = {}
		_next()
	elif _f > 60000:
		print("TIMEOUT ", _cur)
		_results.append({"expect": int(_cur["stars"]), "got": -1})
		_cur = {}
		_next()
	return false
