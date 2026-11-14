class_name UIKit
extends RefCounted
## Shared sci-fi UI theme (blue interface, orange accents) + small widget factories.

const C_PANEL := Color(0.035, 0.08, 0.16, 0.88)
const C_BORDER := Color("2f6fb8")
const C_ACCENT := Color("3da5ff")
const C_ACCENT_DIM := Color("163e6e")
const C_ORANGE := Color("ff8a2b")
const C_TEXT := Color("d8e8ff")
const C_MUTED := Color("7f9cc4")
const C_GOOD := Color("4dffb0")
const C_WARN := Color("ffc94d")
const C_BAD := Color("ff5a5a")

static var _theme: Theme


static func get_ui_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


static func box(bg: Color, border: Color, radius: int = 8, bw: int = 1, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	# Buttons
	t.set_stylebox("normal", "Button", box(Color(0.05, 0.12, 0.25, 0.9), C_BORDER, 8, 1, 10))
	t.set_stylebox("hover", "Button", box(Color(0.09, 0.22, 0.42, 0.95), C_ACCENT, 8, 2, 10))
	t.set_stylebox("pressed", "Button", box(Color(0.12, 0.3, 0.55, 1.0), C_ORANGE, 8, 2, 10))
	t.set_stylebox("disabled", "Button", box(Color(0.05, 0.07, 0.11, 0.8), Color(0.2, 0.25, 0.33), 8, 1, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", C_ORANGE)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.46, 0.55))
	t.set_font_size("font_size", "Button", 20)
	# Labels / panels
	t.set_color("font_color", "Label", C_TEXT)
	t.set_font_size("font_size", "Label", 18)
	t.set_stylebox("panel", "PanelContainer", box(C_PANEL, C_BORDER, 12, 1, 16))
	t.set_stylebox("panel", "Panel", box(C_PANEL, C_BORDER, 12, 1, 8))
	# Check box / slider / progress
	t.set_color("font_color", "CheckButton", C_TEXT)
	t.set_color("font_color", "CheckBox", C_TEXT)
	t.set_stylebox("slider", "HSlider", box(Color(0.1, 0.18, 0.32), Color(0.1, 0.18, 0.32), 4, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(C_ACCENT, C_ACCENT, 4, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(C_ORANGE, C_ORANGE, 4, 0, 3))
	t.set_stylebox("background", "ProgressBar", box(Color(0.03, 0.06, 0.12, 0.9), Color(0.18, 0.3, 0.5), 4, 1, 2))
	t.set_stylebox("fill", "ProgressBar", box(C_ACCENT, C_ACCENT, 4, 0, 2))
	t.set_color("font_color", "ProgressBar", C_TEXT)
	return t


# ------------------------------------------------------------- factories ----
static func label(key: String, size: int = 18, color: Color = C_TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = key
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(key: String, min_size: Vector2 = Vector2(240, 50)) -> Button:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.play("click"))
	b.mouse_entered.connect(func(): Sfx.play("hover", -10.0))
	return b


static func panel() -> PanelContainer:
	return PanelContainer.new()


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## Small "key cap" chip used in control lists.
static func keycap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(0.1, 0.2, 0.38), C_ACCENT, 6, 1, 6))
	var l := label(text, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size.x = 28
	p.add_child(l)
	return p


static func progress_bar(color: Color = C_ACCENT, min_size: Vector2 = Vector2(180, 14)) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = min_size
	b.min_value = 0.0
	b.max_value = 100.0
	b.add_theme_stylebox_override("fill", box(color, color, 4, 0, 2))
	return b


static func set_bar_color(b: ProgressBar, color: Color) -> void:
	b.add_theme_stylebox_override("fill", box(color, color, 4, 0, 2))

