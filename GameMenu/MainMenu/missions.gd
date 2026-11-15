extends Button
## "Missions" button of the main menu: opens the 3D mission list (Router).


func _pressed():
	Router.go_to(Router.MISSION_SELECT)
