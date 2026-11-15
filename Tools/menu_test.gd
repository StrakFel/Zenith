extends SceneTree
## Team main menu (GameMenu/MainMenu) wired to the Router: Play / Missions / Settings / Exit buttons and the way back.
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/menu_test.gd --quit-after 6000
var _fail := 0
var _router: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_scene(part: String) -> Node:
	var n := 0
	while (current_scene == null or not current_scene.scene_file_path.contains(part)) and n < 2000:
		await process_frame
		n += 1
	for i in 200:
		if not _router._busy:
			break
		await process_frame
	await _frames(20)
	return current_scene


func _open_menu() -> Node:
	_router.go_to(_router.MAIN_MENU)
	return await _wait_scene("main_menu")


func _run() -> void:
	await _frames(5)
	_router = root.get_node("Router")
	root.get_node("GameState").progress.clear()
	_check(str(ProjectSettings.get_setting("application/run/main_scene")).begins_with("uid://"), "project starts with the team menu scene (uid main scene)")
	_check(_router.MAIN_MENU == "res://GameMenu/MainMenu/main_menu.tscn", "Router.MAIN_MENU is the team menu")
	var m := await _open_menu()
	for nm in ["Play", "Missions", "Settings", "Exit"]:
		_check(m.get_node_or_null(nm) is Button, "team menu has the %s button" % nm)
	m.get_node("Missions")._pressed()
	await _wait_scene("mission_select")
	_check(current_scene.scene_file_path.contains("mission_select"), "Missions opens the 3D mission list")
	m = await _open_menu()
	m.get_node("Settings")._pressed()
	await _wait_scene("settings")
	_check(current_scene.scene_file_path.contains("settings"), "Settings opens the settings screen")
	# back from our screens returns to the team menu
	for b in current_scene.find_children("*", "Button", true, false):
		if (b as Button).text == "BTN_BACK":
			(b as Button).pressed.emit()
			break
	await _wait_scene("main_menu")
	_check(current_scene.scene_file_path.contains("GameMenu/MainMenu/main_menu"), "Back from Settings returns to the team menu")
	m = current_scene
	m.get_node("Play")._pressed()
	await _wait_scene("mission1")
	_check(current_scene.scene_file_path.contains("mission1"), "Play starts Mission 1 (no progress yet)")
	await _frames(60)
	_check(root.get_node("AudioManager")._active.playing, "music keeps playing across the transitions")
	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
