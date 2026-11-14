class_name RingMarker3D
extends MeshInstance3D
## Flat glowing ring (+ optional progress arc) drawn by a shader on a quad that faces +Z.

var _mat: ShaderMaterial
var _t := randf() * 6.0
var pulse_speed := 4.0


func _init() -> void:
	var q := QuadMesh.new()
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://Core3D/shaders/ring3d.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_size(diameter: float) -> void:
	(mesh as QuadMesh).size = Vector2(diameter, diameter)


func set_color(c: Color) -> void:
	_mat.set_shader_parameter("col", c)


func set_progress(p: float) -> void:
	_mat.set_shader_parameter("progress", p)


func _process(delta: float) -> void:
	_t += delta * pulse_speed
	_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_t))
