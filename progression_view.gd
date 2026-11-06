class_name ProgressionView
extends Control

signal weapon_selected(weapon: int)
signal notification_finished(id: String)
signal roster_intro_finished
signal closed

const WEAPON_ICON_SCRIPT := preload("res://weapon_icon.gd")
const PANEL := Color("101e29", 0.95)
const PANEL_EDGE := Color("55717d", 0.88)
const TEXT := Color("e1eeee")
const SUBTEXT := Color("a7b9bf")
const ACCENT := Color("75c9bd")
const GOLD := Color("e9c77a")
const LOCKED := Color("63737a")

var _model: Dictionary = {}
var _has_model := false
var _built := false
var _training := false
var _interactive := false
var _roster_requested := false
var _compact := false
var _overlay := ""
var _notifications_active := true
var _notification_queue: Array[Dictionary] = []
var _active_notification: Dictionary = {}
var _notification_time := 0.0
var _notification_phase := ""
var _notification_panel: PanelContainer
var _notification_title: Label
var _notification_name: Label
var _notification_description: Label
var _roster_panel: PanelContainer
var _roster_scroll: ScrollContainer
var _roster_list: VBoxContainer
var _roster_close_button: Button
var _achievement_button: Button
var _achievements_panel: PanelContainer
var _achievements_list: VBoxContainer
var _roster_intro_done := false
var _roster_intro_pending := false
var _intro_duration := 0.28
var _intro_elapsed := 0.0
var _notification_origin_y := 0.0
var _layout_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_layout()
	if _has_model:
		_apply_model()
	else:
		visible = false
	_start_next_notification()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()

func _process(delta: float) -> void:
	if not _notifications_active:
		return
	if _notification_phase == "intro":
		_notification_time += delta
		if bool(_model.get("effects_enabled", true)):
			var intro_progress := clampf(_notification_time / 0.24, 0.0, 1.0)
			_notification_panel.position.y = lerpf(_notification_origin_y, _notification_target_y(), intro_progress)
		if _notification_time >= 0.3:
			_notification_phase = "hold"
			_notification_time = 0.0
			_notification_panel.position.y = _notification_target_y()
			if not bool(_model.get("effects_enabled", true)):
				_notification_phase = "hold"
	elif _notification_phase == "hold":
		_notification_time += delta
		if _notification_time >= 3.0:
			_notification_phase = "outro"
			_notification_time = 0.0
	elif _notification_phase == "outro":
		_notification_time += delta
		if bool(_model.get("effects_enabled", true)):
			_notification_panel.modulate.a = 1.0 - clampf(_notification_time / 0.18, 0.0, 1.0)
			_notification_panel.position.y = lerpf(_notification_target_y(), _notification_origin_y, clampf(_notification_time / 0.18, 0.0, 1.0))
		if _notification_time >= 0.18:
			_finish_notification()
			_start_next_notification()
	if _roster_intro_pending and _notifications_active and _roster_panel.visible:
		_intro_elapsed += delta
		_intro_duration -= delta
		var intro_progress := clampf(_intro_elapsed / 0.28, 0.0, 1.0)
		_roster_panel.modulate.a = lerpf(0.65, 1.0, intro_progress)
		_roster_panel.position.x = _roster_target_x() + (18.0 * (1.0 - intro_progress) if bool(_model.get("effects_enabled", true)) else 0.0)
		if _intro_duration <= 0.0:
			_roster_intro_pending = false
			_roster_intro_done = true
			_intro_duration = 0.28
			_intro_elapsed = 0.0
			_roster_panel.position.x = _roster_target_x()
			roster_intro_finished.emit()

