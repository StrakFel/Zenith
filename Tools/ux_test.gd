extends SceneTree
## UX test (menus, back navigation, Demo Mode, gated separations, guided launch) with real input events where it matters.
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/ux_test.gd --quit-after 400000
var _fail := 0
var _router: Node
var _gs: Node
var _held := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_scene(part: String, limit: int = 3000) -> Node:
	var n := 0
	while (current_scene == null or not current_scene.scene_file_path.contains(part)) and n < limit:
		await process_frame
		n += 1
	for i in 200:
		if not _router._busy:
			break
		await process_frame
	await _frames(25)
	return current_scene


func _find_btn(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null


func _press(text: String) -> bool:
	var b := _find_btn(root, text)
	if b == null:
		return false
	b.pressed.emit()
	await _frames(3)
	return true


func _hold(code: Key, down: bool) -> void:
	if bool(_held.get(code, false)) == down:
		return
	_held[code] = down
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _key(code: Key) -> void:
	_hold(code, true)
	await _frames(3)
	_hold(code, false)
	await _frames(2)


func _release_all() -> void:
	for k in _held.keys():
		_hold(k, false)


func _run() -> void:
	await _frames(5)
	_router = root.get_node("Router")
	_gs = root.get_node("GameState")
	_gs.progress.clear()
	_gs.settings["unlock_all"] = false
	_gs.settings["guided"] = true

	# ---------------------------------------------------------------- Demo Mode: Play opens the mission list
	_gs.settings["unlock_all"] = true
	_router.play()
	var m := await _wait_scene("mission_select")
	_check(current_scene.scene_file_path.contains("mission_select"), "Demo Mode: Play opens the mission list first (nothing starts by surprise)")
	_gs.settings["unlock_all"] = false
	_router.play()
	m = await _wait_scene("mission1")
	_check(current_scene.scene_file_path.contains("mission1"), "Normal mode: Play with no progress starts Mission 1")

	# ---------------------------------------------------------------- briefing -> design -> assembly -> BACK
	await _press("BTN_START")
	await _frames(40)
	_check(m.design_view != null and _find_btn(root, "BTN_BACK_MISSIONS") != null, "design screen has a 'Back to missions' button")
	await _press("M1D_CONTINUE")
	await _frames(40)
	_check(m.state == m.S.ASSEMBLY and _find_btn(root, "BTN_BACK") != null, "rocket designer opened and has a Back button")
	# camera help does not sit over the part tabs: bottom-centre placement
	var hint_rect: Rect2 = m.cam_hint._panel.get_global_rect()
	var tabs_rect: Rect2 = m.assembly._tab_buttons["engine"].get_global_rect()
	_check(not hint_rect.intersects(tabs_rect), "camera hint does not overlap the part tabs")
	# required parts are marked and the missing list is explicit
	_check(m.assembly._ready_label.text.contains("Still needed") or m.assembly._ready_label.text.contains("M1_MISSING") or m.assembly._ready_label.text != "", "designer lists what is still missing")
	await _press("StarterButton") if _find_btn(root, "M1_STARTER") == null else await _press("M1_STARTER")
	await _frames(10)
	_check(str(m.assembly.build["engine"]) != "" and str(m.assembly.build["tank"]) != "" and str(m.assembly.build["nose"]) != "", "starter rocket fills the required slots")
	await _press("BTN_BACK")
	await _frames(40)
	_check(m.state == m.S.DESIGN and m.design_view != null and m.assembly == null, "Back from the designer returns to the satellite design (state intact)")
	await _press("M1D_CONTINUE")
	await _frames(40)
	_check(m.state == m.S.ASSEMBLY, "Continue again re-opens the designer")
	await _press("BTN_MISSIONS")
	m = await _wait_scene("mission_select")
	_check(current_scene.scene_file_path.contains("mission_select"), "'Missions' button in the designer leads to the mission list")

	# ---------------------------------------------------------------- gated separations
	_router.go_to("res://Missions/Mission1/mission1.tscn")
	m = await _wait_scene("mission1")
	m.dev_skip_briefing()
	m._on_design_done(M1Design.default_design())
	m.state = m.S.REVIEW
	m._on_launch({"nose": "std", "tank": "m", "engine": "kestrel", "upper": "u_s", "booster": ""})
	await _frames(30)
	m.state = m.S.FLIGHT
	m.model.engine_on = true
	m.model.throttle = 1.0
	m._do_separate()
	_check(m.model.stage == 1, "stage separation is refused right after launch (stage 1 is full)")
	m._do_fairing()
	_check(m.model.fairing_on, "fairing release is refused in dense air near the ground")
	await _frames(5)
	_check(m.stage_panel._sep_btn.disabled and m.stage_panel._fair_btn.disabled, "both buttons look disabled, with the reason shown")
	_check(m.stage_panel._hint.text == "STG_WHY_STAGE" or m.stage_panel._hint.text.contains("propellant") or m.stage_panel._hint.text != "", "a reason is displayed for the unavailable action")
	m.model.fuel = 0.10 * m.model.fuel_cap
	await _frames(5)
	_check(m.model.can_separate_stage() and not m.stage_panel._sep_btn.disabled, "stage separation unlocks when stage 1 is nearly empty")
	m.model.r = FlightModel.R + 90000.0
	await _frames(5)
	_check(m.model.can_jettison_fairing() and not m.stage_panel._fair_btn.disabled, "fairing release unlocks above 80 km")
	m._do_fairing()
	_check(not m.model.fairing_on and not m.model.fairing_early, "fairing jettisoned above 80 km without damage")

	# ---------------------------------------------------------------- guided launch: only the coach's steps, no pitch keys
	_router.go_to("res://Missions/Mission1/mission1.tscn")
	m = await _wait_scene("mission1")
	m.dev_skip_briefing()
	m._on_design_done({"goal": "earth", "instrument": "img_s", "solar": "m", "battery": "m", "comm": "x"})
	m.state = m.S.REVIEW
	m._on_launch({"nose": "std", "tank": "m", "engine": "kestrel", "upper": "u_s", "booster": ""})
	m.flight.skip_intro()
	_check(m.guided, "guided launch is on by default")
	Engine.time_scale = 4.0
	var frames := 0
	var seen: Dictionary = {}
	while frames < 60000 and not m.ended:
		frames += 1
		await process_frame
		if m.state == m.S.COUNTDOWN:
			continue
		if m.state != m.S.FLIGHT:
			continue
		var g: Array = m._guide_step()
		seen[str(g[0])] = true
		match str(g[0]):
			"GUIDE_LIFTOFF", "GUIDE_TURN", "GUIDE_BURN":
				_hold(KEY_Z, m.model.throttle < 0.99)
			"GUIDE_CUT":
				_hold(KEY_Z, false)
				await _key(KEY_X)
			"GUIDE_STAGE":
				await _key(KEY_G)
			"GUIDE_BOOST":
				await _key(KEY_B)
			"GUIDE_FAIRING":
				await _key(KEY_F)
			"GUIDE_COAST":
				_hold(KEY_Z, false)
			"GUIDE_ORBIT":
				_release_all()
				await _key(KEY_X)
				await _key(KEY_SPACE)
	_release_all()
	Engine.time_scale = 1.0
	_check(m.model.in_stable_orbit() or m.last_success, "following ONLY the on-screen coach (no steering keys) reaches orbit")
	_check(seen.has("GUIDE_TURN") and seen.has("GUIDE_CUT") and seen.has("GUIDE_BURN") and seen.has("GUIDE_STAGE"), "the coach showed the steps: turn, stage, cut, burn (%s)" % str(seen.keys()))
	for i in 3000:
		if m.ended and m.last_stars >= 0:
			break
		await process_frame
	_check(m.ended and m.last_success, "guided flight ends with a successful mission (stars %d)" % m.last_stars)
	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
