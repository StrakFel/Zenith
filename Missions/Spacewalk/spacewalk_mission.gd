extends MissionBase
## Mission 2 - Spacewalk. Fly the astronaut (inertia!) to a damaged satellite, repair
## three components, then return to the airlock slowly enough to enter it.

var world: SpacewalkWorld
var view: SpacewalkView3D
var arrow: OffscreenArrow
var hud_layer: CanvasLayer
var started := false
var dev_autopilot := false
var _ap_fine := false

var _o2_bar: ProgressBar
var _fuel_bar: ProgressBar
var _suit_bar: ProgressBar
var _speed_lbl: Label
var _dist_lbl: Label
var _o2_lbl: Label
var _task_labels: Array[Label] = []
var _hint: Label
var _hint_panel: PanelContainer
var _hint_key := ""
var _stranded_t := 0.0
var _flash: ColorRect
var inspecting := false
var cam_hint: CameraHint
var _health_bars: Array[ProgressBar] = []
var _sci_lbl: Label


var ops_launch: Dictionary = {}     # launch hand-off of Mission 2 (empty = stand-alone EVA training)
var ops_design: Dictionary = {}


func _init() -> void:
	mission_id = "eva_training"
	if str(GameState.session.get("profile", "")) == "m2":
		mission_id = "m2_space_ops"
		ops_launch = GameState.session["launch"]
		ops_design = GameState.session["design"]


func _briefing_data() -> Dictionary:
	return {
		"title": "EVA_TITLE",
		"objectives": ["M2_CTX", "M2_OBJ_1", "M2_OBJ_2", "M2_OBJ_3", "M2_OBJ_4", "M2_SCI_NOTE"],
		"controls": [
			["W A S D", "M2_CTRL_MOVE"],
			["X", "M2_CTRL_BRAKE"],
			["SHIFT", "M2_CTRL_FINE"],
			["ESC", "M1_CTRL_PAUSE"],
		],
	}


func _build_mission() -> void:
	var wl := CanvasLayer.new()
	wl.layer = 0
	add_child(wl)
	world = SpacewalkWorld.new()
	world.draw_2d = false
	wl.add_child(world)
	world.visible = false
	view = SpacewalkView3D.new()
	add_child(view)
	view.setup(world)
	_apply_launch()
	world.repaired.connect(_on_repaired)
	world.suit_hit.connect(_on_suit_hit)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	_build_hud()


## The EVA package chosen in the payload lab sets the resources; a rough launch damages the equipment.
func _apply_launch() -> void:
	if ops_launch.is_empty():
		return
	var o2: Dictionary = LaunchProfiles.EVA_O2[ops_design["o2"]]
	var n2: Dictionary = LaunchProfiles.EVA_N2[ops_design["n2"]]
	var su: Dictionary = LaunchProfiles.EVA_SUIT[ops_design["suit"]]
	var q := clampf(float(ops_launch["hull"]) / 100.0, 0.0, 1.0)
	var cond := lerpf(0.8, 1.0, q)                 # equipment condition after the ride to orbit
	world.o2_cap = SpacewalkWorld.O2_MAX * float(o2["k"]) * cond
	world.fuel_cap = SpacewalkWorld.FUEL_MAX * float(n2["k"]) * cond
	world.o2 = world.o2_cap
	world.fuel = world.fuel_cap
	world.suit_k = float(su["k"])
	world.suit = 100.0 if q >= 0.9 else 60.0 + 40.0 * q


