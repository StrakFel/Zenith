class_name SpacewalkWorld
extends Control
## Mission 2 world: astronaut with inertia (no drag in vacuum), limited thruster gas,
## a station airlock, and a damaged satellite with three repair points.
## Units: metres, seconds. Everything is drawn procedurally.

signal repaired(index: int)
signal suit_hit

const PPM := 14.0
const HATCH := Vector2(-4.0, 0.0)
const SAT := Vector2(72.0, -30.0)
const TARGETS: Array[Vector2] = [Vector2(-9.0, -4.8), Vector2(2.0, -9.8), Vector2(4.0, 8.8)]
const TARGET_R := 3.4
const HOLD_TIME := 2.5
const REPAIR_MAX_SPEED := 0.6
const ACC := 1.3
const ACC_FINE := 0.45
const FUEL_RATE := 1.5
const FUEL_RATE_FINE := 0.5
const BRAKE_RATE := 2.0
const FUEL_MAX := 90.0
const O2_MAX := 300.0
const ASTRO_R := 0.8

var pos := Vector2(9.0, 4.0)
var vel := Vector2.ZERO
var fuel := FUEL_MAX
var o2 := O2_MAX
var suit := 100.0
var fuel_cap := FUEL_MAX
var o2_cap := O2_MAX
var suit_k := 1.0                 # suit durability multiplier (armoured suit > 1)
var progress: Array[float] = [0.0, 0.0, 0.0]
var done: Array[bool] = [false, false, false]
var thrusting := false
var facing := 0.0
var cam := Vector2.ZERO
var all_repaired := false
var collisions := 0
var draw_2d := true               # false when a 3D view renders the world
var last_acc := Vector2.ZERO

var _t := 0.0
var _puffs: Array = []
var _fx: Array = []
var _stars: Array[Vector3] = []
var panel_fix := 0.0
var antenna_fix := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 260:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.5, 2.0)))
	cam = pos


func target_world(i: int) -> Vector2:
	return SAT + TARGETS[i]


func next_target() -> Vector2:
	var best := -1
	var bd := INF
	for i in 3:
		if not done[i]:
			var d := pos.distance_to(target_world(i))
			if d < bd:
				bd = d
				best = i
	return target_world(best) if best >= 0 else HATCH


func hulls() -> Array[Rect2]:
	return [
		Rect2(-44.0, -7.0, 40.0, 14.0),            # main module
		Rect2(-54.0, -4.0, 10.0, 8.0),             # aft module
		Rect2(-8.0, -3.0, 4.0, 6.0),               # airlock
		Rect2(-34.0, -31.0, 16.0, 22.0),           # upper array
		Rect2(-34.0, 9.0, 16.0, 22.0),             # lower array
		Rect2(SAT.x - 7.0, SAT.y - 5.0, 14.0, 10.0),   # satellite body
		Rect2(SAT.x + 8.0, SAT.y - 1.6, 20.0, 3.2),    # right panel
	]


func step(delta: float, dir: Vector2, fine: bool, brake: bool) -> void:
	_t += delta
	o2 = maxf(0.0, o2 - delta)
	var acc := Vector2.ZERO
	var use := 0.0
	thrusting = false
	if fuel > 0.0:
		if brake and vel.length() > 0.01:
			var dv := minf(ACC, vel.length() / maxf(delta, 0.0001))
			acc = -vel.normalized() * dv
			use = BRAKE_RATE * dv / ACC
			thrusting = true
		elif dir != Vector2.ZERO:
			acc = dir.normalized() * (ACC_FINE if fine else ACC)
			use = FUEL_RATE_FINE if fine else FUEL_RATE
			thrusting = true
	last_acc = acc
	if thrusting:
		fuel = maxf(0.0, fuel - use * delta)
		_emit_puffs(acc)
	vel += acc * delta
	pos += vel * delta
	_collide()
	_update_repairs(delta)
	facing = lerp_angle(facing, clampf(vel.x * 0.12, -0.6, 0.6), minf(1.0, delta * 2.0))
	cam = cam.lerp(pos, minf(1.0, delta * 3.0))
	panel_fix = move_toward(panel_fix, 1.0 if done[0] else 0.0, delta * 1.2)
	antenna_fix = move_toward(antenna_fix, 1.0 if done[1] else 0.0, delta * 1.2)
	for p in _puffs:
		p["life"] -= delta
		p["p"] += p["v"] * delta
	_puffs = _puffs.filter(func(p): return p["life"] > 0.0)
	for f in _fx:
		f["t"] += delta
	_fx = _fx.filter(func(f): return f["t"] < 1.2)
	queue_redraw()


