extends SceneTree
## HUD layout check (needs a real renderer): flies into the flight state, fires notifications, then verifies that no two
## HUD blocks overlap and nothing leaves the screen - in English and Ukrainian - and saves screenshots.
##   Godot --path . --resolution 1920x1080 --script res://Tools/hud_layout_test.gd -- outdir tag
var _dir := "."
var _tag := "t"
var _f := 0
var _stage := 0
var _locs := ["en", "uk"]
var _li := 0
var _fail := 0
var _m: Node

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_dir = a[0]
	if a.size() > 1:
		_tag = a[1]
	change_scene_to_file("res://Missions/Mission1/mission1.tscn")

func _rects(m: Node) -> Dictionary:
	var out := {}
	var hud: Control = m.hud
	var n := 0
	for c in hud.get_children():
		if c is VBoxContainer:
			for cc in c.get_children():
				if cc is Control and (cc as Control).visible:
					out["topcenter_%d" % n] = (cc as Control).get_global_rect()
					n += 1
		elif c is Control and (c as Control).visible:
			out["%s_%d" % [c.get_class(), n]] = (c as Control).get_global_rect()
			n += 1
	if m.cam_hint._panel.visible:
		out["cam_hint"] = m.cam_hint._panel.get_global_rect()
	if m.cam_hint._banner.visible:
		out["cam_banner"] = m.cam_hint._banner.get_global_rect()
	if m.stage_panel != null and m.stage_panel.visible:
		out["stage_panel"] = m.stage_panel.get_global_rect()
	return out

func _check_layout(tag: String) -> void:
	var m := _m
	var vp := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	var rs := _rects(m)
	var keys := rs.keys()
	var bad := 0
	for k in keys:
		var r: Rect2 = rs[k]
		if not vp.grow(1.0).encloses(r):
			print("FAIL offscreen ", tag, " ", k, " ", r, " vp=", vp)
			bad += 1
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rs[keys[i]]
			var b: Rect2 = rs[keys[j]]
			if a.size.x < 2.0 or b.size.x < 2.0:
				continue
			if a.intersects(b):
				print("FAIL overlap ", tag, " ", keys[i], " ", a, " x ", keys[j], " ", b)
				bad += 1
	if bad == 0:
		print("PASS layout ", tag, " blocks=", keys.size(), " viewport=", vp.size)
	_fail += bad

func _process(_d: float) -> bool:
	_f += 1
	_m = current_scene
	if _m == null or _f < 5:
		return false
	if _stage == 0:
		_stage = 1
		_m.dev_quick("kestrel/m/aero/u_s")
		_m.flight.skip_intro()
		_f = 5
		return false
	if _m.model == null:
		return false
	var gs := root.get_node("GameState")
	if _f == 40:
		gs.settings["locale"] = _locs[_li]
		gs.apply_settings()
		_m.dev_autopilot = true
		_m.hud.notify(tr("STG_TOAST_SEP"), Color(1.0, 0.6, 0.2))
		_m.hud.set_hint("STG_HINT_EMPTY", Color(1, 0.4, 0.4))
	if _f == 110:
		_m.hud.notify(tr("STG_TOAST_FAIRING"), Color(0.4, 0.8, 1.0))
	if _f == 120:
		_check_layout("%s-%s" % [_tag, _locs[_li]])
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/hud_%s_%s.png" % [_dir, _tag, _locs[_li]])
	if _f == 130:
		_li += 1
		if _li >= _locs.size():
			print("RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
			gs.settings["locale"] = "en"
			gs.apply_settings()
			quit(_fail)
		else:
			_f = 30
	return false