func refresh(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_has_model = true
	if not _built:
		return
	_apply_model()

func set_context(training: bool, interactive: bool, roster_visible: bool) -> void:
	var became_interactive := interactive and not _interactive
	_training = training
	_interactive = interactive
	_roster_requested = roster_visible
	if became_interactive:
		_overlay = "roster"
	elif not interactive and _overlay == "roster":
		_overlay = ""
	if _built:
		_apply_model()

func play_roster_intro() -> void:
	if _roster_intro_done:
		return
	_roster_intro_pending = true
	_intro_duration = 0.28
	_intro_elapsed = 0.0
	if not _roster_panel.visible:
		return
	_roster_panel.modulate.a = 0.65

func enqueue_notification(achievement: Dictionary) -> void:
	var queued := achievement.duplicate(true)
	if str(queued.get("id", "")).is_empty():
		return
	_notification_queue.append(queued)
	if _built:
		_start_next_notification()

func show_achievements() -> void:
	if not _built:
		_overlay = "achievements"
		return
	_overlay = "achievements"
	_achievements_panel.visible = true
	_roster_panel.visible = false
	visible = true
	_layout()

func close_overlay() -> void:
	if _overlay.is_empty():
		return
	var closing_roster := _overlay == "roster"
	_overlay = ""
	if closing_roster:
		_interactive = false
		_roster_requested = false
	if _built:
		_achievements_panel.visible = false
		_apply_model()
	closed.emit()

func is_overlay_open() -> bool:
	return not _overlay.is_empty()

func set_notifications_active(active: bool) -> void:
	_notifications_active = active

func _build() -> void:
	if _built:
		return
	_built = true
	_notification_panel = _make_panel(13)
	_notification_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notification_panel.visible = false
	add_child(_notification_panel)
	var banner := VBoxContainer.new()
	banner.add_theme_constant_override("separation", 2)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notification_panel.add_child(banner)
	_notification_title = _make_label(12, GOLD)
	_notification_title.text = "実績解除！"
	_notification_name = _make_label(18, TEXT)
	_notification_description = _make_label(13, SUBTEXT)
	for banner_label in [_notification_title, _notification_name, _notification_description]:
		banner_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		banner_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	banner.add_child(_notification_title)
	banner.add_child(_notification_name)
	banner.add_child(_notification_description)

	_roster_panel = _make_panel(9)
	_roster_panel.visible = false
	add_child(_roster_panel)
	var roster_column := VBoxContainer.new()
	roster_column.add_theme_constant_override("separation", 5)
	_roster_panel.add_child(roster_column)
	var heading := _make_label(15, ACCENT)
	heading.text = "武器と練習"
	var heading_row := HBoxContainer.new()
	heading_row.add_child(heading)
	var heading_spacer := Control.new()
	heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading_spacer)
	_roster_close_button = Button.new()
	_roster_close_button.text = "戻る"
	_roster_close_button.custom_minimum_size = Vector2(54, 27)
	_roster_close_button.pressed.connect(close_overlay)
	heading_row.add_child(_roster_close_button)
	roster_column.add_child(heading_row)
	_roster_list = VBoxContainer.new()
	_roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_list.add_theme_constant_override("separation", 4)
	_roster_scroll = ScrollContainer.new()
	_roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_column.add_child(_roster_scroll)
	_roster_scroll.add_child(_roster_list)
	_achievement_button = Button.new()
	_achievement_button.text = "実績一覧"
	_achievement_button.custom_minimum_size.y = 30
	_achievement_button.pressed.connect(show_achievements)
	roster_column.add_child(_achievement_button)

	_achievements_panel = _make_panel(12)
	_achievements_panel.visible = false
	_achievements_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_achievements_panel)
	var achievement_column := VBoxContainer.new()
	achievement_column.add_theme_constant_override("separation", 7)
	_achievements_panel.add_child(achievement_column)
	var top := HBoxContainer.new()
	var achievement_heading := _make_label(17, ACCENT)
	achievement_heading.text = "実績"
	top.add_child(achievement_heading)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(68, 30)
	close_button.pressed.connect(close_overlay)
	top.add_child(close_button)
	achievement_column.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	achievement_column.add_child(scroll)
	_achievements_list = VBoxContainer.new()
	_achievements_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_achievements_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_achievements_list)

