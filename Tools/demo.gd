extends SceneTree
## Watchable demo: plays the whole game by itself in a real window.
## Menu -> mission select -> Mission 1 (build, launch, orbit, deploy) -> Mission 2 -> Mission 3.
##   Godot --path . --resolution 1280x720 --script res://Tools/demo.gd

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		Engine.time_scale = float(a[0])   # e.g. 6 for a fast headless dry run
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _wait_scene(path_part: String) -> Node:
	while current_scene == null or not current_scene.scene_file_path.contains(path_part):
		await process_frame
	await _wait(0.8)
	return current_scene


func _wait_result(m: Node, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		for c in m.overlay.get_children():
			if c.has_method("show_result"):
				return true
		await process_frame
		t += 0.016
	return false


func _run() -> void:
	await _wait(1.0)
	change_scene_to_file("res://Menus/TempMenu/temp_main_menu.tscn")
	await _wait(6.0)
	root.get_node("Router").go_to("res://Menus/TempMenu/mission_select.tscn")
	await _wait(5.0)

	# ---------------------------------------------------------- mission 1
	root.get_node("Router").start_mission("m1_launch")
	var m: Node = await _wait_scene("mission1")
	await _wait(5.0)                       # briefing on screen
	m.dev_skip_briefing()
	await _wait(4.0)                       # mission design screen: goal + satellite
	m.design_view._on_goal("space")        # show another goal and its requirements
	await _wait(3.0)
	m.design_view._on_goal("earth")
	await _wait(2.0)
	var cards: Array = m.design_view._sat_box.get_children()
	cards[14].button_pressed = true        # faster Ka-band antenna
	cards[14].pressed.emit()
	await _wait(3.5)
	m.design_view.design_done.emit(m.design_view.design.duplicate())
	await _wait(3.0)                       # rocket assembly in 3D
	for step in [["engine", "kestrel"], ["tank", "l"], ["nose", "aero"]]:
		m.assembly._on_install(step[0], step[1])
		await _wait(2.2)
	await _wait(1.5)
	m._on_review_request(m.assembly.build.duplicate())   # design review (verification)
	await _wait(6.0)
	m.review.launch_approved.emit()
	m.dev_autopilot = true
	await _wait_result(m, 900.0)
	await _wait(6.0)

	# ---------------------------------------------------------- mission 2
	root.get_node("Router").start_mission("m2_lunar")
	m = await _wait_scene("mission2")
	await _wait(4.0)
	m.dev_skip_briefing()
	m.dev_autopilot = true
	await _wait_result(m, 400.0)
	await _wait(6.0)

	# ---------------------------------------------------------- mission 3
	root.get_node("Router").start_mission("m3_docking")
	m = await _wait_scene("mission3")
	await _wait(4.0)
	m.dev_skip_briefing()
	m.dev_autopilot = true
	await _wait_result(m, 500.0)
	await _wait(6.0)

	root.get_node("Router").go_to("res://Menus/TempMenu/temp_main_menu.tscn")
	await _wait(5.0)
	quit()




