extends Node3D
## TEMPORARY main menu (Play / Missions / Settings / Exit) over the cinematic 3D launch pad.
## Replace it with the final menu - see the note at the top of Core/router.gd.


func _ready() -> void:
	var bg := MenuBackdrop3D.new()
	bg.view_name = "hero"
	add_child(bg)

	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.theme = UIKit.get_ui_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	# dark gradient on the left so the text always reads
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.01, 0.02, 0.05, 0.82), Color(0.01, 0.02, 0.05, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 760
	root.add_child(shade)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	root.add_child(margin)
	var v := UIKit.vbox(12)
	margin.add_child(v)

	var title := UIKit.label("GAME_TITLE", 120, Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.35, 0.8, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	title.add_theme_constant_override("shadow_offset_y", 8)
	v.add_child(title)
	var tag := UIKit.label("GAME_TAGLINE", 22, UIKit.C_ORANGE)
	v.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size.y = 36
	v.add_child(gap)

	var entries := [
		["MENU_PLAY", Router.play],
		["MENU_MISSIONS", func(): Router.go_to(Router.MISSION_SELECT)],
		["MENU_SETTINGS", func(): Router.go_to(Router.SETTINGS)],
		["MENU_EXIT", func(): get_tree().quit()],
	]
	for i in entries.size():
		var b := UIKit.button(entries[i][0], Vector2(340, 58))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(entries[i][1])
		v.add_child(b)
		b.modulate.a = 0.0
		b.position.x -= 60.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(b, "modulate:a", 1.0, 0.5).set_delay(0.35 + 0.12 * i)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(UIKit.label("MENU_FOOTER", 14, UIKit.C_MUTED))

	var cam_hint := CameraHint.new()
	root.add_child(cam_hint)
	cam_hint.setup(false, -1.0, true)
	title.modulate.a = 0.0
	tag.modulate.a = 0.0
	create_tween().tween_property(title, "modulate:a", 1.0, 1.2)
	create_tween().tween_property(tag, "modulate:a", 1.0, 1.8)


