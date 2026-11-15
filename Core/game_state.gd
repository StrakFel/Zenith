extends Node
## Autoload "GameState": settings + mission progress, persisted to user://.

signal settings_changed
signal progress_changed

const SAVE_PATH := "user://zenith_save.cfg"
## Automated tests (godot --script ...) use their own file so they never touch the player's real progress.
const TEST_SAVE_PATH := "user://zenith_test_save.cfg"
var save_path: String = TEST_SAVE_PATH if OS.get_cmdline_args().has("--script") else SAVE_PATH

var settings: Dictionary = {
	"locale": "en",
	"volume": 0.8,
	"fullscreen": false,
	"shake": true,
	"unlock_all": false,
	"sens": 1.0,   # control sensitivity multiplier (0.5 - 1.5)
}
## mission_id -> {"completed": bool, "stars": int, "score": int}
var progress: Dictionary = {}
## Hand-over between the phases of one mission (launch -> operations). Not saved to disk.
var session: Dictionary = {}


func _ready() -> void:
	load_game()
	apply_settings()


# ---------------------------------------------------------------- settings --
func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save_game()
	settings_changed.emit()


func apply_settings() -> void:
	Loc.set_locale(str(settings["locale"]))
	var vol: float = float(settings["volume"])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	var want_full: bool = bool(settings["fullscreen"])
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if want_full != is_full:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)


# ---------------------------------------------------------------- progress --
func get_stars(id: String) -> int:
	if progress.has(id):
		return int((progress[id] as Dictionary).get("stars", 0))
	return 0


func is_completed(id: String) -> bool:
	if progress.has(id):
		return bool((progress[id] as Dictionary).get("completed", false))
	return false


func record_result(id: String, stars: int, score: int) -> void:
	var old: Dictionary = progress.get(id, {})
	progress[id] = {
		"completed": true,
		"stars": maxi(stars, int(old.get("stars", 0))),
		"score": maxi(score, int(old.get("score", 0))),
		"best_prox": int(old.get("best_prox", 0)),
	}
	save_game()
	progress_changed.emit()


## Personal best of "Mission Success Proximity" (0-100 %), kept between sessions. A failed attempt may set it too,
## without marking the mission as completed.
func get_best_prox(id: String) -> int:
	if progress.has(id):
		return int((progress[id] as Dictionary).get("best_prox", 0))
	return 0


func get_best_score(id: String) -> int:
	if progress.has(id):
		return int((progress[id] as Dictionary).get("score", 0))
	return 0


func record_proximity(id: String, percent: int) -> void:
	var old: Dictionary = progress.get(id, {})
	if old.is_empty():
		progress[id] = {"completed": false, "stars": 0, "score": 0, "best_prox": percent}
	else:
		old["best_prox"] = maxi(percent, int(old.get("best_prox", 0)))
		progress[id] = old
	save_game()


func reset_progress() -> void:
	progress.clear()
	save_game()
	progress_changed.emit()


## First unlocked mission that is not completed yet (used by the Play button).
func next_mission_id() -> String:
	for m in MissionRegistry.all():
		var id: String = m["id"]
		if MissionRegistry.is_unlocked(id) and not is_completed(id):
			return id
	return ""


# ------------------------------------------------------------- persistence --
func save_game() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.set_value("progress", "data", JSON.stringify(progress))
	cfg.save(save_path)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	for k in settings:
		settings[k] = cfg.get_value("settings", k, settings[k])
	var raw: Variant = JSON.parse_string(str(cfg.get_value("progress", "data", "{}")))
	if raw is Dictionary:
		progress.clear()
		for id in raw:
			if MissionRegistry.find(str(id)).is_empty():
				continue  # progress of removed / renamed missions
			var e: Dictionary = raw[id]
			progress[id] = {
				"completed": bool(e.get("completed", false)),
				"stars": int(e.get("stars", 0)),
				"score": int(e.get("score", 0)),
				"best_prox": int(e.get("best_prox", 0)),
			}