func _apply_model() -> void:
	if not _built:
		return
	var rows: Array = _model.get("rows", [])
	var achievements: Array = _model.get("achievements", [])
	_rebuild_rows(rows)
	_rebuild_achievements(achievements)
	_roster_panel.visible = _roster_requested and (_overlay.is_empty() or _overlay == "roster" or _overlay == "achievements") and not rows.is_empty()
	if _overlay == "achievements":
		_roster_panel.visible = false
	_roster_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE if _training or not _interactive else Control.MOUSE_FILTER_STOP
	if _training:
		for control in _roster_panel.find_children("*", "Control", true, false):
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		_roster_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		_roster_scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_STOP
		_roster_close_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_achievement_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_roster_close_button.visible = _interactive and not _training
	_achievement_button.visible = _interactive and not _training
	_achievements_panel.visible = _overlay == "achievements"
	visible = _roster_panel.visible or _notification_panel.visible or _achievements_panel.visible
	_layout()

func _rebuild_rows(rows: Array) -> void:
	for child in _roster_list.get_children():
		_roster_list.remove_child(child)
		child.queue_free()
	var unlocked_count := 0
	for row in rows:
		if row is Dictionary and bool(row.get("unlocked", false)):
			unlocked_count += 1
	for index in rows.size():
		var row: Dictionary = rows[index]
		_roster_list.add_child(_make_weapon_row(row, index, unlocked_count))

func _make_weapon_row(row: Dictionary, index: int, unlocked_count: int) -> Control:
	var unlocked := bool(row.get("unlocked", false))
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("192a34", 0.84)
	style.border_color = Color("405964", 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(5.0)
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row_content := HBoxContainer.new()
	row_content.add_theme_constant_override("separation", 7)
	row_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row_content)
	var icon = WEAPON_ICON_SCRIPT.new()
	icon.weapon_id = int(row.get("id", 0))
	icon.locked = not unlocked
	icon.custom_minimum_size = Vector2(58, 38)
	row_content.add_child(icon)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 1)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_content.add_child(details)
	var name_label := _make_label(15, TEXT if unlocked else LOCKED)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.custom_minimum_size.y = 20
	name_label.text = str(row.get("name", "???")) if unlocked else "???"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(name_label)
	var subtitle := _make_label(11, SUBTEXT if unlocked else LOCKED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if unlocked:
		var title := str(row.get("title", ""))
		subtitle.text = title if _interactive and not title.is_empty() else ""
	else:
		var threshold := int(row.get("threshold", 0))
		var total := int(_model.get("total", 0))
		var remaining := maxi(0, threshold - total)
		subtitle.text = "達成 %d/%d・あと%d" % [total, threshold, remaining]
	if _training and unlocked:
		subtitle.visible = false
	details.add_child(subtitle)
	var description := _make_label(10, SUBTEXT)
	description.autowrap_mode = TextServer.AUTOWRAP_OFF
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.text = str(row.get("description", "")) if _interactive else ""
	description.visible = not description.text.is_empty()
	details.add_child(description)
	if unlocked and _interactive and not _training:
		var button := Button.new()
		button.text = "選ぶ"
		button.custom_minimum_size = Vector2(48, 30)
		button.pressed.connect(_select_weapon.bind(int(row.get("id", 0))))
		row_content.add_child(button)
	if not unlocked:
		box.modulate = Color(0.77, 0.83, 0.85, 0.88)
	box.custom_minimum_size.y = 52.0 if _training else 72.0
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row_content.custom_minimum_size.y = 40.0 if _training else 60.0
	return box

func _select_weapon(weapon: int) -> void:
	weapon_selected.emit(weapon)

func _rebuild_achievements(achievements: Array) -> void:
	for child in _achievements_list.get_children():
		_achievements_list.remove_child(child)
		child.queue_free()
	for achievement in achievements:
		if not achievement is Dictionary:
			continue
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 1)
		var title := _make_label(14, GOLD if bool(achievement.get("unlocked", false)) else LOCKED)
		title.text = str(achievement.get("title", "実績"))
		item.add_child(title)
		var description := _make_label(12, SUBTEXT)
		description.text = str(achievement.get("description", ""))
		item.add_child(description)
		var unlocked_at := str(achievement.get("unlocked_at", ""))
		if bool(achievement.get("unlocked", false)) and not unlocked_at.is_empty():
			var date := _make_label(10, LOCKED)
			date.text = unlocked_at
			item.add_child(date)
		_achievements_list.add_child(item)

