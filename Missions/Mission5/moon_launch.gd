extends "res://Missions/Mission1/mission1.gd"
## Mission 5 - Moon & Return, phase 1: design the whole expedition (lunar lander + rover + science package, return capsule,
## ascent stage) and the heavy launch system (boosters + core + trans-lunar stage) that must reach Earth orbit with enough
## propellant left for the trans-lunar injection. Phase 2 (mission5_ops.gd) flies to the Moon, lands, explores and returns.


func _init() -> void:
	super._init()
	_setup_profile("m5")
	M1Parts.active_required_dv = LaunchProfiles.required_dv("m5")
