class_name FlightView
extends Control
## Side-view renderer of the ascent: sky that darkens with altitude, curving
## atmosphere-lit planet, clouds/land sliding with downrange, launch pad, speed
## streaks, rocket + FX. Reads (never writes) the FlightModel.

var model: FlightModel
var rocket: RocketNode
var shake_amp := 0.0
var flash := 0.0
var rocket_hidden := false

var _scroll := 0.0
var _scroll_v := 0.0
var _t := 0.0
var _shake := Vector2.ZERO
var _stars: Array[Vector3] = []
var _clouds: Array[Vector3] = []   # angle, radius px, alpha
var _land: Array[Vector3] = []
var _explosion: CPUParticles2D
var _sparks: CPUParticles2D


func setup(m: FlightModel, build: Dictionary) -> void:
	model = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in 240:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.6, 2.2)))
	for i in 520:
		_clouds.append(Vector3(rng.randf() * TAU - PI, rng.randf_range(35.0, 110.0), rng.randf_range(0.35, 0.8)))
	for i in 110:
		_land.append(Vector3(rng.randf() * TAU - PI, rng.randf_range(60.0, 190.0), rng.randf()))
	rocket = RocketNode.new()
	add_child(rocket)
	rocket.setup(build)
	_make_explosion()


func _make_explosion() -> void:
	_explosion = CPUParticles2D.new()
	_explosion.one_shot = true
	_explosion.emitting = false
	_explosion.amount = 160
	_explosion.lifetime = 1.8
	_explosion.explosiveness = 1.0
	_explosion.spread = 180.0
	_explosion.initial_velocity_min = 80.0
	_explosion.initial_velocity_max = 520.0
	_explosion.gravity = Vector2(0, 90)
	_explosion.texture = RocketNode.soft_texture()
	_explosion.scale_amount_min = 0.4
	_explosion.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.set_color(1, Color(0.3, 0.1, 0.05, 0.0))
	g.add_point(0.3, Color(1.0, 0.5, 0.1, 0.9))
	_explosion.color_ramp = g
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_explosion.material = mat
	add_child(_explosion)
	_sparks = CPUParticles2D.new()
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.amount = 90
	_sparks.lifetime = 2.4
	_sparks.explosiveness = 0.95
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 150.0
	_sparks.initial_velocity_max = 700.0
	_sparks.gravity = Vector2(0, 160)
	_sparks.texture = RocketNode.soft_texture()
	_sparks.scale_amount_min = 0.06
	_sparks.scale_amount_max = 0.16
	_sparks.color = Color(1.0, 0.85, 0.5)
	add_child(_sparks)


func explode() -> void:
	rocket_hidden = true
	rocket.visible = false
	_explosion.position = rocket.position
	_sparks.position = rocket.position
	_explosion.restart()
	_sparks.restart()
	flash = 1.0


func rocket_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.5) + _shake


func ground_screen_y(h: float) -> float:
	var half := rocket.half_height() if rocket != null else 100.0
	var base := size.y * 0.5 + half
	var f1 := base + 300.0 * (1.0 - exp(-h / 700.0))
	if h < 10000.0:
		return f1
	var f10 := base + 300.0 * (1.0 - exp(-10000.0 / 700.0))
	return lerpf(f10, size.y * 0.74, smoothstep(15000.0, 100000.0, h))


func planet_radius_px(h: float) -> float:
	var tt := clampf((h - 10000.0) / 210000.0, 0.0, 1.0)
	return 30000.0 * pow(1500.0 / 30000.0, sqrt(tt))


## Advance purely visual scroll values (called once per rendered frame with simulated dt).
func advance(sim_dt: float) -> void:
	var h := model.altitude()
	var ppm := 0.9 * exp(-h / 9000.0) + 0.004
	_scroll += model.vt * ppm * sim_dt
	_scroll_v += model.vr * 0.5 * sim_dt


func _process(delta: float) -> void:
	_t += delta
	if shake_amp > 0.001:
		_shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amp
		shake_amp = lerpf(shake_amp, 0.0, minf(1.0, delta * 3.0))
	else:
		_shake = Vector2.ZERO
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 1.6)
	if rocket != null and model != null:
		rocket.position = rocket_center()
		rocket.rotation = model.pitch
	queue_redraw()


