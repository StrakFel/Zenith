extends SceneTree
## FULL PLAYTHROUGH through REAL INPUT EVENTS (Input.parse_input_event = same path as the OS):
##   Main menu -> Missions -> Briefing -> Start -> Gameplay -> Results -> Next mission, x3,
##   plus camera inspect (C / drag / wheel / RMB / R), pause, restart, loss and save checks.
## Mouse clicks hit real buttons; flying uses real key presses driven by a small "pilot" script
## (so this is an automated test, NOT a human playing).
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/play_full.gd --quit-after 400000

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


func _idle() -> void:
	var i := 0
	while _router._busy and i < 900:
		await process_frame
		i += 1


func _wait_scene(part: String, limit: int = 1200) -> Node:
	var n := 0
	while (current_scene == null or not current_scene.scene_file_path.contains(part)) and n < limit:
		await process_frame
		n += 1
	await _idle()
	await _frames(25)
	return current_scene


# ----------------------------------------------------------------- real input ---
func _move(pos: Vector2, rel: Vector2 = Vector2.ZERO, mask: int = 0) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = mask
	Input.parse_input_event(e)


func _btn(btn: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = (1 << (btn - 1)) if pressed else 0
	Input.parse_input_event(e)


func _click_at(pos: Vector2) -> void:
	_move(pos)
	await _frames(2)
	_btn(MOUSE_BUTTON_LEFT, true, pos)
	await _frames(2)
	_btn(MOUSE_BUTTON_LEFT, false, pos)
	await _frames(3)


func _click(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	await _click_at(c.get_global_rect().get_center())
	return true


func _find_btn(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null


func _click_text(text: String) -> bool:
	var b := _find_btn(root, text)
	if b == null or b.disabled:
		return false
	return await _click(b)


func _key(code: Key) -> void:
	_hold(code, true)
	await process_frame
	_hold(code, false)
	await process_frame


func _hold(code: Key, down: bool) -> void:
	if _held.get(code, false) == down:
		return
	_held[code] = down
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _release_all() -> void:
	for k in _held.keys():
		_hold(k, false)


func _drag(btn: MouseButton, total: Vector2, start: Vector2 = Vector2(640, 360)) -> void:
	var pos := start
	_move(pos)
	await _frames(2)
	_btn(btn, true, pos)
	await _frames(2)
	for i in 12:
		pos += total / 12.0
		_move(pos, total / 12.0, 1 if btn == MOUSE_BUTTON_LEFT else 2)
		await process_frame
	_btn(btn, false, pos)
	await _frames(2)


func _has_result(m: Node) -> bool:
	for c in m.overlay.get_children():
		if c.has_method("show_result"):
			return true
	return false


func _wait_result(m: Node, limit: int) -> bool:
	var n := 0
	while not _has_result(m) and n < limit:
		await process_frame
		n += 1
	await _frames(40)
	return _has_result(m)


# ---------------------------------------------------------------------- main ----
func _run() -> void:
	await _frames(5)
	_router = root.get_node("Router")
	_gs = root.get_node("GameState")
	root.size = Vector2i(1280, 720)
	_gs.progress.clear()
	_gs.settings["unlock_all"] = false
	_gs.settings["locale"] = "en"
	_gs.apply_settings()

	# ============================================================ MAIN MENU
	_router.go_to("res://Menus/TempMenu/temp_main_menu.tscn")
	var m := await _wait_scene("temp_main_menu")
	_check(_find_btn(root, "MENU_PLAY") != null and _find_btn(root, "MENU_MISSIONS") != null
		and _find_btn(root, "MENU_SETTINGS") != null and _find_btn(root, "MENU_EXIT") != null, "main menu shows Play / Missions / Settings / Exit")
	await _click_text("MENU_SETTINGS")
	m = await _wait_scene("settings")
	_check(current_scene.scene_file_path.contains("settings"), "CLICK Settings opens the settings screen")
	await _click_text("BTN_BACK")
	m = await _wait_scene("temp_main_menu")
	_check(current_scene.scene_file_path.contains("temp_main_menu"), "CLICK Back returns to the main menu")
	await _click_text("MENU_MISSIONS")
	m = await _wait_scene("mission_select")
	_check(current_scene.scene_file_path.contains("mission_select"), "CLICK Missions opens the mission list (a different screen from Play)")
	var sel: Node = current_scene
	_check((_gs.progress.is_empty()), "progress is empty at the start")
	sel._select(1, false)
	await _frames(5)
	_check((sel._detail["go"] as Button).disabled, "Mission 2 is locked before Mission 1 is done")
	sel._select(0, false)
	await _frames(5)

	# ============================================================ MISSION 1
	_check(await _click_text("MS_LAUNCH"), "CLICK Launch mission on Mission 1")
	m = await _wait_scene("mission1")
	var br: Node = null
	for c in m.overlay.get_children():
		if c.has_signal("started") and c.has_signal("back_requested"):
			br = c
	_check(br != null, "M1: briefing is shown")
	_check(await _click_text("BTN_START"), "M1: CLICK Start mission")
	await _frames(40)
	_check(m.design_view != null and m.pause_menu.enabled, "M1: mission design screen is open")
	# choose a different instrument + the faster antenna with real clicks
	var cards: Array = m.design_view._sat_box.get_children()
	cards = m.design_view._sat_box.get_children()
	# the antenna options are below the fold: scroll the list with the REAL mouse wheel like a player would
	var list_pos: Vector2 = m.design_view._sat_box.get_parent().get_global_rect().get_center()
	for i in 14:
		if cards[14].get_global_rect().end.y <= m.design_view._sat_box.get_parent().get_global_rect().end.y:
			break
		_btn(MOUSE_BUTTON_WHEEL_DOWN, true, list_pos)
		_btn(MOUSE_BUTTON_WHEEL_DOWN, false, list_pos)
		await _frames(4)
	await _frames(10)
	_check(cards[14].get_global_rect().end.y <= m.design_view._sat_box.get_parent().get_global_rect().end.y + 1.0,
		"M1: mouse wheel scrolls the satellite option list down to the antennas")
	await _click(cards[14])
	await _frames(5)
	_check(m.design_view.design["comm"] == "ka", "M1: real click changed the satellite design (Ka antenna)")
	await _click_text("M1D_CONTINUE")
	await _frames(40)
	_check(m.state == m.S.ASSEMBLY and m.assembly != null, "M1: rocket designer opened")
	# drag&drop a part with the real mouse
	var inst := _find_btn(root, "M1_INSTALL")
	var card_ctrl: Control = inst.get_parent().get_parent().get_parent()   # the card
	var from := card_ctrl.get_global_rect().position + Vector2(40, 40)
	await _drag(MOUSE_BUTTON_LEFT, Vector2(640, 360) - from, from)
	await _frames(10)
	_check(str(m.assembly.build["engine"]) != "", "M1: DRAG & DROP of an engine onto the stand works (engine = %s)" % m.assembly.build["engine"])
	# the rest through the Install buttons
	await _click_text("M1_SLOT_TANK")
	await _frames(5)
	var installs: Array = []
	_collect_buttons(root, "M1_INSTALL", installs)
	await _click(installs[1])
	await _click_text("M1_SLOT_UPPER")
	await _frames(5)
	installs.clear()
	_collect_buttons(root, "M1_INSTALL", installs)
	await _click(installs[0])
	await _click_text("M1_SLOT_NOSE")
	await _frames(5)
	installs.clear()
	_collect_buttons(root, "M1_INSTALL", installs)
	await _click(installs[0])
	await _click_text("M1_SLOT_ENGINE")
	await _frames(5)
	installs.clear()
	_collect_buttons(root, "M1_INSTALL", installs)
	await _click(installs[1])
	await _frames(10)
	var bd: Dictionary = m.assembly.build
	_check(bd["engine"] == "kestrel" and bd["tank"] == "m" and bd["nose"] == "std" and bd["upper"] == "u_s", "M1: rocket assembled by clicks %s" % str(bd))
	_check(await _click_text("M1_TO_REVIEW"), "M1: CLICK Design review")
	await _frames(40)
	_check(m.state == m.S.REVIEW, "M1: design review (verification) window is open")
	_check(await _click_text("REV_LAUNCH"), "M1: CLICK Approve and launch")
	await _frames(40)
	_check(m.summary != null and is_instance_valid(m.summary), "M1: Mission Summary window is shown before the countdown")
	_check(await _click_text("SUM_CONFIRM"), "M1: CLICK Confirm and start countdown")
	await _frames(30)
	_check(m.state == m.S.COUNTDOWN, "M1: countdown started")
	await _frames(430)
	_check(m.state == m.S.FLIGHT, "M1: lift-off, flight state")

	# ---- real camera inspect during flight
	await _frames(120)
	await _check_inspect_m1(m)

	# ---- fly with the keyboard
	var ok := await _fly_m1(m)
	_check(ok, "M1: orbit reached, satellite deployed, results window shown (keyboard pilot)")
	_release_all()
	_check(_gs.is_completed("m1_launch"), "M1: progress saved (stars %d)" % _gs.get_stars("m1_launch"))
	_check(await _click_text("BTN_NEXT"), "M1 results: CLICK Next mission")
	m = await _wait_scene("mission2")
	_check(current_scene.scene_file_path.contains("mission2"), "Next mission opens Mission 2")

	# ============================================================ MISSION 2 (Lunar Expedition)
	_check(await _click_text("BTN_START"), "M2: CLICK Start mission")
	await _frames(40)
	_check(m.state == m.S.DESIGN and m.design_view != null, "M2: mission design lab is open")
	_check(await _click_text("LUN_CONTINUE"), "M2: CLICK Continue to verification")
	await _frames(40)
	_check(m.state == m.S.REVIEW, "M2: verification (design review) window is open")
	_check(await _click_text("REV_LAUNCH"), "M2: CLICK Approve and launch")
	await _frames(40)
	_check(m.state == m.S.LAUNCH, "M2: launch sequence started")
	_check(await _wait_state(m, m.S.TRANSFER, 1500), "M2: launch finished, transfer planning open")
	m._tli_slider.value = LunarDesign.ideal_tli_dv()
	await _frames(5)
	_check(m.tli_dv > 3100.0 and LunarDesign.tli_outcome(m.tli_dv) == 0, "M2: planner shows a clean-intercept burn")
	_check(await _click_text("LUN_TLI_EXEC"), "M2: CLICK Execute burn")
	_check(await _wait_state(m, m.S.DESCENT, 1500), "M2: Moon intercepted, descent started")
	await _frames(60)
	await _check_inspect_lunar(m)
	await _test_pause_lunar(m)
	var ok2 := await _fly_lunar_descent(m)
	_check(ok2 and m.lm.landed, "M2: lander touched down safely (keyboard pilot, %s)" % m.lm.outcome)
	await _frames(30)
	_check(m.state == m.S.SURFACE, "M2: surface operations started")
	var ok2b := await _drive_rover(m)
	_check(ok2b and m.r_samples == 3, "M2: rover collected %d / 3 samples (keyboard, E key)" % m.r_samples)
	_release_all()
	await _key(KEY_ENTER)
	_check(await _wait_result(m, 1500), "M2: data uplinked, results window shown")
	_check(_gs.is_completed("m2_lunar"), "M2: progress saved")
	_check(await _click_text("BTN_NEXT"), "M2 results: CLICK Next mission")
	m = await _wait_scene("mission3")
	_check(current_scene.scene_file_path.contains("mission3"), "Next mission opens Mission 3")

	# ============================================================ MISSION 3
	_check(await _click_text("BTN_START"), "M3: CLICK Start mission")
	await _frames(40)
	_check(m.design_view != null, "M3: cargo design lab is open")
	_check(await _click_text("LUN_CONTINUE"), "M3: CLICK Continue to verification")
	await _frames(40)
	_check(await _click_text("REV_LAUNCH"), "M3: CLICK Approve and launch")
	await _frames(1000)
	_check(m.started, "M3: launch done, docking phase running")
	await _fly_m3_some(m, 900)
	await _check_inspect_vehicle(m, "M3")
	var ok3 := await _fly_m3(m)
	_check(ok3, "M3: docked with the station (keyboard pilot)")
	_release_all()
	_check(_gs.is_completed("m3_docking"), "M3: progress saved")
	_check(await _click_text("BTN_MISSIONS"), "M3 results: CLICK Mission select")
	m = await _wait_scene("mission_select")
	_check(current_scene.scene_file_path.contains("mission_select"), "Mission select reopened after M3")

	# ============================================================ SAVE FILE
	var cfg := ConfigFile.new()
	var err := cfg.load("user://zenith_test_save.cfg")
	var saved: Dictionary = JSON.parse_string(str(cfg.get_value("progress", "data", "{}")))
	_check(err == OK and saved.has("m1_launch") and saved.has("m2_lunar") and saved.has("m3_docking"), "save file on disk contains all 3 missions")

	# ============================================================ LOSS / RETRY / PLAY
	await _test_loss_retry()
	_gs.progress.clear()
	_router.play()
	m = await _wait_scene("mission1")
	_check(current_scene.scene_file_path.contains("mission1"), "Play with no progress starts Mission 1")

	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)


func _collect_buttons(node: Node, text: String, out: Array) -> void:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		out.append(node)
	for c in node.get_children():
		_collect_buttons(c, text, out)


# ---------------------------------------------------------------- camera / pause --
func _check_inspect_m1(m: Node) -> void:
	var o: OrbitCameraController = m.pad_scene.orbit
	var cam: Camera3D = m.pad_scene.camera
	# without C the mouse must not move the camera (no conflict with flying)
	var c0 := cam.global_position
	await _drag(MOUSE_BUTTON_LEFT, Vector2(200, 0))
	_check(not o.engaged, "M1: LMB drag does nothing during flight until C is pressed")
	await _key(KEY_C)
	await _frames(5)
	_check(m.inspecting and o.engaged, "M1: C turns the free camera ON")
	var snap := [m.model.r, m.model.vr, m.model.vt, m.model.pitch, m.model.fuel, m.model.time]
	var camp := cam.global_position
	await _drag(MOUSE_BUTTON_LEFT, Vector2(300, 60))
	_btn(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(640, 360))
	_btn(MOUSE_BUTTON_WHEEL_DOWN, false, Vector2(640, 360))
	await _drag(MOUSE_BUTTON_RIGHT, Vector2(80, 20))
	await _frames(30)
	_check(cam.global_position.distance_to(camp) > 3.0, "M1 inspect: real mouse moved the camera %.0f m" % cam.global_position.distance_to(camp))
	_check(snap[0] == m.model.r and snap[1] == m.model.vr and snap[2] == m.model.vt and snap[3] == m.model.pitch
		and snap[4] == m.model.fuel and snap[5] == m.model.time, "M1 inspect: rocket position / velocity / fuel / time UNCHANGED")
	await _key(KEY_C)
	await _frames(60)
	_check(not m.inspecting and not o.engaged, "M1: C turns the free camera OFF and the flight continues")
	var r0: float = m.model.r
	await _frames(40)
	_check(absf(m.model.r - r0) > 0.01, "M1: simulation runs again")


func _check_inspect_vehicle(m: Node, tag: String) -> void:
	var o: OrbitCameraController = m.view.orbit
	var cam: Camera3D = m.view.camera
	var w = m.world
	await _drag(MOUSE_BUTTON_LEFT, Vector2(200, 0))
	_check(not o.engaged, "%s: LMB drag does nothing during play until C is pressed" % tag)
	await _key(KEY_C)
	await _frames(5)
	_check(m.inspecting, "%s: C turns the free camera ON" % tag)
	var p1: Vector2 = w.pos
	var v1: Vector2 = w.vel
	var f1: float = w.fuel
	var camp := cam.global_position
	await _drag(MOUSE_BUTTON_LEFT, Vector2(300, -70))
	_btn(MOUSE_BUTTON_WHEEL_UP, true, Vector2(640, 360))
	_btn(MOUSE_BUTTON_WHEEL_UP, false, Vector2(640, 360))
	await _frames(30)
	_check(cam.global_position.distance_to(camp) > 1.0, "%s inspect: real mouse moved the camera" % tag)
	_check(w.pos == p1 and w.vel == v1 and w.fuel == f1, "%s inspect: vehicle position / velocity / fuel UNCHANGED" % tag)
	await _key(KEY_R)
	await _frames(40)
	_check(not m.inspecting, "%s: R leaves the free camera and resumes" % tag)


func _test_pause(m: Node, tag: String) -> void:
	await _key(KEY_ESCAPE)
	await _frames(5)
	_check(paused and m.pause_menu.visible, "%s: ESC opens the pause menu" % tag)
	var p0: Vector2 = m.world.pos
	await _frames(30)
	_check(m.world.pos == p0, "%s: game is frozen while paused" % tag)
	_check(await _click_text("BTN_RESUME"), "%s: CLICK Resume" % tag)
	await _frames(5)
	_check(not paused and not m.pause_menu.visible, "%s: pause closed" % tag)


# ------------------------------------------------------------------- pilots ------
func _fly_m1(m: Node) -> bool:
	var staged := false
	var fair_done := false
	var phase := 0
	var warp2 := false
	var warp3 := false
	var deployed := false
	var frames := 0
	while frames < 90000 and not _has_result(m):
		frames += 1
		await process_frame
		if m.state != m.S.FLIGHT:
			continue
		var model = m.model
		var h: float = model.altitude()
		var o: Dictionary = model.orbit()
		var ap: float = minf(float(o["ap"]), 1.0e9)
		if not warp2 and h > 800.0:
			warp2 = true
			await _key(KEY_2)
		if not warp3 and h > 31000.0:
			warp3 = true
			await _key(KEY_3)
		if phase == 0 and ap >= 115000.0:
			phase = 1
			await _key(KEY_X)
		elif phase == 1 and model.vr < 15.0:
			phase = 2
			await _key(KEY_Z)
		# throttle in thick air: Max-Q guard
		if phase == 0:
			if model.q > 0.8 * 50000.0:
				_hold(KEY_S, true)
			else:
				_hold(KEY_S, false)
				if model.throttle < 0.98:
					_hold(KEY_Z, true)
				else:
					_hold(KEY_Z, false)
		else:
			_hold(KEY_S, false)
		var des := 0.0
		if phase == 0:
			des = 0.0 if h < 600.0 else 90.0 * minf(1.0, pow((h - 600.0) / 60000.0, 0.5))
		elif phase == 1:
			des = 90.0
		else:
			des = 90.0 + clampf(model.vr * 0.25, -10.0, 40.0)
		var cur := rad_to_deg(model.pitch)
		_hold(KEY_D, cur < des - 1.2)
		_hold(KEY_A, cur > des + 1.2)
		if model.has_upper and model.stage == 1 and model.fuel <= 1.0 and not staged:
			staged = true
			await _key(KEY_G)
			await _frames(5)
			_check(model.stage == 2 and m.flight._spent.size() > 0, "M1: G separates stage 1 (stage -> 2, spent stage drifting away in 3D)")
		if model.fairing_on and h >= 95000.0 and not fair_done:
			fair_done = true
			await _key(KEY_F)
			_check(not model.fairing_on and not model.fairing_early, "M1: F jettisons the fairing above 85 km without damage")
		if model.in_stable_orbit() and not deployed:
			deployed = true
			_release_all()
			await _key(KEY_X)
			await _key(KEY_SPACE)
	_release_all()
	return await _wait_result(m, 4000)


func _keys_for_dir(dir: Vector2) -> void:
	_hold(KEY_D, dir.x > 0.35)
	_hold(KEY_A, dir.x < -0.35)
	_hold(KEY_S, dir.y > 0.35)
	_hold(KEY_W, dir.y < -0.35)


func _wait_state(m: Node, st: int, limit: int) -> bool:
	for i in limit:
		if m.state == st:
			return true
		await process_frame
	return m.state == st


func _check_inspect_lunar(m: Node) -> void:
	var o: OrbitCameraController = m.moon.orbit
	var cam: Camera3D = m.moon.camera
	await _drag(MOUSE_BUTTON_LEFT, Vector2(200, 0))
	_check(not o.engaged, "M2: LMB drag does nothing during the landing until C is pressed")
	await _key(KEY_C)
	await _frames(5)
	_check(m.inspecting, "M2: C turns the free camera ON")
	var p1: Vector2 = m.lm.pos
	var v1: Vector2 = m.lm.vel
	var f1: float = m.lm.fuel
	var camp := cam.global_position
	await _drag(MOUSE_BUTTON_LEFT, Vector2(300, -70))
	await _frames(30)
	_check(cam.global_position.distance_to(camp) > 1.0, "M2 inspect: real mouse moved the camera")
	_check(m.lm.pos == p1 and m.lm.vel == v1 and m.lm.fuel == f1, "M2 inspect: lander position / velocity / fuel UNCHANGED")
	await _key(KEY_R)
	await _frames(40)
	_check(not m.inspecting, "M2: R leaves the free camera and resumes")


func _test_pause_lunar(m: Node) -> void:
	await _key(KEY_ESCAPE)
	await _frames(5)
	_check(paused and m.pause_menu.visible, "M2: ESC opens the pause menu")
	var p0: Vector2 = m.lm.pos
	await _frames(30)
	_check(m.lm.pos == p0, "M2: game is frozen while paused")
	_check(await _click_text("BTN_RESUME"), "M2: CLICK Resume")
	await _frames(5)
	_check(not paused and not m.pause_menu.visible, "M2: pause closed")


func _fly_lunar_descent(m: Node) -> bool:
	var frames := 0
	while frames < 30000 and m.state == m.S.DESCENT:
		frames += 1
		await process_frame
		if m.inspecting:
			continue
		var c: Vector2 = m._lander_autopilot()
		_hold(KEY_W, c.x > m.lm.throttle + 0.04)
		_hold(KEY_S, c.x < m.lm.throttle - 0.04)
		_hold(KEY_D, c.y > 0.3)
		_hold(KEY_A, c.y < -0.3)
	_release_all()
	return m.state != m.S.DESCENT and m.lm.landed


func _drive_rover(m: Node) -> bool:
	var frames := 0
	while frames < 30000 and m.state == m.S.SURFACE and m.r_samples < 3:
		frames += 1
		await process_frame
		var c: Vector2 = m._rover_autopilot(false)
		_hold(KEY_W, c.x > 0.3)
		_hold(KEY_S, c.x < -0.3)
		_hold(KEY_D, c.y > 0.3)
		_hold(KEY_A, c.y < -0.3)
		var i: int = m._next_poi()
		if i >= 0 and m._sampling < 0 and m.r_pos.distance_to(m.moon.pois[i]) < 4.0 and absf(m.r_speed) < 0.4:
			_release_all()
			await _key(KEY_E)
	_release_all()
	return m.r_samples == 3


func _fly_m3_some(m: Node, n: int) -> void:
	for i in n:
		await process_frame
		_keys_m3(m)


func _keys_m3(m: Node) -> void:
	var a: Array = m._autopilot()
	_hold(KEY_W, float(a[0]) > 0.3)
	_hold(KEY_S, float(a[0]) < -0.3)
	_hold(KEY_E, float(a[1]) > 0.3)
	_hold(KEY_Q, float(a[1]) < -0.3)
	_hold(KEY_D, float(a[2]) > 0.3)
	_hold(KEY_A, float(a[2]) < -0.3)
	_hold(KEY_SHIFT, m.world.axial_distance() < 40.0)


func _fly_m3(m: Node) -> bool:
	var frames := 0
	while frames < 60000 and not _has_result(m):
		frames += 1
		await process_frame
		if m.inspecting:
			continue
		_keys_m3(m)
	_release_all()
	return await _wait_result(m, 400)


# -------------------------------------------------------------- loss + restart -----
func _test_loss_retry() -> void:
	# --- Mission 2 loss: wrong trans-lunar burn (miss the Moon), then Retry
	_router.go_to("res://Missions/Mission2/mission2.tscn")
	var m := await _wait_scene("mission2")
	await _click_text("BTN_START")
	await _frames(40)
	m.dev_auto_design()
	m._on_launch()
	await _wait_state(m, m.S.TRANSFER, 1500)
	m._tli_slider.value = 3010.0
	await _frames(5)
	await _click_text("LUN_TLI_EXEC")
	var got := await _wait_result(m, 1500)
	_check(got, "M2 loss: a wrong trans-lunar burn (miss) shows the result window")
	var title_fail := false
	for c in m.overlay.get_children():
		if c.has_method("show_result"):
			title_fail = _find_btn(c, "BTN_RETRY") != null
	_check(title_fail, "M2 loss: result window offers Retry")
	var before := m.get_instance_id()
	await _click_text("BTN_RETRY")
	m = await _wait_scene("mission2")
	_check(m.get_instance_id() != before and not m.ended, "M2: CLICK Retry reloads a fresh mission")
	# --- pause menu: restart + main menu
	await _click_text("BTN_START")
	await _frames(40)
	await _key(KEY_ESCAPE)
	await _frames(5)
	before = m.get_instance_id()
	await _click_text("BTN_RESTART")
	m = await _wait_scene("mission2")
	_check(m.get_instance_id() != before, "M2: pause menu -> Restart reloads the mission")
	await _click_text("BTN_START")
	await _frames(40)
	await _key(KEY_ESCAPE)
	await _frames(5)
	await _click_text("BTN_MAIN_MENU")
	await _wait_scene("temp_main_menu")
	_check(current_scene.scene_file_path.contains("temp_main_menu") and not paused, "pause menu -> Main menu works and un-pauses")
	# --- Mission 1 loss: no fuel
	_router.go_to("res://Missions/Mission1/mission1.tscn")
	m = await _wait_scene("mission1")
	m.dev_skip_briefing()
	await _frames(10)
	m.dev_quick("kestrel/l/aero")
	await _frames(60)
	m.model.fuel = 0.0
	got = await _wait_result(m, 1500)
	_check(got, "M1 loss: out of fuel before orbit shows the result window")
	# --- language: scan visible texts for missing translations (EN + UK)
	for loc in ["en", "uk"]:
		_gs.settings["locale"] = loc
		_gs.apply_settings()
		for scene in ["res://Menus/TempMenu/temp_main_menu.tscn", "res://Menus/TempMenu/mission_select.tscn", "res://Menus/TempMenu/settings.tscn",
				"res://Missions/Mission1/mission1.tscn", "res://Missions/Mission2/mission2.tscn", "res://Missions/Mission3/mission3.tscn"]:
			_router.go_to(scene)
			await _wait_scene(scene.get_file().get_basename())
			var bad: Array[String] = []
			_scan_missing(root, bad)
			_check(bad.is_empty(), "locale %s: %s has no untranslated texts %s" % [loc, scene.get_file(), str(bad)])
	_gs.settings["locale"] = "en"
	_gs.apply_settings()


func _scan_missing(node: Node, out: Array[String]) -> void:
	if (node is Label or node is Button) and (node as Control).is_visible_in_tree():
		var t: String = node.text
		if t.length() > 3 and t == t.to_upper() and "_" in t and not " " in t and tr(t) == t:
			out.append(t)
	for c in node.get_children():
		_scan_missing(c, out)
