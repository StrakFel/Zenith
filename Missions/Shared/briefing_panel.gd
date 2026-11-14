class_name BriefingPanel
extends OverlayFrame
## Mission briefing: objectives + controls in a scroll area, with Back / Start mission buttons
## pinned below it. ESC = back, Enter = start. Adapts to any screen size.

signal started
signal back_requested

var _grid: GridContainer
var _age := 0.0
var _closing := false


## objectives: Array of translation keys. controls: Array of [keycap_text, description_key].
func setup(title_key: String, objectives: Array, controls: Array) -> void:
	build(900.0, 0.9)
	header.add_child(UIKit.label("BRIEF_TITLE", 15, UIKit.C_ORANGE))
	var title := UIKit.label(title_key, 32, Color.WHITE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)

	body.add_child(UIKit.label("BRIEF_OBJECTIVES", 20, UIKit.C_ACCENT))
	for o in objectives:
		var l := UIKit.label(str(o), 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(l)
	body.add_child(UIKit.label("BRIEF_CONTROLS", 20, UIKit.C_ACCENT))
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_grid)
	for c in controls:
		var pair: Array = c
		var keys := UIKit.hbox(4)
		for k in str(pair[0]).split(" "):
			keys.add_child(UIKit.keycap(k))
		keys.custom_minimum_size.x = 120
		_grid.add_child(keys)
		var d := UIKit.label(str(pair[1]), 15, UIKit.C_MUTED)
		d.custom_minimum_size.x = 150
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(d)

	var back := UIKit.button("BTN_BACK", Vector2(180, 50))
	back.name = "BackButton"
	back.pressed.connect(_on_back)
	footer.add_child(back)
	var start := UIKit.button("BTN_START", Vector2(260, 50))
	start.name = "StartButton"
	start.pressed.connect(_on_start)
	footer.add_child(start)
	resized.connect(_adapt_columns)
	_adapt_columns()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)


## Narrow screens: key | description pairs stack in two columns instead of four.
func _adapt_columns() -> void:
	if _grid != null:
		_grid.columns = 4 if size.x >= 880.0 else 2


func _process(delta: float) -> void:
	_age += delta


func _unhandled_input(event: InputEvent) -> void:
	if _closing or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			_on_back()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if _age > 0.5:   # ignore the Enter that opened the mission
				_on_start()
				get_viewport().set_input_as_handled()


func _on_start() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	await tw.finished
	started.emit()
	queue_free()


func _on_back() -> void:
	if _closing:
		return
	_closing = true
	back_requested.emit()