func _emit_puffs(acc: Vector2) -> void:
	if _puffs.size() > 160:
		return
	var d := -acc.normalized()
	for i in 2:
		_puffs.append({"p": pos + d * 0.9 + Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)),
			"v": vel + d * randf_range(2.5, 5.0) + Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)),
			"life": randf_range(0.35, 0.7)})


func _collide() -> void:
	for r in hulls():
		var cp := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
		var diff := pos - cp
		var dist := diff.length()
		if dist >= ASTRO_R:
			continue
		var n: Vector2
		if dist < 0.0001:
			# centre inside the rectangle: push along the shallowest axis
			var dl := pos.x - r.position.x
			var dr := r.end.x - pos.x
			var dt := pos.y - r.position.y
			var db := r.end.y - pos.y
			var m := minf(minf(dl, dr), minf(dt, db))
			if m == dl:
				n = Vector2.LEFT
			elif m == dr:
				n = Vector2.RIGHT
			elif m == dt:
				n = Vector2.UP
			else:
				n = Vector2.DOWN
			pos += n * (m + ASTRO_R)
		else:
			n = diff / dist
			pos += n * (ASTRO_R - dist)
		var impact := -vel.dot(n)
		if impact > 0.0:
			vel += n * impact * 1.35
			if impact > 1.2:
				suit = maxf(0.0, suit - ((impact - 1.2) * 14.0 + 4.0) / suit_k)
				collisions += 1
				suit_hit.emit()
				_fx.append({"p": pos, "t": 0.0, "kind": "hit"})


func _update_repairs(delta: float) -> void:
	var speed := vel.length()
	all_repaired = done[0] and done[1] and done[2]
	for i in 3:
		if done[i]:
			continue
		var d := pos.distance_to(target_world(i))
		if d < TARGET_R and speed < REPAIR_MAX_SPEED:
			progress[i] = minf(1.0, progress[i] + delta / HOLD_TIME)
			if progress[i] >= 1.0:
				done[i] = true
				_fx.append({"p": target_world(i), "t": 0.0, "kind": "fix"})
				repaired.emit(i)
		else:
			progress[i] = maxf(0.0, progress[i] - delta * 0.5)
	all_repaired = done[0] and done[1] and done[2]


func at_hatch() -> bool:
	return pos.distance_to(HATCH) < 2.6 and vel.length() < 0.8


## True if drifting (no fuel) could still reach a goal: closest approach to a goal is
## inside its radius and happens within the remaining oxygen time.
func drift_hope() -> bool:
	var goals: Array[Vector2] = []
	if all_repaired:
		goals.append(HATCH)
	else:
		for i in 3:
			if not done[i]:
				goals.append(target_world(i))
	var sp2 := vel.length_squared()
	if sp2 < 0.0004:
		return false
	for g in goals:
		var t := (g - pos).dot(vel) / sp2
		if t > 0.0 and t < o2:
			var closest := pos + vel * t
			if closest.distance_to(g) < 2.4 and vel.length() < (0.8 if g == HATCH else REPAIR_MAX_SPEED + 0.1):
				return true
	return false


# ------------------------------------------------------------------ draw ----
func _draw() -> void:
	if not draw_2d:
		return
	var s := size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([Color("01030a"), Color("01030a"), Color("050f22"), Color("050f22")]))
	for st in _stars:
		var par := 0.015 + st.z * 0.02
		var x := fposmod(st.x * s.x - cam.x * PPM * par, s.x)
		var y := fposmod(st.y * s.y - cam.y * PPM * par, s.y)
		draw_circle(Vector2(x, y), st.z * 0.8, Color(0.85, 0.92, 1.0, 0.35 + 0.25 * sin(_t * 1.5 + st.x * 30.0)))
	var er := s.x * 1.1
	SpaceBackdrop.draw_earth(self, Vector2(s.x * 0.62 - cam.x * 0.5, s.y + er * 0.78 - cam.y * 0.5), er, _t * 1.5)
	# ---- world (metres)
	draw_set_transform(s * 0.5 - cam * PPM, 0.0, Vector2(PPM, PPM))
	_draw_station()
	_draw_satellite()
	_draw_targets()
	for p in _puffs:
		var a: float = clampf(float(p["life"]) * 1.6, 0.0, 1.0)
		draw_circle(p["p"], 0.18 + (0.7 - float(p["life"])) * 0.3, Color(0.8, 0.92, 1.0, a * 0.7))
	_draw_astronaut()
	for f in _fx:
		var k: float = float(f["t"]) / 1.2
		var col := Color(0.4, 1.0, 0.7, 1.0 - k) if f["kind"] == "fix" else Color(1.0, 0.5, 0.3, 1.0 - k)
		draw_arc(f["p"], 1.0 + k * 6.0, 0.0, TAU, 32, col, 0.25)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_arrow(s)


