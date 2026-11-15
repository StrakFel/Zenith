extends SceneTree
## AudioManager test: buses, mood switching per scene, crossfade without double playback, seamless loop, pause ducking, settings.
##   Godot --headless --fixed-fps 60 --path . --script res://Tools/audio_test.gd --quit-after 6000
var _fail := 0
var _am: Node
var _gs: Node

const SCENES := ["res://Missions/Mission1/mission1.tscn", "res://Missions/Mission2/space_ops.tscn", "res://Missions/Mission3/iss_launch.tscn",
	"res://Missions/Mission4/constellation_launch.tscn", "res://Missions/Mission5/moon_launch.tscn"]


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _loud() -> int:
	var n := 0
	for p in _am._players:
		if p.playing and p.volume_db > -30.0:
			n += 1
	return n


func _run() -> void:
	await _frames(5)
	_am = root.get_node("AudioManager")
	_gs = root.get_node("GameState")
	_gs.settings["music_on"] = true
	_gs.settings["music_volume"] = 0.7
	_gs.settings["sfx_volume"] = 0.8
	_gs.settings["unlock_all"] = true
	_gs.apply_settings()
	_gs.settings_changed.emit()
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "Music and SFX buses exist")
	change_scene_to_file("res://Menus/TempMenu/temp_main_menu.tscn")
	await _frames(40)
	_check(_am.mood == "calm" and _am._active.playing, "main menu: calm music is playing (%s)" % _am.mood)
	var menu_stream: Resource = _am._active.stream
	change_scene_to_file("res://Menus/TempMenu/settings.tscn")
	await _frames(40)
	_check(_am._active.stream == menu_stream and _am._active.playing, "scene change does not restart or swap the music")
	# every mission: calm in the briefing, action when the mission phase runs
	for sp in SCENES:
		change_scene_to_file(sp)
		await _frames(40)
		var m := current_scene
		_check(m.has_method("music_mood") and str(m.music_mood()) == "calm", "%s: calm music in the briefing" % sp.get_file())
	change_scene_to_file(SCENES[0])
	await _frames(30)
	var m1 := current_scene
	m1.dev_skip_briefing()
	m1._on_design_done({"goal": "earth", "instrument": "img_s", "solar": "m", "battery": "m", "comm": "x"})
	await _frames(40)
	_check(_am.mood == "calm", "rocket designer: calm music")
	m1.dev_quick("kestrel/m/aero/u_s")
	await _frames(40)
	_check(str(m1.music_mood()) == "action", "launch: mission asks for the energetic track")
	await _frames(30)
	_check(_am.mood == "action" and _am._active.playing, "launch: action music is playing")
	await _frames(150)
	_check(_loud() == 1, "crossfade finished: one loud track only (%d)" % _loud())
	# pause ducking
	paused = true
	await _frames(60)
	_check(_am._active.playing and _am._duck < -5.0, "pause: music continues, ducked (%.1f dB)" % _am._duck)
	paused = false
	await _frames(60)
	# seamless loop: jump close to the end of the track
	var len: float = _am._active.stream.get_length()
	_am._active.seek(len - 1.5)
	await _frames(30)
	var both := 0
	for p in _am._players:
		if p.playing:
			both += 1
	_check(both == 2 and _am._active.get_playback_position() < 5.0, "loop: the track crossfades into itself before it ends")
	await _frames(240)
	_check(_loud() == 1 and _am._active.playing, "loop: single track playing again after the crossfade")
	# settings
	_gs.set_setting("music_on", false)
	await _frames(5)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and not _am._active.playing, "Music off: bus muted, playback stopped")
	_gs.set_setting("music_on", true)
	await _frames(40)
	_check(_am._active.playing and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Music on: resumes")
	_gs.set_setting("music_volume", 0.3)
	_gs.set_setting("sfx_volume", 0.5)
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.3)) < 0.1, "music volume slider changes the Music bus")
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.5)) < 0.1, "SFX slider changes the SFX bus")
	var cfg := ConfigFile.new()
	cfg.load(_gs.save_path)
	_check(is_equal_approx(float(cfg.get_value("settings", "music_volume", -1.0)), 0.3), "settings are saved to disk")
	_gs.settings["music_volume"] = 0.7
	_gs.settings["sfx_volume"] = 0.8
	_gs.settings["unlock_all"] = false
	_gs.save_game()
	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
