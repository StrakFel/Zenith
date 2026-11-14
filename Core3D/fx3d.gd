class_name Fx3D
extends RefCounted
## Small factory for the particle systems / materials used by the 3D scenes.

static var _soft: GradientTexture2D


## Soft round sprite used by every billboard particle.
static func soft_tex() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func billboard_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func gradient_tex(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


## A ready-to-configure GPU particle system with a soft billboard quad.
static func particles(amount: int, lifetime: float, quad: float, additive: bool, local: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = local
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-400, -800, -400), Vector3(800, 1000, 800))
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	q.material = billboard_mat(additive)
	p.draw_pass_1 = q
	p.process_material = ParticleProcessMaterial.new()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func pmat(p: GPUParticles3D) -> ParticleProcessMaterial:
	return p.process_material as ParticleProcessMaterial


## One-shot glowing burst (sparks / impact / repair). Frees itself afterwards.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 60, speed: float = 18.0,
		size: float = 1.2, life: float = 1.2) -> void:
	var p := particles(amount, life, size, true, false)
	var pm := pmat(p)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.3
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.damping_min = speed * 0.4
	pm.damping_max = speed * 0.9
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = gradient_tex([Color(color.r, color.g, color.b, 0.0), Color(color.r, color.g, color.b, 0.9),
		Color(color.r, color.g, color.b, 0.0)], [0.0, 0.1, 1.0])
	pm.scale_curve = curve_tex([Vector2(0, 1), Vector2(1, 0.2)])
	p.one_shot = true
	p.explosiveness = 1.0
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tm := parent.get_tree().create_timer(life + 0.5)
	tm.timeout.connect(p.queue_free)