func _arc_points(c: Vector2, rad: float, amax: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(-amax, amax, float(i) / float(n))
		pts.append(c + Vector2(sin(a), -cos(a)) * rad)
	return pts


func _draw() -> void:
	if model == null:
		return
	var s := size
	var h := model.altitude()
	var top_y := ground_screen_y(h) + _shake.y
	var rpx := planet_radius_px(h)
	var space := smoothstep(4000.0, 85000.0, h)
	# --- sky -----------------------------------------------------------------
	var sky_top := Color(0.08, 0.26, 0.68).lerp(Color(0.0, 0.006, 0.03), space)
	var sky_hor := Color(0.58, 0.8, 0.98).lerp(Color(0.02, 0.05, 0.12), space)
	var by := maxf(top_y, 1.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, by), Vector2(0, by)]),
		PackedColorArray([sky_top, sky_top, sky_hor, sky_hor]))
	if top_y < s.y:
		draw_rect(Rect2(0, top_y - 1.0, s.x, s.y - top_y + 2.0), sky_hor)
	# --- stars ---------------------------------------------------------------
	var star_a := smoothstep(14000.0, 70000.0, h)
	if star_a > 0.01:
		for st in _stars:
			var x := fposmod(st.x * s.x - _scroll * 0.01 * st.z, s.x)
			draw_circle(Vector2(x, st.y * s.y), st.z * 0.8,
				Color(0.85, 0.92, 1.0, star_a * (0.45 + 0.4 * sin(_t * 2.0 + st.x * 40.0))))
		# distant sun glare
		var sc := Vector2(s.x * 0.12, s.y * 0.14)
		for i in 7:
			draw_circle(sc, 130.0 - i * 17.0, Color(1.0, 0.9, 0.65, star_a * 0.05))
	# --- airflow streaks -----------------------------------------------------
	var rho := model.air_density()
	var sp := model.speed()
	if sp > 90.0 and rho > 0.002:
		var dir := Vector2(model.vt, -model.vr).normalized()
		var alpha := clampf(rho / 0.8, 0.0, 1.0) * clampf(sp / 700.0, 0.0, 1.0) * 0.5
		for i in 26:
			var ox := fposmod(float(i) * 97.0 + sin(float(i) * 3.1) * 200.0, s.x)
			var oy := fposmod(float(i) * 131.0 - _scroll_v * 2.0, s.y + 200.0) - 100.0
			var p0 := Vector2(ox, oy)
			draw_line(p0, p0 - dir * (20.0 + sp * 0.07), Color(1, 1, 1, alpha), 1.5)
	# --- planet ----------------------------------------------------------------
	if top_y < s.y + 40.0 or rpx < 20000.0:
		_draw_planet(s, h, top_y, rpx)
	# --- launch pad ----------------------------------------------------------
	if top_y < s.y + 60.0 and h < 6000.0:
		_draw_pad(s, top_y)
	# --- explosion flash -------------------------------------------------------
	if flash > 0.0:
		draw_circle(rocket_center(), 80.0 + (1.0 - flash) * 520.0, Color(1.0, 0.8, 0.5, flash * 0.5))
		draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.9, 0.7, flash * 0.18))


