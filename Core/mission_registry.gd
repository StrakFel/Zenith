class_name MissionRegistry
extends RefCounted
## Single list of all missions. To add mission 4/5: set "available": true and
## point "scene" at the new mission scene (which extends MissionBase).

const MISSIONS: Array[Dictionary] = [
	{"id": "m1_launch", "title": "M1_TITLE", "desc": "M1_DESC",
		"scene": "res://Missions/Mission1/mission1.tscn", "available": true, "difficulty": 2, "skill": "MS_M1_SKILL"},
	{"id": "m2_spacewalk", "title": "M2_TITLE", "desc": "M2_DESC",
		"scene": "res://Missions/Mission2/mission2.tscn", "available": true, "difficulty": 3, "skill": "MS_M2_SKILL"},
	{"id": "m3_docking", "title": "M3_TITLE", "desc": "M3_DESC",
		"scene": "res://Missions/Mission3/mission3.tscn", "available": true, "difficulty": 4, "skill": "MS_M3_SKILL"},
	{"id": "m4_lunar", "title": "M4_TITLE", "desc": "M4_DESC",
		"scene": "", "available": false, "difficulty": 4, "skill": "MS_M4_SKILL"},
	{"id": "m5_deep", "title": "M5_TITLE", "desc": "M5_DESC",
		"scene": "", "available": false, "difficulty": 5, "skill": "MS_M5_SKILL"},
]


static func all() -> Array[Dictionary]:
	return MISSIONS


static func find(id: String) -> Dictionary:
	for m in MISSIONS:
		if m["id"] == id:
			return m
	return {}


static func index_of(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i]["id"] == id:
			return i
	return -1


static func is_available(id: String) -> bool:
	return bool(find(id).get("available", false))


## A mission is playable when implemented and the previous one is completed
## (or the "unlock all" demo switch is on in Settings).
static func is_unlocked(id: String) -> bool:
	if not is_available(id):
		return false
	if bool(GameState.settings["unlock_all"]):
		return true
	var i := index_of(id)
	if i <= 0:
		return true
	return GameState.is_completed(MISSIONS[i - 1]["id"])


## Last implemented mission the player may start (used by Play when everything is done).
static func last_playable_id() -> String:
	var best := MISSIONS[0]["id"]
	for m in MISSIONS:
		if is_unlocked(str(m["id"])):
			best = m["id"]
	return str(best)


static func next_of(id: String) -> Dictionary:
	var i := index_of(id)
	if i >= 0 and i + 1 < MISSIONS.size():
		return MISSIONS[i + 1]
	return {}

