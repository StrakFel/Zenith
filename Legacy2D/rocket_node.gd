class_name RocketNode
extends Node2D
## The player's rocket in the flight view: art + engine plume (particles) + smoke trail.
## The node origin is the rocket's centre; rotation = pitch.

var build: Dictionary = {}
var throttle := 0.0:
	set(v):
		throttle = v
		queue_redraw()
var show_nose := true
var damaged := 0.0   # 0..1, drives a flicker of sparks/smoke

var _plume: CPUParticles2D
var _smoke: CPUParticles2D
var _half := 100.0
var _t := 0.0


static var _soft: GradientTexture2D


## Soft round sprite shared by all particle systems (flames, smoke, explosion).
static func soft_texture() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


func setup(b: Dictionary) -> void:
	build = b
	_half = RocketDrawer.height_of(b) * 0.5
	_make_particles()
	queue_redraw()


func half_height() -> float:
	return _half


func _make_particles() -> void:
	_plume = CPUParticles2D.new()
	_plume.amount = 120
	_plume.lifetime = 0.55
	_plume.direction = Vector2(0, 1)
	_plume.spread = 7.0
	_plume.initial_velocity_min = 260.0
	_plume.initial_velocity_max = 380.0
	_plume.texture = soft_texture()
	_plume.scale_amount_min = 0.25
	_plume.scale_amount_max = 0.55
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.15))
	_plume.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 0.95))
	g.set_color(1, Color(1.0, 0.25, 0.0, 0.0))
	g.add_point(0.35, Color(1.0, 0.6, 0.12, 0.8))
	_plume.color_ramp = g
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_plume.material = mat
	_plume.local_coords = true
	_plume.emitting = false
	_plume.position = Vector2(0, _half - 4.0)
	_plume.show_behind_parent = true
	add_child(_plume)

	_smoke = CPUParticles2D.new()
	_smoke.amount = 70
	_smoke.lifetime = 3.2
	_smoke.direction = Vector2(0, 1)
	_smoke.spread = 14.0
	_smoke.initial_velocity_min = 30.0
	_smoke.initial_velocity_max = 90.0
	_smoke.texture = soft_texture()
	_smoke.scale_amount_min = 0.4
	_smoke.scale_amount_max = 0.9
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.8))
	_smoke.scale_amount_curve = sc
	var sg := Gradient.new()
	sg.set_color(0, Color(0.85, 0.85, 0.9, 0.5))
	sg.set_color(1, Color(0.5, 0.52, 0.6, 0.0))
	_smoke.color_ramp = sg
	_smoke.local_coords = false
	_smoke.emitting = false
	_smoke.position = Vector2(0, _half - 2.0)
	_smoke.show_behind_parent = true
	add_child(_smoke)


## smoke_drift: screen-space velocity the smoke should be pushed with (opposite to travel).
func update_fx(thr: float, smoke_amount: float, smoke_drift: Vector2) -> void:
	throttle = thr
	if _plume == null:
		return
	_plume.emitting = thr > 0.02
	_plume.initial_velocity_min = 200.0 + 160.0 * thr
	_plume.initial_velocity_max = 300.0 + 200.0 * thr
	_smoke.emitting = thr > 0.02 and smoke_amount > 0.02
	_smoke.gravity = smoke_drift
	_smoke.modulate.a = clampf(smoke_amount, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if build.is_empty():
		return
	draw_set_transform(Vector2(0, _half), 0.0, Vector2.ONE)
	# flame glow body
	if throttle > 0.02:
		var fl := 70.0 * throttle * (0.88 + 0.12 * sin(_t * 47.0))
		var w := 20.0 + 6.0 * throttle
		draw_colored_polygon(PackedVector2Array([
			Vector2(-w, -2), Vector2(w, -2), Vector2(w * 0.4, fl * 0.7), Vector2(0, fl * 1.25), Vector2(-w * 0.4, fl * 0.7)]),
			Color(1.0, 0.5, 0.1, 0.55))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-w * 0.5, -2), Vector2(w * 0.5, -2), Vector2(0, fl * 0.8)]), Color(1.0, 0.95, 0.75, 0.85))
		for i in 4:
			draw_circle(Vector2(0, 8 + i * 4), 34.0 - i * 5.0, Color(1.0, 0.55, 0.15, 0.035 * throttle))
	RocketDrawer.draw_rocket(self, build, 1.0, show_nose)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if damaged > 0.0 and fmod(_t, 0.25) < 0.12:
		draw_circle(Vector2(randf_range(-14, 14), randf_range(-_half, _half)), randf_range(3, 7), Color(1.0, 0.7, 0.2, 0.9 * damaged))