func _draw_station() -> void:
	var hull := Color("c9d3e6")
	var shade := Color("8d9bb8")
	draw_rect(Rect2(-44.0, -7.0, 40.0, 14.0), hull)
	draw_rect(Rect2(-44.0, 2.0, 40.0, 5.0), shade)
	draw_rect(Rect2(-44.0, -7.0, 40.0, 14.0), Color("5a6a8a"), false, 0.25)
	for i in 8:
		draw_rect(Rect2(-41.0 + i * 4.6, -4.0, 2.2, 1.5), Color("1b2a4a"))
		draw_rect(Rect2(-41.0 + i * 4.6, -4.0, 2.2, 0.5), Color("5fb4ff"))
	draw_rect(Rect2(-54.0, -4.0, 10.0, 8.0), Color("b7c3dc"))
	draw_rect(Rect2(-54.0, -4.0, 10.0, 8.0), Color("5a6a8a"), false, 0.25)
	draw_rect(Rect2(-8.0, -3.0, 4.0, 6.0), Color("dfe6f5"))
	draw_rect(Rect2(-8.0, -3.0, 4.0, 6.0), Color("5a6a8a"), false, 0.25)
	# solar arrays with grid
	for sy in [-31.0, 9.0]:
		var ar := Rect2(-34.0, sy, 16.0, 22.0)
		draw_rect(ar, Color("1c4f9e"))
		draw_rect(ar, Color("9fd0ff"), false, 0.3)
		var gx := ar.position.x + 2.0
		while gx < ar.end.x:
			draw_line(Vector2(gx, ar.position.y), Vector2(gx, ar.end.y), Color(0.6, 0.82, 1.0, 0.5), 0.1)
			gx += 2.0
		var gy := ar.position.y + 2.0
		while gy < ar.end.y:
			draw_line(Vector2(ar.position.x, gy), Vector2(ar.end.x, gy), Color(0.6, 0.82, 1.0, 0.5), 0.1)
			gy += 2.0
	# hatch ring
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var hc := Color(0.3, 1.0, 0.6, 0.45 + 0.4 * pulse) if all_repaired else Color(0.3, 0.7, 1.0, 0.5)
	draw_arc(HATCH, 2.2, 0.0, TAU, 32, hc, 0.25)
	draw_circle(HATCH, 0.6, hc)


func _draw_satellite() -> void:
	var gold := Color("e8c55a")
	var body := Rect2(SAT.x - 7.0, SAT.y - 5.0, 14.0, 10.0)
	draw_rect(body, gold)
	draw_rect(Rect2(body.position.x, body.position.y + 6.5, body.size.x, 3.5), Color("b8932f"))
	draw_rect(body, Color("6f5520"), false, 0.25)
	draw_circle(SAT + Vector2(0, 0), 1.6, Color("2b3a5e"))
	# right panel (intact)
	_draw_panel(SAT + Vector2(8.0, 0.0), 0.0, 20.0, false)
	# left panel: broken until repaired
	var ang := lerpf(-0.55, 0.0, panel_fix)
	_draw_panel(SAT + Vector2(-8.0, 0.0), PI + ang, 18.0, not done[0])
	# antenna dish
	var aa := lerpf(0.75, 0.0, antenna_fix)
	var base := SAT + Vector2(2.0, -5.0)
	var dir := Vector2.UP.rotated(aa)
	draw_line(base, base + dir * 3.2, Color("cfd6e6"), 0.3)
	var dc := base + dir * 3.6
	draw_arc(dc, 2.2, dir.angle() - 1.1 + PI * 0.0, dir.angle() + 1.1, 16, Color("e9eef8"), 0.5)
	draw_circle(dc, 0.35, Color("ff6a6a") if not done[1] else Color("66ffb0"))
	# battery unit
	var bt := Rect2(SAT.x + 1.5, SAT.y + 5.0, 5.0, 3.0)
	draw_rect(bt, Color("55607a"))
	var bl := 0.5 + 0.5 * sin(_t * 6.0)
	draw_circle(bt.get_center(), 0.5, Color(1.0, 0.25, 0.25, 0.4 + 0.6 * bl) if not done[2] else Color(0.3, 1.0, 0.6))
	# sparks on broken panel
	if not done[0] and fmod(_t, 0.7) < 0.12:
		draw_circle(SAT + Vector2(-9.0 - randf() * 3.0, -1.0 + randf() * 2.0), 0.35, Color(1.0, 0.9, 0.4))


