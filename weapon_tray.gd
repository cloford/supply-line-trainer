class_name WeaponTray
extends Control

var panel: PanelContainer
var weapon_buttons: Array[Button] = []
var measure_button: Button
var error_label: Label
var edit_button: Button
var stop_button: Button
var progress_label: Label
var _tween: Tween
const WIDTH := 350.0

func build(g) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = TrainerTheme.create()
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = 0.0
	panel.offset_right = WIDTH
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("0c1a24")
	surface.border_color = Color("355467")
	surface.border_width_left = 1
	panel.add_theme_stylebox_override("panel", surface)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	var heading := Label.new()
	heading.text = "武器・練習"
	heading.add_theme_font_size_override("font_size", 21)
	col.add_child(heading)
	progress_label = V2Interface.label(col, "", 15)
	var rows := VBoxContainer.new()
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	col.add_child(rows)
	for weapon in 5:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(g._tab_choose_weapon.bind(weapon))
		rows.add_child(b)
		weapon_buttons.append(b)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	col.add_child(actions)
	edit_button = Button.new()
	edit_button.text = "ターゲット編集"
	edit_button.pressed.connect(g._open_target_editor)
	actions.add_child(edit_button)
	measure_button = Button.new()
	measure_button.text = "兵士作成（60秒測定）"
	measure_button.pressed.connect(g._tab_start_measurement)
	actions.add_child(measure_button)
	stop_button = Button.new()
	stop_button.text = "練習終了"
	stop_button.pressed.connect(g._tab_stop)
	actions.add_child(stop_button)
	for button in [edit_button, measure_button, stop_button]:
		button.custom_minimum_size.y = 40.0
		button.focus_mode = Control.FOCUS_NONE
	error_label = Label.new()
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(error_label)
	for control in panel.find_children("*", "Control", true, false):
		if not control is Button:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func present(open: bool, animate: bool = true) -> void:
	if _tween and _tween.is_running(): _tween.kill()
	if open: show()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	for button in weapon_buttons + [edit_button, measure_button, stop_button]:
		button.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	var destination := -WIDTH if open else 0.0
	if animate:
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(panel, "offset_left", destination, 0.18)
		_tween.parallel().tween_property(panel, "offset_right", destination + WIDTH, 0.18)
		if not open: _tween.tween_callback(hide)
	else:
		panel.offset_left = destination
		panel.offset_right = destination + WIDTH
		visible = open

func refresh(data: Dictionary, training_weapon: int, training_measurement: bool = false) -> void:
	if not is_node_ready():
		call_deferred("refresh", data, training_weapon, training_measurement)
		return
	var progression := Progression.total(data)
	progress_label.text = "累計達成 %d" % progression
	for weapon in 5:
		var unlocked := Progression.unlocked(data, weapon)
		var button := weapon_buttons[weapon]
		var selected := weapon == training_weapon
		var title: String = TrainingCatalog.NAMES[weapon] if unlocked else "???"
		V2Interface.set_weapon_button(button, weapon, unlocked, selected, title)
		if not unlocked:
			var threshold: int = Progression.THRESHOLDS[weapon]
			button.text = "???\n累計 %d達成・あと %d" % [threshold, maxi(0, threshold - progression)]
		button.disabled = not unlocked
		button.set_pressed_no_signal(selected)
		button.tooltip_text = button.text
	measure_button.disabled = training_weapon >= 3 or not Progression.measurement_unlocked(data)
	edit_button.disabled = training_measurement or training_weapon == 4

func set_error(message: String) -> void:
	error_label.text = message
	error_label.visible = not message.is_empty()