func _draw_planet(s: Vector2, h: float, top_y: float, rpx: float) -> void:
	var ocean := smoothstep(3000.0, 40000.0, h)
	var base_col := Color(0.14, 0.34, 0.17).lerp(Color(0.05, 0.22, 0.52), ocean)
	var cx := s.x * 0.5
	var center := Vector2(cx, top_y + rpx)
	# atmosphere glow rings (visible mainly from space)
	var glow_a := smoothstep(20000.0, 100000.0, h)
	var big := rpx > 12000.0
	var amax := 0.0
	if big:
		amax = asin(minf(1.0, (s.x * 0.75) / rpx)) + 0.02
	else:
		amax = PI
	if glow_a > 0.0:
		for k in 9:
			var rr := rpx + 10.0 + k * (rpx * 0.0045 + 6.0)
			draw_polyline(_arc_points(center, rr, amax, 56), Color(0.35, 0.65, 1.0, glow_a * 0.11 * (1.0 - k / 9.0)),
				rpx * 0.0045 + 7.0, true)
	if big:
		# nearly flat ground: a plain rectangle is enough and avoids huge polygons
		draw_rect(Rect2(0, top_y, s.x, s.y - top_y + 2.0), base_col)
		# hills silhouette / distant ridges at low altitude
		var low := 1.0 - smoothstep(0.0, 6000.0, h)
		if low > 0.01:
			var pts := PackedVector2Array()
			pts.append(Vector2(0, top_y + 40.0))
			for i in 33:
				var x := s.x * float(i) / 32.0
				var y := top_y - 8.0 - 26.0 * (0.5 + 0.5 * sin((x + _scroll * 0.4) * 0.006)) \
					- 14.0 * sin((x + _scroll * 0.4) * 0.017 + 1.3)
				pts.append(Vector2(x, y))
			pts.append(Vector2(s.x, top_y + 40.0))
			draw_colored_polygon(pts, Color(0.09, 0.2, 0.16, low))
		draw_rect(Rect2(0, top_y, s.x, 5.0), Color(0.7, 0.9, 1.0, 0.25 * (1.0 - ocean)))
	else:
		var disc := _arc_points(center, rpx, amax, 90)
		disc.append(center)
		draw_colored_polygon(disc, base_col)
		draw_polyline(_arc_points(center, rpx, amax, 120), Color(0.55, 0.8, 1.0, 0.9), 3.0, true)
	# land patches + clouds on the surface (rotate with downrange angle theta)
	var surf_a := smoothstep(2500.0, 9000.0, h)
	if surf_a > 0.01 and rpx < 30500.0:
		var th := model.theta
		var sc := clampf(rpx / 7000.0, 0.14, 1.0)   # keep decoration proportional to the globe
		for lp in _land:
			var sa := wrapf(lp.x - th, -PI, PI)
			if absf(sa) > amax:
				continue
			var lr := lp.y * (0.5 + 0.5 * lp.z) * sc
			var p := center + Vector2(sin(sa), -cos(sa)) * (rpx - lr * 0.75)
			draw_circle(p, lr, Color(0.16, 0.42, 0.24, 0.9 * surf_a * ocean))
		for c in _clouds:
			var ca := wrapf(c.x - th * 1.07, -PI, PI)
			if absf(ca) > amax:
				continue
			var rad := c.y * sc * 0.8
			var cp := center + Vector2(sin(ca), -cos(ca)) * (rpx - rad * 0.55)
			var al := c.z * surf_a * 0.5
			draw_circle(cp, rad, Color(1, 1, 1, al))
			draw_circle(cp + Vector2(rad * 0.7, rad * 0.05), rad * 0.7, Color(1, 1, 1, al))
			draw_circle(cp + Vector2(-rad * 0.7, rad * 0.1), rad * 0.6, Color(1, 1, 1, al))


func _draw_pad(s: Vector2, top_y: float) -> void:
	var cx := s.x * 0.5 - _scroll
	# concrete apron
	draw_rect(Rect2(cx - 150.0, top_y, 300.0, 14.0), Color(0.32, 0.35, 0.42))
	draw_rect(Rect2(cx - 150.0, top_y, 300.0, 3.0), Color(0.55, 0.6, 0.7))
	# flame trench glow while engines run
	if model.throttle > 0.02 and model.altitude() < 400.0:
		for i in 5:
			draw_circle(Vector2(cx, top_y - 6.0), 40.0 + i * 22.0, Color(1.0, 0.6, 0.25, 0.05 * model.throttle))
	# service tower
	var tx := cx - 96.0
	var th := 330.0
	draw_rect(Rect2(tx, top_y - th, 18.0, th), Color(0.42, 0.18, 0.12))
	for i in 11:
		var y := top_y - th + i * (th / 11.0)
		draw_line(Vector2(tx, y), Vector2(tx + 18.0, y + th / 11.0), Color(0.75, 0.35, 0.2), 2.0)
		draw_line(Vector2(tx + 18.0, y), Vector2(tx, y + th / 11.0), Color(0.75, 0.35, 0.2), 2.0)
	draw_rect(Rect2(tx - 60.0, top_y - th, 66.0, 7.0), Color(0.6, 0.62, 0.7))
	for i in 3:
		var arm_y := top_y - 230.0 + i * 60.0
		draw_rect(Rect2(tx + 18.0, arm_y, 56.0 - i * 4.0, 5.0), Color(0.6, 0.62, 0.7))
	# beacon
	draw_circle(Vector2(tx + 9.0, top_y - th - 8.0), 4.0, Color(1, 0.2, 0.2, 0.5 + 0.5 * sin(_t * 5.0)))
	# floodlights
	draw_circle(Vector2(cx + 120.0, top_y - 70.0), 3.0, Color(1.0, 0.95, 0.7))
	draw_line(Vector2(cx + 120.0, top_y), Vector2(cx + 120.0, top_y - 70.0), Color(0.4, 0.42, 0.5), 3.0)
