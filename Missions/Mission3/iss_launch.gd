extends "res://Missions/Mission1/mission1.gd"
## Mission 3 - ISS Expedition, phase 1: design the science cargo and the rocket that carries it, launch into the station's
## orbit. Phase 2 is the rendezvous and docking (Missions/Mission3/mission3.gd) with the cargo and fuel that were designed here.


func _init() -> void:
	super._init()
	_setup_profile("m3")
	M1Parts.active_required_dv = LaunchProfiles.required_dv("m3")
