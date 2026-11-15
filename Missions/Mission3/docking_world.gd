class_name DockingWorld
extends Control
## Mission 3 world: a spacecraft with RCS thrusters (translation + rotation, full
## inertia) approaching the docking port of the station. Port at the origin,
## facing -X; the spacecraft must fly along +X with its nose on the X axis.

signal docked
signal docking_failed(reason: String)
signal collided

const PORT := Vector2.ZERO
const NOSE := 4.6
const SHIP_R := 2.5
const ACC := 1.5                 # snappier thrusters: the manoeuvres take a third of the time
const ACC_FINE := 0.5
const ROT_ACC := 1.4
const ROT_ACC_FINE := 0.45
const FUEL_MAX := 60.0
const FUEL_TRANS := 1.0
const FUEL_ROT := 0.15
# docking tolerances
const TOL_SPEED := 0.5
const TOL_LAT := 1.2
const TOL_ANGLE := 0.105       # ~6 deg
const TOL_LAT_RATE := 0.3
const TOL_OMEGA := 0.052       # ~3 deg/s

var pos := Vector2(-300.0, 30.0)
var vel := Vector2(6.0, -0.12)      # fast approach (was 2 m/s)
var angle := 0.5
var omega := 0.0
var fuel := FUEL_MAX
var warp := 8                       # time compression for the long far approach (drops to x1 inside 150 m)
var finished := false
var contact_result := ""
var contact_speed := 0.0
var draw_2d := true               # false when DockingView3D renders the world
var thrust_fx := Vector2.ZERO   # for drawing (ship frame)
var rot_fx := 0.0

var _t := 0.0
var _ppm := 1.5
var _cam := Vector2(-150.0, 20.0)
var _stars: Array[Vector3] = []
var _puffs: Array = []
var _fx: Array = []
var _lock_t := 0.0
var _dead := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 280:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.5, 2.0)))


func nose_dir() -> Vector2:
	return Vector2.from_angle(angle)


func nose_tip() -> Vector2:
	return pos + nose_dir() * NOSE


func axial_distance() -> float:
	return PORT.x - nose_tip().x


func angle_error() -> float:
	return wrapf(angle, -PI, PI)


func range_to_port() -> float:
	return nose_tip().distance_to(PORT)


func hulls() -> Array[Rect2]:
	return [
		Rect2(0.0, -3.4, 14.0, 6.8),
		Rect2(14.0, -1.4, 104.0, 2.8),
		Rect2(22.0, -12.0, 8.0, 24.0),
		Rect2(60.0, -10.0, 6.0, 20.0),
		Rect2(36.0, -62.0, 16.0, 46.0), Rect2(36.0, 16.0, 16.0, 46.0),
		Rect2(86.0, -62.0, 16.0, 46.0), Rect2(86.0, 16.0, 16.0, 46.0),
	]


## fwd/strafe/rot in -1..1.
func step(delta: float, fwd: float, strafe: float, rot: float, fine: bool, kill_rot: bool) -> void:
	if finished:
		_lock_t += delta
		queue_redraw()
		return
	var wdt := delta
	if warp > 1 and range_to_port() > 100.0:
		wdt = delta * float(warp)
		fwd = 0.0
		strafe = 0.0
		rot = 0.0
		kill_rot = false
	else:
		warp = 1
	_t += delta
	var n := nose_dir()
	var side := n.rotated(PI * 0.5)
	var a := ACC_FINE if fine else ACC
	var ra := ROT_ACC_FINE if fine else ROT_ACC
	var acc := Vector2.ZERO
	var used := 0.0
	thrust_fx = Vector2(fwd, strafe)
	rot_fx = rot
	if fuel > 0.0:
		if fwd != 0.0 or strafe != 0.0:
			acc = (n * fwd + side * strafe * 0.8) * a
			used += FUEL_TRANS * (0.35 if fine else 1.0) * clampf(absf(fwd) + absf(strafe), 0.0, 1.0)
		if kill_rot and absf(omega) > 0.002:
			var dw := minf(ra, absf(omega) / maxf(wdt, 0.0001))
			omega -= signf(omega) * dw * wdt
			used += FUEL_ROT * 0.8
			rot_fx = -signf(omega)
		elif rot != 0.0:
			omega += rot * ra * wdt
			used += FUEL_ROT * (0.35 if fine else 1.0)
		fuel = maxf(0.0, fuel - used * wdt)
	else:
		thrust_fx = Vector2.ZERO
		rot_fx = 0.0
	vel += acc * wdt
	pos += vel * wdt
	angle += omega * wdt
	if used > 0.0 and warp == 1:
		_emit_puffs(fwd, strafe, rot)
	for p in _puffs:
		p["life"] -= delta
		p["p"] += p["v"] * delta
	_puffs = _puffs.filter(func(p): return p["life"] > 0.0)
	for f in _fx:
		f["t"] += delta
	_fx = _fx.filter(func(f): return f["t"] < 1.6)
	_check_contact()
	_update_camera(delta)
	queue_redraw()