func _build_hud() -> void:
	var root := Control.new()
	root.theme = UIKit.get_ui_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(root)
	# resources (top-left)
	var p := UIKit.panel()
	p.position = Vector2(16, 16)
	root.add_child(p)
	var v := UIKit.vbox(6)
	p.add_child(v)
	_o2_bar = _bar_row(v, "HUD_O2", UIKit.C_ACCENT)
	_o2_lbl = UIKit.label("", 14, UIKit.C_MUTED)
	v.add_child(_o2_lbl)
	_fuel_bar = _bar_row(v, "HUD_N2", UIKit.C_ORANGE)
	_suit_bar = _bar_row(v, "HUD_SUIT", UIKit.C_GOOD)
	# satellite health = what the repairs buy (links the spacewalk to the science mission)
	var hp := UIKit.panel()
	hp.position = Vector2(16, 168)
	root.add_child(hp)
	var hv := UIKit.vbox(5)
	hp.add_child(hv)
	hv.add_child(UIKit.label("M2_HEALTH", 15, UIKit.C_ORANGE))
	for pair in [["M2_H_POWER", UIKit.C_ACCENT], ["M2_H_LINK", UIKit.C_ACCENT], ["M2_H_BATT", UIKit.C_ACCENT]]:
		_health_bars.append(_bar_row(hv, pair[0], pair[1]))
	_sci_lbl = UIKit.label("", 20, UIKit.C_ORANGE)
	hv.add_child(_sci_lbl)
	# telemetry + tasks (top-right)
	var tp := UIKit.panel()
	tp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tp.offset_left = -330
	tp.offset_right = -16
	tp.offset_top = 16
	root.add_child(tp)
	var tv := UIKit.vbox(4)
	tp.add_child(tv)
	var g := GridContainer.new()
	g.columns = 2
	tv.add_child(g)
	g.add_child(UIKit.label("HUD_SPEED", 15, UIKit.C_MUTED))
	_speed_lbl = UIKit.label("0", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_speed_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(_speed_lbl)
	g.add_child(UIKit.label("HUD_TARGET_DIST", 15, UIKit.C_MUTED))
	_dist_lbl = UIKit.label("0", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	g.add_child(_dist_lbl)
	tv.add_child(HSeparator.new())
	tv.add_child(UIKit.label("M2_TASKS", 16, UIKit.C_ACCENT))
	for key in ["M2_TASK_PANEL", "M2_TASK_ANTENNA", "M2_TASK_BATTERY", "M2_TASK_RETURN"]:
		var l := UIKit.label(key, 16, UIKit.C_TEXT)
		tv.add_child(l)
		_task_labels.append(l)
	# hint (bottom-centre)
	_hint_panel = UIKit.panel()
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_panel.offset_left = -330
	_hint_panel.offset_right = 330
	_hint_panel.offset_top = -100
	_hint_panel.offset_bottom = -18
	root.add_child(_hint_panel)
	_hint = UIKit.label("", 18, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_panel.add_child(_hint)
	arrow = OffscreenArrow.new()
	arrow.camera = view.camera
	root.add_child(arrow)
	cam_hint = CameraHint.new()
	root.add_child(cam_hint)
	cam_hint.setup(true, 16.0)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.2, 0.1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_flash)


func _bar_row(parent: Control, key: String, color: Color) -> ProgressBar:
	var h := UIKit.hbox(8)
	var l := UIKit.label(key, 14, UIKit.C_MUTED)
	l.custom_minimum_size.x = 96
	h.add_child(l)
	var b := UIKit.progress_bar(color, Vector2(170, 12))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	parent.add_child(h)
	return b


func _on_mission_start() -> void:
	started = true
	view.orbit.engaged_changed.connect(func(on: bool):
		inspecting = on
		cam_hint.set_inspect(on)
		if on:
			Sfx.stop_all_loops())


func _unhandled_input(event: InputEvent) -> void:
	if started and not ended and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		view.orbit.toggle_sticky()


func _on_repaired(i: int) -> void:
	Sfx.play("repair")
	_task_labels[i].add_theme_color_override("font_color", UIKit.C_GOOD)
	_task_labels[i].text = "[x] " + tr(["M2_TASK_PANEL", "M2_TASK_ANTENNA", "M2_TASK_BATTERY"][i])
	_task_labels[i].set_meta("done", true)
	view.repair_fx(i)


func _on_suit_hit() -> void:
	Sfx.play("hit", -4.0)
	view.hit_fx()
	_flash.color.a = 0.35
	create_tween().tween_property(_flash, "color:a", 0.0, 0.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _task_labels.size() == 4:
		var keys := ["M2_TASK_PANEL", "M2_TASK_ANTENNA", "M2_TASK_BATTERY", "M2_TASK_RETURN"]
		for i in 4:
			if _task_labels[i].has_meta("done"):
				_task_labels[i].text = "[x] " + tr(keys[i])


func _process(delta: float) -> void:
	if not started or ended:
		return
	if inspecting:
		# INSPECT MODE: the world is frozen, only the camera moves
		_update_hud()
		return
	var dir := Vector2.ZERO
	var fine := false
	var brake := false
	if dev_autopilot:
		dir = _autopilot_dir()
		fine = _ap_fine
		brake = false
	else:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			dir.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			dir.x += 1.0
		fine = Input.is_physical_key_pressed(KEY_SHIFT)
		brake = Input.is_physical_key_pressed(KEY_X)
	world.step(delta, dir, fine, brake)
	if world.thrusting:
		Sfx.loop("hiss", -16.0 if not fine else -24.0, 1.0)
	else:
		Sfx.loop_stop("hiss")
	_update_hud()
	_check_end()


## Simple test pilot: fly toward the next goal, slow down when close.
## Test pilot: shortest route round the solid parts (visibility graph over the inflated corners of the hulls).
## A target that lies inside a part (the dish) is approached from the nearest free side.
func _route_next(from: Vector2, goal: Vector2) -> Vector2:
	var pad := SpacewalkWorld.ASTRO_R + 0.9
	var rects: Array[Rect2] = []
	for r in world.hulls():
		rects.append(r.grow(pad))
	var cands: Array[Vector2] = []
	var holder := -1
	for i in rects.size():
		if rects[i].grow(-0.05).has_point(goal):
			holder = i
	if holder < 0:
		cands.append(goal)
	else:
		var r: Rect2 = rects[holder]
		for c in [Vector2(goal.x, r.position.y - 0.1), Vector2(goal.x, r.end.y + 0.1), Vector2(r.position.x - 0.1, goal.y), Vector2(r.end.x + 0.1, goal.y)]:
			var free := goal.distance_to(c) <= SpacewalkWorld.TARGET_R - 0.4
			for q in rects:
				if q.grow(-0.05).has_point(c):
					free = false
			if free:
				cands.append(c)
		if cands.is_empty():
			cands.append(goal)
	var best_cost := INF
	var best_wp := goal
	for c in cands:
		var res := _plan(from, c, rects)
		if float(res[0]) < best_cost:
			best_cost = float(res[0])
			best_wp = res[1]
	return best_wp


## Returns [path length, first waypoint].
func _plan(from: Vector2, goal: Vector2, rects: Array[Rect2]) -> Array:
	if _seg_clear(from, goal, rects):
		return [from.distance_to(goal), goal]
	var nodes: Array[Vector2] = [from, goal]
	for r in rects:
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var inside := false
			for q in rects:
				if q.grow(-0.05).has_point(c):
					inside = true
					break
			if not inside:
				nodes.append(c)
	var n := nodes.size()
	var dist: Array[float] = []
	var prev: Array[int] = []
	var done: Array[bool] = []
	for i in n:
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	dist[0] = 0.0
	for _k in n:
		var u := -1
		for i in n:
			if not done[i] and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0 or dist[u] == INF:
			break
		done[u] = true
		if u == 1:
			break
		for v in n:
			if done[v]:
				continue
			var d: float = dist[u] + nodes[u].distance_to(nodes[v])
			if d < dist[v] and _seg_clear(nodes[u], nodes[v], rects):
				dist[v] = d
				prev[v] = u
	if prev[1] < 0:
		return [INF, goal]
	var cur := 1
	while prev[cur] != 0 and prev[cur] >= 0:
		cur = prev[cur]
	return [dist[1], nodes[cur]]


func _seg_clear(a: Vector2, b: Vector2, rects: Array[Rect2]) -> bool:
	for r0 in rects:
		var r := r0.grow(-0.05)            # touching an edge (corner to corner along a side) is allowed
		var d := b - a
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for ax in 2:
			var da: float = d[ax]
			var lo: float = r.position[ax]
			var hi: float = r.end[ax]
			if absf(da) < 0.00001:
				if a[ax] < lo or a[ax] > hi:
					hit = false
					break
			else:
				var ta := (lo - a[ax]) / da
				var tb := (hi - a[ax]) / da
				t0 = maxf(t0, minf(ta, tb))
				t1 = minf(t1, maxf(ta, tb))
				if t0 > t1:
					hit = false
					break
		if hit:
			return false
	return true


var _ap_goal := Vector2(1e9, 1e9)
var _ap_wp := Vector2.ZERO


func _autopilot_dir() -> Vector2:
	var goal := world.next_target()
	# commit to a waypoint until it is reached (re-planning every frame makes the pilot dither and burn fuel)
	var passing := _ap_wp.distance_to(goal) > 3.2        # an intermediate waypoint (not the final approach): fly through it at speed
	if goal != _ap_goal or world.pos.distance_to(_ap_wp) < (2.2 if passing else 1.3):
		_ap_goal = goal
		_ap_wp = _route_next(world.pos, goal)
	var tgt := _ap_wp
	var to := tgt - world.pos
	var d := to.length()
	var v := world.vel
	var want_speed := clampf(d * 0.18, 0.35, 2.6)
	if d < 10.0:
		want_speed = clampf(d * 0.12, 0.0, 0.6)
	if d < 1.6:
		want_speed = 0.0
	if passing and _ap_wp.distance_to(goal) > 3.2:
		want_speed = 2.3
	var want := to.normalized() * want_speed if d > 0.01 else Vector2.ZERO
	var diff := want - v
	_ap_fine = d < 14.0
	if diff.length() < (0.1 if _ap_fine else 0.3):
		return Vector2.ZERO
	return diff.normalized()


func _update_hud() -> void:
	for i in 3:
		var hb: ProgressBar = _health_bars[i]
		hb.value = 100.0 if world.done[i] else 15.0 + 40.0 * world.progress[i]
		UIKit.set_bar_color(hb, UIKit.C_GOOD if world.done[i] else UIKit.C_BAD)
	_sci_lbl.text = "%s: %d%%" % [tr("M2_H_SCI"), int(_science() * 100.0)]
	_o2_bar.value = world.o2 / world.o2_cap * 100.0
	_fuel_bar.value = world.fuel / world.fuel_cap * 100.0
	_suit_bar.value = world.suit
	UIKit.set_bar_color(_o2_bar, UIKit.C_BAD if world.o2 < 60.0 else UIKit.C_ACCENT)
	UIKit.set_bar_color(_fuel_bar, UIKit.C_BAD if world.fuel < 10.0 else UIKit.C_ORANGE)
	UIKit.set_bar_color(_suit_bar, UIKit.C_BAD if world.suit < 40.0 else UIKit.C_GOOD)
	_o2_lbl.text = "%d:%02d" % [int(world.o2) / 60, int(world.o2) % 60]
	_speed_lbl.text = "%.2f %s" % [world.vel.length(), tr("UNIT_MS")]
	_speed_lbl.add_theme_color_override("font_color", UIKit.C_GOOD if world.vel.length() < SpacewalkWorld.REPAIR_MAX_SPEED else Color.WHITE)
	_dist_lbl.text = Units.m(world.pos.distance_to(world.next_target()))
	arrow.target = SpacewalkView3D.p3(world.next_target())
	arrow.distance_text = _dist_lbl.text
	arrow.color = UIKit.C_GOOD if world.all_repaired else UIKit.C_ORANGE
	var key := "M2_HINT_GO"
	if world.fuel <= 0.0:
		key = "M2_HINT_NOFUEL"
	elif world.o2 < 45.0:
		key = "M2_HINT_O2"
	elif world.all_repaired:
		key = "M2_HINT_RETURN"
	else:
		var near := false
		for i in 3:
			if not world.done[i] and world.pos.distance_to(world.target_world(i)) < SpacewalkWorld.TARGET_R + 6.0:
				near = true
		key = "M2_HINT_HOLD" if near else "M2_HINT_GO"
	if key != _hint_key:
		_hint_key = key
		_hint.text = key
		var col := UIKit.C_TEXT
		if key == "M2_HINT_NOFUEL" or key == "M2_HINT_O2":
			col = UIKit.C_BAD
		elif key == "M2_HINT_RETURN":
			col = UIKit.C_GOOD
		_hint.add_theme_color_override("font_color", col)


func _check_end() -> void:
	if world.all_repaired and world.at_hatch():
		_win()
		return
	if world.suit <= 0.0:
		_lose("M2_FAIL_SUIT")
	elif world.o2 <= 0.0:
		_lose("M2_FAIL_O2")
	elif world.pos.length() > 260.0:
		_lose("M2_FAIL_LOST")
	elif world.fuel <= 0.0 and not world.drift_hope():
		_stranded_t += get_process_delta_time()
		if _stranded_t > 3.0:
			_lose("M2_FAIL_STRANDED")
	else:
		_stranded_t = 0.0


## Science output of the satellite given the repairs done so far (base 20 %).
func _science() -> float:
	return 0.20 + 0.35 * float(world.done[0]) + 0.30 * float(world.done[1]) + 0.15 * float(world.done[2])


func _stats() -> Array:
	return [
		["R_SCI_RESTORED", "%d%%" % int(_science() * 100.0)],
		["R_REPAIRS", "%d / 3" % (int(world.done[0]) + int(world.done[1]) + int(world.done[2]))],
		["R_FUEL_LEFT", "%d%%" % int(world.fuel / world.fuel_cap * 100.0)],
		["R_O2_LEFT", "%d:%02d" % [int(world.o2) / 60, int(world.o2) % 60]],
		["R_SUIT", "%d%%" % int(world.suit)],
	]


func _win() -> void:
	var stars := 1
	if world.fuel / world.fuel_cap >= 0.3:
		stars += 1
	if world.o2 / world.o2_cap >= 0.35 and world.suit >= 90.0:
		stars += 1
	var score := stars * 1000 + int(world.fuel * 10.0) + int(world.o2 * 2.0) + int(world.suit * 3.0)
	var s := _stats()
	s.append(["R_SCORE", str(score)])
	var tips: Array = []
	if world.fuel / world.fuel_cap < 0.3:
		tips.append("M2_TIP_FUEL")
	if world.suit < 90.0:
		tips.append("M2_TIP_SUIT")
	if world.o2 / world.o2_cap < 0.35:
		tips.append("M2_TIP_O2")
	if tips.is_empty():
		tips.append("M2_TIP_GOOD")
	var sci := _science()
	var segs: Array = []
	if not ops_launch.is_empty():
		segs.append(["SEG_LAUNCH", _launch_rating()])
		s.append(["R_BUDGET_USED", "%s / %s" % [Units.money(int(ops_launch["cost"])), Units.money(int(ops_launch["budget"]))]])
		s.append(["R_LAUNCH_HULL", "%d%%" % int(ops_launch["hull"])])
	segs.append_array([["SEG_SPACE", clampf(float(world.suit) / 100.0, 0.0, 1.0)],
			["SEG_GROUND", 0.2 + 0.8 * float(world.done[1])],
			["SEG_USER", sci]])
	var extra := {
		"segments": segs,
		"science": sci, "science_note": "M2_SCI_NOTE", "tips": tips,
		"user": "USER_EARTH_%d" % M1Design.science_tier(sci),
	}
	Sfx.stop_all_loops()
	finish(true, stars, score, s, "M2_WIN_REASON", 0.8, extra)


func _launch_rating() -> float:
	var l := ops_launch
	var r := float(l["hull"]) / 100.0 * 0.6 + float(l["orbit_q"]) * 0.25 + (0.15 if not bool(l["fairing_early"]) else 0.0)
	r *= 1.0 - clampf(float(l["waste"]) * 0.3 + float(l["booster_waste"]) * 0.2, 0.0, 0.3)
	return clampf(r, 0.0, 1.0)


func _lose(reason: String) -> void:
	Sfx.stop_all_loops()
	finish(false, 0, 0, _stats(), reason, 1.2)


