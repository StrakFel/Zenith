extends "res://Missions/Mission1/mission1.gd"
## Mission 4 - Satellite Constellation, phase 1: design the constellation (satellite class, count, dispenser) and a heavy
## rocket with strap-on boosters, a core stage and an upper stage; launch into the constellation altitude.
## Phase 2 (Missions/Mission4/mission4_ops.gd) deploys the satellites into evenly spaced slots with the propellant left.


func _init() -> void:
	super._init()
	_setup_profile("m4")
	M1Parts.active_required_dv = LaunchProfiles.required_dv("m4")