func _emit_puffs(fwd: float, strafe: float, rot: float) -> void:
	if _puffs.size() > 120:
		return
	var n := nose_dir()
	var side := n.rotated(PI * 0.5)
	var push := n * fwd + side * strafe
	if push.length() > 0.01:
		var d := -push.normalized()
		_puffs.append({"p": pos + d * 3.0, "v": vel + d * randf_range(3.0, 6.0) + side * randf_range(-0.5, 0.5), "life": randf_range(0.4, 0.8)})
	if rot != 0.0:
		var sgn := signf(rot)
		_puffs.append({"p": pos + n * 3.8 + side * (-sgn) * 1.2, "v": vel + side * (-sgn) * 4.0 + n * 0.5, "life": 0.4})
		_puffs.append({"p": pos - n * 3.8 + side * sgn * 1.2, "v": vel + side * sgn * 4.0 - n * 0.5, "life": 0.4})


func _check_contact() -> void:
	var tip := nose_tip()
	# --- docking attempt: nose tip reaches the port plane
	if tip.x >= PORT.x - 0.3 and absf(tip.y) < 3.2 and vel.x > 0.0:
		var reason := ""
		if vel.x > TOL_SPEED:
			reason = "M3_FAIL_SPEED"
		elif absf(tip.y) > TOL_LAT:
			reason = "M3_FAIL_OFFSET"
		elif absf(angle_error()) > TOL_ANGLE:
			reason = "M3_FAIL_ANGLE"
		elif absf(vel.y) > TOL_LAT_RATE or absf(omega) > TOL_OMEGA:
			reason = "M3_FAIL_DRIFT"
		finished = true
		contact_result = reason
		contact_speed = vel.x
		if reason == "":
			vel = Vector2.ZERO
			omega = 0.0
			docked.emit()
		else:
			_dead = true
			_fx.append({"p": tip, "t": 0.0})
			collided.emit()
			docking_failed.emit(reason)
		return
	# --- hull collisions (ship body as a circle)
	for r in hulls():
		var cp := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
		var diff := pos - cp
		var dist := diff.length()
		if dist < SHIP_R and dist > 0.0001:
			var nrm := diff / dist
			var impact := -vel.dot(nrm)
			if impact > 0.9:
				finished = true
				_dead = true
				_fx.append({"p": cp, "t": 0.0})
				collided.emit()
				docking_failed.emit("M3_FAIL_COLLISION")
				return
			pos += nrm * (SHIP_R - dist)
			if impact > 0.0:
				vel += nrm * impact * 1.3


func _update_camera(delta: float) -> void:
	var d := range_to_port()
	var target_ppm := clampf(300.0 / (d * 0.6 + 12.0), 0.9, 28.0)
	_ppm = lerpf(_ppm, target_ppm, minf(1.0, delta * 2.0))
	var w := clampf(1.0 - d / 120.0, 0.0, 1.0)
	var tcam := (pos + PORT) * 0.5
	tcam = tcam.lerp(nose_tip().lerp(PORT, 0.5), w)
	_cam = _cam.lerp(tcam, minf(1.0, delta * 3.0))


func w2s(p: Vector2) -> Vector2:
	return (p - _cam) * _ppm + size * 0.5


