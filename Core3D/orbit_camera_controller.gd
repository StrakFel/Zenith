class_name OrbitCameraController
extends Node
## Reusable orbit / free-look camera in the style of NASA Mission Viz.
##
##   LMB drag   rotate 360 degrees around the focus point (with inertia)
##   Wheel      smooth zoom (clamped)
##   RMB drag   pan the focus point
##   R          reset (hand the camera back to the scene's own cinematic camera)
##   Dbl-click  smoothly focus the focusable object under the cursor
##
## The owner keeps its own "auto" camera and calls  update(delta, auto_pos, auto_look, auto_fov)
## every frame. While the controller is not engaged the camera follows the auto pose; when the
## player starts interacting (or the owner calls toggle_sticky) the controller takes over from
## the exact current pose, and after R it blends smoothly back. The controller NEVER touches
## anything but the camera - vehicles, physics and game state are untouched.

signal engaged_changed(on: bool)
signal focused(node: Node3D)

var camera: Camera3D
var enabled := true
var user_can_engage := true        # false in missions: free camera only in inspect (sticky) mode
var engaged := false
var sticky := false
var min_dist := 3.0
var max_dist := 600.0
var pitch_min := deg_to_rad(-82.0)
var pitch_max := deg_to_rad(86.0)
var rotate_speed := 0.0055
var ground: Node3D                 # optional: camera is kept above this node's origin height
var ground_margin := 2.0

var focus := Vector3.ZERO
var yaw := 0.0
var pitch := 0.3
var dist := 50.0

var focusables: Array = []        # {node, radius, dist}
var obstacles: Array = []         # {node, radius, half_len}  (half_len > 0 => vertical capsule)

var _focus_t := Vector3.ZERO
var _dist_t := 50.0
var _yaw_v := 0.0
var _pitch_v := 0.0
var _yaw_goal := NAN
var _pitch_goal := NAN
var _drag_l := false
var _drag_r := false
var _home_focus := Vector3.ZERO
var _home_dist := 50.0
var _release_t := 1.0
var _from_pose := Transform3D.IDENTITY
var _auto_pos := Vector3(0, 0, 10)
var _auto_look := Vector3.ZERO
var _auto_fov := -1.0


func setup(cam: Camera3D) -> void:
	camera = cam


func add_focusable(node: Node3D, radius: float, focus_dist: float = -1.0) -> void:
	focusables.append({"node": node, "radius": radius, "dist": focus_dist if focus_dist > 0.0 else radius * 3.2})


func add_obstacle(node: Node3D, radius: float, half_len: float = 0.0) -> void:
	obstacles.append({"node": node, "radius": radius, "half_len": half_len})


# ------------------------------------------------------------------ state ------
func engage() -> void:
	if engaged:
		return
	focus = _auto_look
	_focus_t = focus
	_home_focus = focus
	var off := _auto_pos - _auto_look
	dist = clampf(off.length(), min_dist, max_dist)
	_dist_t = dist
	_home_dist = dist
	yaw = atan2(off.x, off.z)
	pitch = asin(clampf(off.y / maxf(off.length(), 0.001), -1.0, 1.0))
	_yaw_v = 0.0
	_pitch_v = 0.0
	_yaw_goal = NAN
	_pitch_goal = NAN
	engaged = true
	engaged_changed.emit(true)


func disengage() -> void:
	if not engaged:
		return
	engaged = false
	sticky = false
	_drag_l = false
	_drag_r = false
	_release_t = 0.0
	if camera != null:
		_from_pose = camera.global_transform
	engaged_changed.emit(false)


## Inspect mode used by the missions (C key).
func toggle_sticky() -> void:
	if engaged and sticky:
		disengage()
	elif engaged:
		# already free-looking (the player dragged earlier): make it sticky and tell the owner
		sticky = true
		engaged_changed.emit(true)
	else:
		engage()
		sticky = true


## Smoothly move the orbit centre / distance (and optionally the viewing angles).
func fly_to(new_focus: Vector3, new_dist: float, new_yaw: float = NAN, new_pitch: float = NAN) -> void:
	engage()
	_focus_t = new_focus
	_dist_t = clampf(new_dist, min_dist, max_dist)
	_yaw_goal = new_yaw
	_pitch_goal = new_pitch


