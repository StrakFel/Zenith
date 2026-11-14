class_name MenuBackdrop3D
extends Node3D
## Cinematic dawn launch-pad scene used behind every menu screen. The camera slowly
## orbits the ZENITH rocket; each screen picks its own framing via `view_name`.

const VIEWS := {
	# target, radius, azimuth (deg), elevation (deg), fov, h_offset
	"hero": {"target": Vector3(0, 31, 0), "radius": 112.0, "az": 34.0, "el": -6.0, "fov": 40.0, "h": -15.0},
	"select": {"target": Vector3(0, 20, 0), "radius": 120.0, "az": -38.0, "el": 4.0, "fov": 44.0, "h": 0.0},
	"settings": {"target": Vector3(0, 11, 0), "radius": 36.0, "az": 52.0, "el": -4.0, "fov": 46.0, "h": -7.0},
}

@export var view_name := "hero"

var scene: PadScene3D
var _t := 0.0
var _cur_target := Vector3.ZERO
var _cur_az := 0.0
var _cur_radius := 80.0
var _cur_el := 0.0
var _cur_fov := 40.0
var _cur_h := 0.0
var _dust: GPUParticles3D


func _ready() -> void:
	Sfx.music(true)
	scene = PadScene3D.new()
	add_child(scene)
	scene.stage.set_look("dawn")
	scene.set_build({"nose": "aero", "tank": "l", "engine": "kestrel"}, false)
	var v: Dictionary = VIEWS[view_name]
	_cur_target = v["target"]
	_cur_az = v["az"]
	_cur_radius = v["radius"]
	_cur_el = v["el"]
	_cur_fov = v["fov"]
	_cur_h = v["h"]
	_dust = Fx3D.particles(140, 14.0, 0.5, true, false)
	var pm := Fx3D.pmat(_dust)
	pm.direction = Vector3(0.3, 0.1, -0.2)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(60, 25, 60)
	pm.scale_min = 0.3
	pm.scale_max = 1.0
	pm.color_ramp = Fx3D.gradient_tex(
		[Color(1.0, 0.8, 0.55, 0.0), Color(1.0, 0.82, 0.6, 0.55), Color(1.0, 0.8, 0.55, 0.0)], [0.0, 0.5, 1.0])
	_dust.position = Vector3(0, 18, 0)
	_dust.emitting = true
	_dust.preprocess = 8.0
	add_child(_dust)
	_apply(0.0)


func set_view(name: String) -> void:
	view_name = name


func _process(delta: float) -> void:
	_t += delta
	_apply(delta)


func _apply(delta: float) -> void:
	var v: Dictionary = VIEWS[view_name]
	var k := minf(1.0, delta * 2.0)
	_cur_target = _cur_target.lerp(v["target"], k)
	_cur_radius = lerpf(_cur_radius, float(v["radius"]), k)
	_cur_el = lerpf(_cur_el, float(v["el"]), k)
	_cur_fov = lerpf(_cur_fov, float(v["fov"]), k)
	_cur_h = lerpf(_cur_h, float(v["h"]), k)
	_cur_az = lerpf(_cur_az, float(v["az"]), k)
	var az := deg_to_rad(_cur_az + 9.0 * sin(_t * 0.13) + 4.0 * sin(_t * 0.31))
	var el := deg_to_rad(_cur_el + 1.5 * sin(_t * 0.21))
	var r := _cur_radius * (1.0 + 0.04 * sin(_t * 0.17))
	var cam := scene.camera
	var pos := _cur_target + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * r
	scene.orbit.update(delta, pos, _cur_target + Vector3(0.25 * sin(_t * 0.7), 0.3 * sin(_t * 0.9), 0.0), _cur_fov)
	cam.h_offset = _cur_h



