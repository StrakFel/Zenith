class_name MissionBase
extends Node
## Base class for every mission scene: overlay layer, pause menu, briefing,
## result screen and progress saving. Missions 4-5 only need to extend this.
##
## Subclass contract:
##   mission_id            - id from MissionRegistry
##   _briefing_data()      - {"title": key, "objectives": [keys], "controls": [[keys, desc_key]]}
##   _on_mission_start()   - called after the player pressed "Start" in the briefing
##   finish(...)           - call once when the mission is won or lost

var mission_id: String = ""
var overlay: CanvasLayer
var pause_menu: PauseMenu
var ended := false


func _ready() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	pause_menu = PauseMenu.new()
	overlay.add_child(pause_menu)
	pause_menu.restart_requested.connect(restart)
	pause_menu.missions_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))
	pause_menu.menu_requested.connect(func(): Router.go_to(Router.MAIN_MENU))
	_build_mission()
	Sfx.music(true)
	_show_briefing()


## Build world, HUD, etc. (called before the briefing is shown).
func _build_mission() -> void:
	pass


func _briefing_data() -> Dictionary:
	return {"title": "", "objectives": [], "controls": []}


func _on_mission_start() -> void:
	pass


func _show_briefing() -> void:
	var d := _briefing_data()
	var b := BriefingPanel.new()
	overlay.add_child(b)
	b.setup(str(d["title"]), d["objectives"], d["controls"])
	b.started.connect(_begin)
	b.back_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))


func _begin() -> void:
	pause_menu.enabled = true
	_on_mission_start()


## Developer/test helper (used by Tools/shot.gd): closes the briefing and starts the mission.
func dev_skip_briefing() -> void:
	for c in overlay.get_children():
		if c is BriefingPanel:
			c.queue_free()
	_begin()


func restart() -> void:
	Router.go_to(get_tree().current_scene.scene_file_path)


func is_active() -> bool:
	return not ended and not get_tree().paused


## stats: Array of [label_key, value_text].
func finish(success: bool, stars: int, score: int, stats: Array, reason_key: String, delay: float = 1.2,
		extra: Dictionary = {}) -> void:
	if ended:
		return
	ended = true
	pause_menu.enabled = false
	if success:
		GameState.record_result(mission_id, stars, score)
	await get_tree().create_timer(delay).timeout
	var r := ResultScreen.new()
	overlay.add_child(r)
	var nxt := MissionRegistry.next_of(mission_id)
	var has_next := not nxt.is_empty() and MissionRegistry.is_unlocked(str(nxt["id"]))
	r.show_result(success, stars, stats, reason_key, has_next, extra)
	r.retry_requested.connect(restart)
	r.missions_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))
	r.next_requested.connect(func(): Router.start_mission(str(nxt["id"])))