# ----------------------------------------------------------------- per frame ----
func update(delta: float, auto_pos: Vector3, auto_look: Vector3, auto_fov: float = -1.0) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	_auto_pos = auto_pos
	_auto_look = auto_look
	_auto_fov = auto_fov
	if engaged:
		_step_engaged(delta)
		return
	var dirv := auto_look - auto_pos
	if dirv.length() < 0.0001:
		return
	var up := Vector3.UP if absf(dirv.normalized().dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var xf := Transform3D(Basis.looking_at(dirv, up), auto_pos)
	if _release_t < 1.0:
		_release_t = minf(1.0, _release_t + delta / 1.3)
		camera.global_transform = _from_pose.interpolate_with(xf, smoothstep(0.0, 1.0, _release_t))
	else:
		camera.global_transform = xf
	if auto_fov > 0.0:
		camera.fov = lerpf(camera.fov, auto_fov, minf(1.0, delta * 4.0))


func _step_engaged(delta: float) -> void:
	if not _drag_l:
		yaw += _yaw_v * delta
		pitch += _pitch_v * delta
		var damp := exp(-delta * 3.2)
		_yaw_v *= damp
		_pitch_v *= damp
	if not is_nan(_yaw_goal):
		yaw = lerp_angle(yaw, _yaw_goal, 1.0 - exp(-delta * 3.0))
	if not is_nan(_pitch_goal):
		pitch = lerpf(pitch, _pitch_goal, 1.0 - exp(-delta * 3.0))
	pitch = clampf(pitch, pitch_min, pitch_max)
	dist = lerpf(dist, _dist_t, 1.0 - exp(-delta * 9.0))
	focus = focus.lerp(_focus_t, 1.0 - exp(-delta * 7.0))
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var pos := _avoid(focus + off)
	camera.global_position = pos
	var look_dir := focus - pos
	if look_dir.length() > 0.0001:
		var up := Vector3.UP if absf(look_dir.normalized().dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
		camera.look_at(focus, up)
	if _auto_fov > 0.0:
		camera.fov = lerpf(camera.fov, _auto_fov, minf(1.0, delta * 4.0))


## Keeps the camera out of models (spheres / vertical capsules) and above the ground.
func _avoid(pos: Vector3) -> Vector3:
	var p := pos
	if ground != null and is_instance_valid(ground):
		p.y = maxf(p.y, ground.global_position.y + ground_margin)
	for o in obstacles:
		var n: Node3D = o["node"]
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var c := n.global_position
		var r := float(o["radius"]) + 1.0
		var hl := float(o["half_len"])
		var nearest := c
		if hl > 0.0:
			var axis := n.global_transform.basis.y.normalized()
			nearest = c + axis * clampf((p - c).dot(axis), -hl, hl)
		var v := p - nearest
		var d := v.length()
		if d < r:
			p = nearest + (v / d if d > 0.001 else Vector3.UP) * r
	return p


# -------------------------------------------------------------------- input ------
func _unhandled_input(event: InputEvent) -> void:
	if not enabled or camera == null or not camera.is_inside_tree():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if mb.double_click:
						_focus_pick(mb.position)
					elif engaged or user_can_engage:
						_drag_l = true
						engage()
				else:
					_drag_l = false
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and (engaged or user_can_engage):
					_drag_r = true
					engage()
				elif not mb.pressed:
					_drag_r = false
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and (engaged or user_can_engage):
					engage()
					var k := 0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
					_dist_t = clampf(_dist_t * pow(k, maxf(mb.factor, 1.0)), min_dist, max_dist)
	elif event is InputEventMouseMotion and engaged:
		var mm := event as InputEventMouseMotion
		if _drag_l:
			yaw -= mm.relative.x * rotate_speed
			pitch = clampf(pitch + mm.relative.y * rotate_speed, pitch_min, pitch_max)
			_yaw_v = -mm.relative.x * rotate_speed * 55.0
			_pitch_v = mm.relative.y * rotate_speed * 55.0
			_yaw_goal = NAN
			_pitch_goal = NAN
		elif _drag_r:
			var basis := camera.global_transform.basis
			var s := dist * 0.0017
			_focus_t += (-basis.x * mm.relative.x + basis.y * mm.relative.y) * s
			focus = _focus_t
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_R and (engaged or user_can_engage):
			disengage()


func _focus_pick(screen: Vector2) -> void:
	var best: Dictionary = {}
	var best_r := INF
	var vp_h := camera.get_viewport().get_visible_rect().size.y
	var f := vp_h * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	for fb in focusables:
		var n: Node3D = fb["node"]
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if camera.is_position_behind(n.global_position):
			continue
		var d := camera.global_position.distance_to(n.global_position)
		var rpx := float(fb["radius"]) / maxf(d, 0.01) * f
		var sp := camera.unproject_position(n.global_position)
		if sp.distance_to(screen) <= maxf(rpx, 36.0) and rpx < best_r:
			best_r = rpx
			best = fb
	if best.is_empty():
		engage()
		_focus_t = _home_focus
		_dist_t = _home_dist
		return
	engage()
	var node: Node3D = best["node"]
	_focus_t = node.global_position
	_dist_t = clampf(float(best["dist"]), min_dist, max_dist)
	focused.emit(node)