# ------------------------------------------------------------------ draw ----
func _draw() -> void:
	if not draw_2d:
		return
	var s := size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([Color("01020a"), Color("01020a"), Color("040c1e"), Color("040c1e")]))
	for st in _stars:
		var par := 0.02 + st.z * 0.02
		var x := fposmod(st.x * s.x - _cam.x * _ppm * par - _t * 3.0 * st.z, s.x)
		var y := fposmod(st.y * s.y - _cam.y * _ppm * par, s.y)
		draw_circle(Vector2(x, y), st.z * 0.8, Color(0.85, 0.92, 1.0, 0.35 + 0.25 * sin(_t * 1.5 + st.x * 30.0)))
	var er := s.x * 1.25
	SpaceBackdrop.draw_earth(self, Vector2(s.x * 0.35 - _cam.x * 0.2, s.y + er * 0.72 - _cam.y * 0.2), er, _t * 2.5)
	_draw_corridor(s)
	draw_set_transform(s * 0.5 - _cam * _ppm, 0.0, Vector2(_ppm, _ppm))
	_draw_station()
	_draw_port_marker()
	for p in _puffs:
		draw_circle(p["p"], 0.35 + (0.8 - float(p["life"])) * 0.4, Color(0.85, 0.93, 1.0, clampf(float(p["life"]) * 1.8, 0.0, 0.7)))
	if not _dead:
		_draw_ship()
	for f in _fx:
		var k: float = float(f["t"]) / 1.6
		draw_arc(f["p"], 1.0 + k * 14.0, 0.0, TAU, 40, Color(1.0, 0.6, 0.25, 1.0 - k), 0.5)
		draw_circle(f["p"], 3.0 * (1.0 - k), Color(1.0, 0.9, 0.6, 1.0 - k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# far away the ship is tiny: add a locator ring
	if not _dead and _ppm * 9.0 < 18.0:
		var sp := w2s(pos)
		draw_arc(sp, 14.0 + 3.0 * sin(_t * 4.0), 0.0, TAU, 32, Color(0.4, 0.8, 1.0, 0.8), 1.5)
	# velocity vector
	if not _dead and not finished:
		var vs := w2s(nose_tip())
		draw_line(vs, vs + vel * 10.0 * _ppm, Color(0.3, 1.0, 0.7, 0.9), 2.0, true)
		draw_circle(vs + vel * 10.0 * _ppm, 3.0, Color(0.3, 1.0, 0.7))
	if finished and contact_result == "":
		var k2 := clampf(_lock_t / 1.2, 0.0, 1.0)
		draw_arc(w2s(PORT), 20.0 + k2 * 160.0, 0.0, TAU, 48, Color(0.4, 1.0, 0.7, 1.0 - k2), 3.0)


func _draw_corridor(s: Vector2) -> void:
	var p0 := w2s(PORT)
	var reach := 330.0
	var half := tan(deg_to_rad(8.0)) * reach
	var a := w2s(Vector2(PORT.x - reach, -half))
	var b := w2s(Vector2(PORT.x - reach, half))
	draw_colored_polygon(PackedVector2Array([p0, a, b]), Color(0.3, 1.0, 0.7, 0.05))
	draw_line(p0, a, Color(0.3, 1.0, 0.7, 0.28), 1.5, true)
	draw_line(p0, b, Color(0.3, 1.0, 0.7, 0.28), 1.5, true)
	draw_line(p0, w2s(Vector2(PORT.x - reach, 0.0)), Color(0.3, 1.0, 0.7, 0.35), 1.0, true)
	# range ticks
	var font := ThemeDB.fallback_font
	for m in [10, 25, 50, 100, 200, 300]:
		var tp := w2s(Vector2(PORT.x - float(m), 0.0))
		if tp.x > -20.0 and tp.x < s.x + 20.0:
			draw_line(tp + Vector2(0, -7), tp + Vector2(0, 7), Color(0.3, 1.0, 0.7, 0.55), 1.5)
			draw_string(font, tp + Vector2(-14, 24), "%d" % m, HORIZONTAL_ALIGNMENT_CENTER, 28.0, 12, Color(0.5, 1.0, 0.8, 0.7))


func _draw_station() -> void:
	var hull := Color("cdd6e8")
	var shade := Color("8996b3")
	var line := Color("46567a")
	# truss + modules
	draw_rect(Rect2(14.0, -1.4, 104.0, 2.8), Color("9aa6c0"))
	draw_rect(Rect2(14.0, -1.4, 104.0, 2.8), line, false, 0.2)
	var x := 16.0
	while x < 118.0:
		draw_line(Vector2(x, -1.4), Vector2(x + 2.0, 1.4), line, 0.15)
		x += 2.0
	draw_rect(Rect2(0.0, -3.4, 14.0, 6.8), hull)
	draw_rect(Rect2(0.0, 1.0, 14.0, 2.4), shade)
	draw_rect(Rect2(0.0, -3.4, 14.0, 6.8), line, false, 0.2)
	for i in 4:
		draw_rect(Rect2(2.5 + i * 2.8, -2.2, 1.5, 1.0), Color("5fb4ff"))
	draw_rect(Rect2(22.0, -12.0, 8.0, 24.0), hull)
	draw_rect(Rect2(22.0, -12.0, 8.0, 24.0), line, false, 0.2)
	draw_rect(Rect2(26.0, -12.0, 4.0, 24.0), shade)
	draw_rect(Rect2(60.0, -10.0, 6.0, 20.0), hull)
	draw_rect(Rect2(60.0, -10.0, 6.0, 20.0), line, false, 0.2)
	# big solar arrays
	for ax in [36.0, 86.0]:
		for ay in [-62.0, 16.0]:
			var ar := Rect2(ax, ay, 16.0, 46.0)
			draw_rect(ar, Color("1d52a8"))
			draw_rect(ar, Color("a8d4ff"), false, 0.3)
			var gx := ar.position.x + 2.0
			while gx < ar.end.x:
				draw_line(Vector2(gx, ar.position.y), Vector2(gx, ar.end.y), Color(0.6, 0.82, 1.0, 0.45), 0.12)
				gx += 2.0
			var gy := ar.position.y + 2.0
			while gy < ar.end.y:
				draw_line(Vector2(ar.position.x, gy), Vector2(ar.end.x, gy), Color(0.6, 0.82, 1.0, 0.45), 0.12)
				gy += 2.0
	# radiators
	draw_rect(Rect2(108.0, -30.0, 6.0, 26.0), Color("e8edf8"))
	draw_rect(Rect2(108.0, 4.0, 6.0, 26.0), Color("e8edf8"))
	# docking adapter
	draw_rect(Rect2(-0.8, -1.8, 1.0, 3.6), Color("2a3350"))
	draw_circle(Vector2(0.0, 0.0), 1.2, Color("1a2038"))


func _draw_port_marker() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var good := finished and contact_result == ""
	var col := Color(0.4, 1.0, 0.7, 0.9) if good else Color(1.0, 0.75, 0.25, 0.55 + 0.4 * pulse)
	draw_arc(PORT, 2.6, 0.0, TAU, 32, col, maxf(0.2, 1.5 / _ppm))
	draw_line(PORT + Vector2(-4.5, 0), PORT + Vector2(-1.0, 0), col, maxf(0.15, 1.2 / _ppm))
	draw_line(PORT + Vector2(0, -4.5), PORT + Vector2(0, -1.5), col, maxf(0.15, 1.2 / _ppm))
	draw_line(PORT + Vector2(0, 4.5), PORT + Vector2(0, 1.5), col, maxf(0.15, 1.2 / _ppm))


func _draw_ship() -> void:
	var xf := size * 0.5 - _cam * _ppm + pos * _ppm
	draw_set_transform(xf, angle, Vector2(_ppm, _ppm))
	# solar wings
	for sgn in [-1.0, 1.0]:
		draw_rect(Rect2(-3.6, 1.2 if sgn > 0 else -6.4, 2.2, 5.2), Color("1f56b0"))
		draw_rect(Rect2(-3.6, 1.2 if sgn > 0 else -6.4, 2.2, 5.2), Color("a9d6ff"), false, 0.1)
		draw_line(Vector2(-3.6, 1.7 * sgn), Vector2(-1.4, 1.7 * sgn), Color("a9d6ff"), 0.08)
	# service module
	draw_rect(Rect2(-4.6, -1.5, 3.8, 3.0), Color("c4ccdc"))
	draw_rect(Rect2(-4.6, 0.3, 3.8, 1.2), Color("8d98b2"))
	draw_rect(Rect2(-4.6, -1.5, 3.8, 3.0), Color("46567a"), false, 0.1)
	# crew capsule
	draw_colored_polygon(PackedVector2Array([Vector2(-0.8, -1.5), Vector2(2.4, -0.7), Vector2(2.4, 0.7), Vector2(-0.8, 1.5)]), Color("eef2fa"))
	draw_circle(Vector2(0.6, 0.0), 0.35, Color("1b2d55"))
	# docking probe
	draw_line(Vector2(2.4, 0.0), Vector2(NOSE, 0.0), Color("9aa6c0"), 0.2)
	draw_circle(Vector2(NOSE, 0.0), 0.35, Color("ffb347"))
	# main engine glow when braking (thrusting backwards)
	if thrust_fx.x > 0.1:
		draw_colored_polygon(PackedVector2Array([Vector2(-4.6, -0.7), Vector2(-4.6, 0.7), Vector2(-7.5, 0.0)]), Color(1.0, 0.6, 0.2, 0.7))
	elif thrust_fx.x < -0.1:
		draw_colored_polygon(PackedVector2Array([Vector2(1.0, -1.2), Vector2(2.4, -0.7), Vector2(3.6, -2.2)]), Color(0.8, 0.95, 1.0, 0.7))
	draw_set_transform(size * 0.5 - _cam * _ppm, 0.0, Vector2(_ppm, _ppm))