func _draw_panel(joint: Vector2, ang: float, length: float, broken: bool) -> void:
	var w := 1.6
	var pts := PackedVector2Array([
		joint + Vector2(0, -w).rotated(ang), joint + Vector2(length, -w).rotated(ang),
		joint + Vector2(length, w).rotated(ang), joint + Vector2(0, w).rotated(ang)])
	draw_colored_polygon(pts, Color("1f56b0") if not broken else Color("5b3b3b"))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color("a9d6ff"), 0.15)
	for i in range(1, 6):
		var f := float(i) / 6.0 * length
		draw_line(joint + Vector2(f, -w).rotated(ang), joint + Vector2(f, w).rotated(ang), Color(0.7, 0.88, 1.0, 0.6), 0.08)


func _draw_targets() -> void:
	for i in 3:
		if done[i]:
			continue
		var c := target_world(i)
		var pulse := 0.5 + 0.5 * sin(_t * 4.0 + i)
		var col := Color(1.0, 0.7, 0.2, 0.55 + 0.35 * pulse)
		draw_arc(c, TARGET_R, 0.0, TAU, 40, col, 0.18)
		draw_circle(c, 0.35, col)
		if progress[i] > 0.0:
			draw_arc(c, TARGET_R + 0.6, -PI * 0.5, -PI * 0.5 + TAU * progress[i], 40, Color(0.4, 1.0, 0.7), 0.4)


func _draw_astronaut() -> void:
	# rebuild the metre transform with the astronaut's rotation
	var base_xf := size * 0.5 - cam * PPM
	draw_set_transform(base_xf + pos * PPM, facing, Vector2(PPM, PPM))
	# backpack
	draw_rect(Rect2(-0.85, -0.55, 0.5, 1.5), Color("9aa6bf"))
	# torso + legs
	draw_rect(Rect2(-0.5, -0.5, 1.0, 1.4), Color("f1f4fb"))
	draw_rect(Rect2(-0.45, 0.8, 0.38, 0.7), Color("dfe5f2"))
	draw_rect(Rect2(0.07, 0.8, 0.38, 0.7), Color("dfe5f2"))
	# arms
	draw_rect(Rect2(0.3, -0.35, 0.9, 0.35), Color("f1f4fb"))
	draw_rect(Rect2(-1.0, 0.0, 0.7, 0.3), Color("f1f4fb"))
	# helmet
	draw_circle(Vector2(0.0, -0.95), 0.62, Color("f1f4fb"))
	draw_circle(Vector2(0.18, -0.95), 0.42, Color("1b2d55"))
	draw_circle(Vector2(0.3, -1.08), 0.14, Color(0.7, 0.9, 1.0, 0.9))
	draw_rect(Rect2(-0.5, -0.5, 1.0, 1.4), Color("7d8aa6"), false, 0.07)
	draw_rect(Rect2(-0.5, 0.15, 1.0, 0.18), Color("ff8a2b"))
	draw_set_transform(size * 0.5 - cam * PPM, 0.0, Vector2(PPM, PPM))


func _draw_arrow(s: Vector2) -> void:
	var tgt := next_target()
	var sp := (tgt - cam) * PPM + s * 0.5
	# keep the arrow clear of the HUD panels: usable box is inset more at the top
	var box := Rect2(70.0, 260.0, s.x - 140.0, s.y - 260.0 - 130.0)
	if box.has_point(sp):
		return
	var c := box.get_center()
	var dirv := (sp - c).normalized()
	var k := 1.0 / maxf(absf(dirv.x) / (box.size.x * 0.5), absf(dirv.y) / (box.size.y * 0.5))
	var p := c + dirv * k
	var col := UIKit.C_GOOD if all_repaired else UIKit.C_ORANGE
	var perp := dirv.orthogonal()
	draw_colored_polygon(PackedVector2Array([p + dirv * 16.0, p - dirv * 10.0 + perp * 11.0, p - dirv * 10.0 - perp * 11.0]), col)
	var txt := Units.m(pos.distance_to(tgt))
	draw_string(ThemeDB.fallback_font, p - dirv * 34.0 - Vector2(20, -5), txt, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 15, col)

