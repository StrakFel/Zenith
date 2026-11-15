extends SceneTree
## Adaptive-layout test (needs a real renderer). Opens the main screens at the current window size / aspect ratio and checks that
## no visible UI block leaves the screen and no two panels overlap; saves a screenshot of each screen.
##   Godot --path . --resolution 2560x1080 --script res://Tools/adapt_test.gd -- outdir tag
var _dir := "."
var _tag := "t"
var _fail := 0
var _loc := "en"

const SCREENS := [
	["menu", "res://Menus/TempMenu/temp_main_menu.tscn", []],
	["select", "res://Menus/TempMenu/mission_select.tscn", []],
	["settings", "res://Menus/TempMenu/settings.tscn", []],
	["nasa", "res://Menus/TempMenu/nasa_resources.tscn", []],
	["briefing", "res://Missions/Mission1/mission1.tscn", []],
	["design", "res://Missions/Mission1/mission1.tscn", ["dev_skip_briefing"]],
	["assembly", "res://Missions/Mission1/mission1.tscn", ["dev_auto_design"]],
	["review", "res://Missions/Mission1/mission1.tscn", ["dev_review"]],
	["lab_m3", "res://Missions/Mission3/iss_launch.tscn", ["dev_skip_briefing"]],
	["hud", "res://Missions/Mission1/mission1.tscn", ["dev_quick:kestrel/m/aero/u_s"]],
]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_dir = a[0]
	if a.size() > 1:
		_tag = a[1]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _visible_controls(n: Node, out: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.visible or c.modulate.a < 0.05:
			return
		if n is ScrollContainer:
			out.append(c)
			return                      # its content is clipped and scrolls by design
		out.append(c)
	for ch in n.get_children():
		_visible_controls(ch, out)


func _is_ancestor(a: Node, b: Node) -> bool:
	var p := b.get_parent()
	while p != null:
		if p == a:
			return true
		p = p.get_parent()
	return false


func _check_screen(name: String) -> void:
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var all: Array = []
	_visible_controls(current_scene, all)
	var bad := 0
	var panels: Array = []
	for c: Control in all:
		var r := c.get_global_rect()
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		if c is Label or c is Button or c is PanelContainer or c is ProgressBar or c is TextureRect:
			if not vp.grow(1.5).encloses(r):
				# a control inside a scroll area may legitimately be outside; every other one is a layout bug
				var inside_scroll := false
				var p := c.get_parent()
				while p != null:
					if p is ScrollContainer:
						inside_scroll = true
						break
					p = p.get_parent()
				if not inside_scroll and c.get_class() != "TextureRect":
					print("FAIL offscreen %s/%s/%s %s '%s' %s vp=%s" % [_tag, _loc, name, c.get_class(), str(c.get("text")) if "text" in c else "", r, vp.size])
					bad += 1
		if c is PanelContainer and r.size.x > 60.0 and r.size.y > 40.0 and r.size.x < vp.size.x * 0.97:
			panels.append(c)
	for i in panels.size():
		for j in range(i + 1, panels.size()):
			var a: Control = panels[i]
			var b: Control = panels[j]
			if _is_ancestor(a, b) or _is_ancestor(b, a):
				continue
			var ra := a.get_global_rect()
			var rb := b.get_global_rect()
			var inter := ra.intersection(rb)
			if inter.size.x > 4.0 and inter.size.y > 4.0:
				print("FAIL overlap %s/%s/%s %s x %s" % [_tag, _loc, name, ra, rb])
				bad += 1
	_fail += bad
	if bad == 0:
		print("PASS  %s/%s/%s (%d controls, viewport %s)" % [_tag, _loc, name, all.size(), vp.size])


func _run() -> void:
	await _frames(3)
	var gs := root.get_node("GameState")
	gs.progress.clear()
	gs.settings["unlock_all"] = true
	for loc in ["en", "uk"]:
		_loc = loc
		gs.settings["locale"] = loc
		gs.apply_settings()
		for s in SCREENS:
			change_scene_to_file(str(s[1]))
			await _frames(8)
			var cs := current_scene
			for h in s[2]:
				var parts: PackedStringArray = str(h).split(":")
				if parts.size() > 1:
					cs.call(parts[0], parts[1])
				else:
					cs.call(parts[0])
			if str(s[0]) == "hud":
				cs.flight.skip_intro()
				cs.dev_autopilot = true
				await _frames(60)
				cs.hud.notify(tr("STG_TOAST_SEP"), Color(1.0, 0.6, 0.2))
				cs.hud.set_hint("STG_HINT_EMPTY", Color(1, 0.4, 0.4))
			await _frames(70)
			_check_screen(str(s[0]))
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%s_%s.png" % [_dir, _tag, loc, str(s[0])])
	gs.settings["locale"] = "en"
	gs.settings["unlock_all"] = false
	gs.apply_settings()
	print("RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