func _start_next_notification() -> void:
	if not _built or _notification_phase != "" or _notification_queue.is_empty():
		return
	_active_notification = _notification_queue.pop_front()
	_notification_name.text = str(_active_notification.get("title", "実績解除"))
	_notification_description.text = str(_active_notification.get("description", ""))
	visible = true
	_notification_panel.visible = true
	_notification_panel.modulate.a = 1.0
	_notification_origin_y = 4.0
	_notification_panel.position.y = _notification_origin_y if bool(_model.get("effects_enabled", true)) else _notification_target_y()
	_notification_phase = "intro"
	_notification_time = 0.0
	if not bool(_model.get("effects_enabled", true)):
		_notification_panel.position.y = _notification_target_y()

func _finish_notification() -> void:
	_notification_panel.visible = false
	_notification_phase = ""
	_notification_time = 0.0
	var id := str(_active_notification.get("id", ""))
	_active_notification.clear()
	if not id.is_empty():
		notification_finished.emit(id)
	visible = _roster_panel.visible or _achievements_panel.visible or not _notification_queue.is_empty()

func _layout() -> void:
	if not _built:
		return
	var viewport := get_viewport_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	var narrow := viewport.x < 860.0
	var compact_now := narrow or viewport.y < 640.0
	var compact_changed := _compact != compact_now
	_compact = compact_now
	if compact_changed and _has_model:
		_rebuild_rows(_model.get("rows", []))
	var width := clampf(viewport.x * (0.24 if narrow else 0.205), 190.0, 278.0)
	if _interactive:
		width = minf(340.0, viewport.x - 32.0)
	if narrow:
		width = minf(width, viewport.x * 0.34)
	_roster_panel.size = Vector2(width, 0)
	_roster_panel.position = Vector2(_roster_target_x(), _roster_target_y())
	_roster_panel.custom_minimum_size.x = width
	var row_count := (_model.get("rows", []) as Array).size()
	var desired_row_height := 52.0 if _training else 72.0
	_roster_scroll.custom_minimum_size.y = clampf(float(row_count) * desired_row_height + float(maxi(0, row_count - 1)) * 4.0 + 4.0, 104.0, minf(viewport.y * 0.53, 390.0))
	_roster_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_notification_panel.custom_minimum_size.x = minf(330.0, viewport.x * 0.43)
	_notification_panel.size = Vector2(minf(330.0, viewport.x * 0.43), 0)
	_notification_panel.position = Vector2(viewport.x - _notification_panel.size.x - 18.0, _notification_target_y())
	var ach_width := minf(480.0, viewport.x - 32.0)
	var ach_height := minf(440.0, viewport.y - 32.0)
	_achievements_panel.size = Vector2(ach_width, ach_height)
	_achievements_panel.position = (viewport - _achievements_panel.size) * 0.5
	_layout_size = viewport

func _notification_target_y() -> float:
	return 32.0

func _roster_target_x() -> float:
	var viewport := get_viewport_rect().size
	return maxf(8.0, viewport.x - _roster_panel.size.x - 18.0)

func _roster_target_y() -> float:
	return maxf(92.0, get_viewport_rect().size.y * 0.21)

func _make_panel(padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = PANEL_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(float(padding))
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
