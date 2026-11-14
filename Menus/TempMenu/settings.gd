extends Node3D
## Settings over the 3D launch pad. The ONLY place where the language can be changed.

var _reset_armed := false
var _reset_btn: Button


func _ready() -> void:
	var bg := MenuBackdrop3D.new()
	bg.view_name = "settings"
	add_child(bg)
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.theme = UIKit.get_ui_theme()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(screen)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.add_theme_constant_override("margin_right", 700)
	screen.add_child(margin)
	var p := UIKit.panel()
	margin.add_child(p)
	var v := UIKit.vbox(14)
	p.add_child(v)
	v.add_child(UIKit.label("SET_TITLE", 40, Color.WHITE))
	v.add_child(HSeparator.new())

	# Language
	v.add_child(UIKit.label("SET_LANGUAGE", 20, UIKit.C_ACCENT))
	var lang_row := UIKit.hbox(12)
	v.add_child(lang_row)
	var group := ButtonGroup.new()
	for code in Loc.LOCALES:
		var b := Button.new()
		b.text = str(Loc.LOCALE_NAMES[code])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(190, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = (Loc.current() == code)
		b.pressed.connect(_on_lang.bind(code))
		lang_row.add_child(b)

	# Volume
	v.add_child(UIKit.label("SET_VOLUME", 20, UIKit.C_ACCENT))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(GameState.settings["volume"])
	slider.custom_minimum_size = Vector2(0, 26)
	slider.value_changed.connect(func(val: float): GameState.set_setting("volume", val))
	v.add_child(slider)

	v.add_child(_toggle("SET_FULLSCREEN", "fullscreen"))
	v.add_child(_toggle("SET_SHAKE", "shake"))
	v.add_child(_toggle("SET_UNLOCK_ALL", "unlock_all"))

	_reset_btn = UIKit.button("SET_RESET", Vector2(0, 46))
	_reset_btn.pressed.connect(_on_reset)
	v.add_child(_reset_btn)

	var back := UIKit.button("BTN_BACK", Vector2(200, 48))
	back.pressed.connect(func(): Router.go_to(Router.MAIN_MENU))
	v.add_child(back)
	var cam_hint := CameraHint.new()
	screen.add_child(cam_hint)
	cam_hint.setup(false, -1.0, true)


func _toggle(key: String, setting: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = key
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(GameState.settings[setting])
	c.toggled.connect(func(on: bool): GameState.set_setting(setting, on))
	return c


func _on_lang(code: String) -> void:
	GameState.set_setting("locale", code)


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = "SET_RESET_CONFIRM"
		return
	_reset_armed = false
	GameState.reset_progress()
	_reset_btn.text = "SET_RESET"

