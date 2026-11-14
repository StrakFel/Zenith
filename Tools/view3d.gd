extends Node3D
## Developer scene: shows the pad + rocket from a configurable camera (used by Tools/run_shot.ps1).
## Env vars: ZENITH_VIEW_ALT (m), ZENITH_VIEW_DOWN (camera pitch down, deg)

var scene: PadScene3D


func _ready() -> void:
	scene = PadScene3D.new()
	add_child(scene)
	scene.stage.set_look("dawn")
	scene.set_build({"nose": "aero", "tank": "l", "engine": "kestrel"}, false)
	var alt := float(ProjectSettings.get_setting("zenith/view_alt", 0.0))
	var down := float(ProjectSettings.get_setting("zenith/view_down", 0.0))
	scene.set_flight(alt, 0.0, 0.0)
	scene.camera.fov = 40.0
	if alt > 0.0:
		scene.camera.position = Vector3(60, 50, 110)
		var d := Vector3(-0.4, -tan(deg_to_rad(down)), -0.9).normalized()
		scene.camera.look_at(scene.camera.position + d * 100.0)
	else:
		scene.camera.position = Vector3(26, 6, 44)
		scene.camera.look_at(Vector3(0, 24, 0))
