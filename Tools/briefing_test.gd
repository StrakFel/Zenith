extends SceneTree
## Functional UI test of the mission briefing in all 3 missions, EN + UK, at several layout sizes:
## the window must fit the screen, Start / Back must be inside it and REALLY clickable (hit-test +
## synthetic mouse clicks), ESC must go back.  Headless:
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/briefing_test.gd --quit-after 40000

const MISSIONS := ["mission1", "mission2", "mission3"]
const IDS := ["m1_launch", "m2_spacewalk", "m3_docking"]
const SIZES := [Vector2i(1280, 720), Vector2i(1024, 576), Vector2i(800, 450)]

var _fail := 0
var _router: Node
var _gs: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _idle() -> void:
	var i := 0
	while _router._busy and i < 900:
		await process_frame
		i += 1


func _load(i: int, locale: String, size: Vector2i) -> Node:
	_gs.settings["locale"] = locale
	_gs.apply_settings()
	root.size = size                    # real window size ...
	root.content_scale_size = size      # ... and layout space, so the visible rect equals `size`
	_gs.progress.clear()
	_gs.settings["unlock_all"] = true
	_router.go_to("res://Missions/Mission%d/mission%d.tscn" % [i + 1, i + 1])
	var n := 0
	while (current_scene == null or not current_scene.scene_file_path.contains(MISSIONS[i])) and n < 900:
		await process_frame
		n += 1
	await _idle()
	await _frames(40)
	return current_scene


func _briefing(m: Node) -> Control:
	for c in m.overlay.get_children():
		if c.has_signal("back_requested") and c.has_signal("started"):
			return c
	return null


func _click(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	root.push_input(mv, true)
	await process_frame
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.position = pos
	dn.global_position = pos
	root.push_input(dn, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	root.push_input(up, true)
	await process_frame


func _hover(pos: Vector2) -> Control:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	root.push_input(mv, true)
	await process_frame
	await process_frame
	return root.gui_get_hovered_control()


func _is_inside(c: Control, b: Control) -> bool:
	var n: Node = c
	while n != null:
		if n == b:
			return true
		n = n.get_parent()
	return false


func _run() -> void:
	await _frames(5)
	_router = root.get_node("Router")
	_gs = root.get_node("GameState")

	# ------------------------------------------------ layout + hit-test, every combination
	for i in 3:
		for loc in ["en", "uk"]:
			for size in SIZES:
				var tag := "%s %s %dx%d" % [MISSIONS[i], loc, size.x, size.y]
				var m := await _load(i, loc, size)
				var b := _briefing(m)
				_check(b != null, tag + ": briefing is shown")
				if b == null:
					continue
				var vis := root.get_visible_rect()
				var start: Button = b.find_child("StartButton", true, false)
				var back: Button = b.find_child("BackButton", true, false)
				var panel: Control = b.panel
				_check(Rect2(Vector2.ZERO, vis.size).grow(1.0).encloses(panel.get_global_rect()),
					tag + ": window fits the screen (%s in %s)" % [panel.get_global_rect().size, vis.size])
				_check(start != null and Rect2(Vector2.ZERO, vis.size).encloses(start.get_global_rect()), tag + ": Start button fully visible")
				_check(back != null and Rect2(Vector2.ZERO, vis.size).encloses(back.get_global_rect()), tag + ": Back button fully visible")
				var h1 := await _hover(start.get_global_rect().get_center())
				_check(h1 != null and _is_inside(h1, start), tag + ": Start button is hit by the mouse (not covered)")
				var h2 := await _hover(back.get_global_rect().get_center())
				_check(h2 != null and _is_inside(h2, back), tag + ": Back button is hit by the mouse (not covered)")
				var sc: ScrollContainer = b.scroll
				var vbar := sc.get_v_scroll_bar()
				print("      scroll: content %.0f px, visible %.0f px, scrollbar %s" % [b.body.get_combined_minimum_size().y,
					sc.size.y, "ON" if vbar.max_value > vbar.page + 1.0 else "off"])

	# ------------------------------------------------ real clicks + ESC (smallest and normal size)
	for i in 3:
		for size in [Vector2i(1280, 720), Vector2i(800, 450)]:
			var tag := "%s %dx%d" % [MISSIONS[i], size.x, size.y]
			# Start
			var m := await _load(i, "uk", size)
			var b := _briefing(m)
			var start: Button = b.find_child("StartButton", true, false)
			await _click(start.get_global_rect().get_center())
			await _frames(40)
			_check(_briefing(m) == null and m.pause_menu.enabled, tag + ": CLICK on Start mission starts the mission (briefing closed)")
			# Back
			m = await _load(i, "en", size)
			b = _briefing(m)
			var back: Button = b.find_child("BackButton", true, false)
			await _click(back.get_global_rect().get_center())
			await _idle()
			var n := 0
			while not current_scene.scene_file_path.contains("mission_select") and n < 600:
				await process_frame
				n += 1
			_check(current_scene.scene_file_path.contains("mission_select"), tag + ": CLICK on Back returns to the mission list")
			await _idle()
			# ESC
			m = await _load(i, "uk", size)
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			root.push_input(esc, true)
			await _idle()
			n = 0
			while not current_scene.scene_file_path.contains("mission_select") and n < 600:
				await process_frame
				n += 1
			_check(current_scene.scene_file_path.contains("mission_select"), tag + ": ESC closes the briefing and returns to the list")
			await _idle()

	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
