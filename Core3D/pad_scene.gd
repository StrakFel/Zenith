class_name PadScene3D
extends Node3D
## SpaceStage + launch pad + rocket, with the rocket's centre fixed at a constant place
## above the pad. In flight the planet (and the pad that rides on it) moves instead.

var stage: SpaceStage
var pad: LaunchPad3D
var rocket_pivot: Node3D
var rocket: Rocket3D
var camera: Camera3D
var orbit: OrbitCameraController
var tower_marker: Marker3D


func _init() -> void:
	stage = SpaceStage.new()
	pad = LaunchPad3D.new()
	rocket_pivot = Node3D.new()
	rocket = Rocket3D.new()
	camera = Camera3D.new()


func _ready() -> void:
	add_child(stage)
	stage.ground_anchor.add_child(pad)
	add_child(rocket_pivot)
	rocket_pivot.add_child(rocket)
	camera.far = 6_000_000.0
	camera.near = 0.4
	camera.fov = 45.0
	add_child(camera)
	camera.make_current()
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.ground = pad
	orbit.max_dist = 4_000_000.0
	orbit.min_dist = 6.0
	tower_marker = Marker3D.new()
	tower_marker.position = Vector3(-15, 36, 0)
	pad.add_child(tower_marker)
	orbit.add_focusable(rocket_pivot, 30.0, 100.0)
	orbit.add_focusable(tower_marker, 40.0, 110.0)
	orbit.add_focusable(stage.planet_pivot, SpaceStage.R, 3_600_000.0)
	orbit.add_obstacle(rocket_pivot, 5.0, 28.0)
	orbit.add_obstacle(tower_marker, 6.5, 36.0)
	orbit.add_obstacle(stage.planet_pivot, SpaceStage.R * 1.0)
	set_build(rocket.build, false)


func set_build(b: Dictionary, ghosts: bool) -> void:
	rocket.set_build(b, ghosts)
	rocket_pivot.position = Vector3(0, rocket.total_height() * 0.5 + LaunchPad3D.MOUNT_H, 0)


## Altitude of the rocket base above the pad (m), downrange angle, pitch from vertical.
func set_flight(h: float, theta: float, pitch: float) -> void:
	stage.set_flight(h, theta)
	rocket_pivot.rotation.z = -pitch

