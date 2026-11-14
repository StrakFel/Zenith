extends SceneTree
## Real-window visual proof of the camera: opens the rocket designer, performs a REAL mouse drag
## (Input.parse_input_event) and saves screenshots before / after rotating and zooming.
##   Godot --path . --resolution 1280x720 --script res://Tools/cam_visual.gd -- C:/temp/prefix

var _prefix := "cam"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_prefix = a[0]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(tag: String) -> void:
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_prefix, tag])
	print("SAVED ", tag)


func _mouse(pos: Vector2, rel: Vector2, mask: int) -> void:
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
	e.button_mask = 1 if pressed else 0
	Input.parse_input_event(e)


func _run() -> void:
	await _frames(10)
	var gs := root.get_node("GameState")
	gs.settings["locale"] = "en"
	gs.apply_settings()
	root.get_node("Router").go_to("res://Missions/Mission1/mission1.tscn")
	await create_timer(2.5).timeout
	var m := current_scene
	m.dev_skip_briefing()
	await _frames(20)
	m._on_design_done(m.design_view.design.duplicate())
	for step in [["engine", "kestrel"], ["tank", "l"], ["nose", "aero"]]:
		m.assembly._on_install(step[0], step[1])
	await create_timer(1.5).timeout
	await _shot("1_before")
	var pos := Vector2(640, 360)
	_mouse(pos, Vector2.ZERO, 0)
	await _frames(3)
	_btn(MOUSE_BUTTON_LEFT, true, pos)
	await _frames(3)
	for i in 20:
		pos += Vector2(14, -3)
		_mouse(pos, Vector2(14, -3), 1)
		await process_frame
	_btn(MOUSE_BUTTON_LEFT, false, pos)
	await create_timer(1.2).timeout
	await _shot("2_rotated_right")
	for i in 6:
		_btn(MOUSE_BUTTON_WHEEL_UP, true, pos)
		_btn(MOUSE_BUTTON_WHEEL_UP, false, pos)
		await _frames(3)
	await create_timer(1.0).timeout
	await _shot("3_zoomed_in")
	var e := InputEventKey.new()
	e.keycode = KEY_R
	e.physical_keycode = KEY_R
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(2.5).timeout
	await _shot("4_after_R")
	print("orbit engaged after R: ", m.pad_scene.orbit.engaged)
	quit()
