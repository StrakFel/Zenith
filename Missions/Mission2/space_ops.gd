extends "res://Missions/Mission1/mission1.gd"
## Mission 2 - Space Operations. Phase 1: design the EVA equipment package (oxygen, thruster gas, suit) and the rocket that
## delivers it (the shared launch segment, see LaunchProfiles "m2"). Phase 2: the spacewalk repair mission
## (Missions/Spacewalk), whose resources come from the package the player designed and from how well the launch went.


func _init() -> void:
	super._init()
	_setup_profile("m2")
	M1Parts.active_required_dv = LaunchProfiles.required_dv("m2")
