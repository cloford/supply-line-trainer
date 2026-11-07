class_name V2Interface
extends RefCounted

static func button(parent:Node, text:String, action:Callable, primary:bool = false)->Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary:
		control.theme_type_variation = "PrimaryButton"
		control.custom_minimum_size.y = 44
	parent.add_child(control)
	return control

static func icon_button(parent:Node, text:String, icon_id:String, action:Callable, primary:bool = false, tooltip:String = "")->Button:
	var control := button(parent, text, action, primary)
	control.tooltip_text = tooltip if not tooltip.is_empty() else text
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		control.add_theme_color_override(state, Color(0,0,0,0))
	var icon := UIIcon.new()
	icon.icon_id = icon_id
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon.offset_left = -32
	icon.offset_right = 32
	icon.offset_top = -32
	icon.offset_bottom = 32
	control.add_child(icon)
	return control

static func set_icon_state(control:Button, icon_id:String, selected:bool = false, disabled:bool = false)->void:
	for child in control.get_children():
		if child is UIIcon:
			child.icon_id = icon_id
			child.selected = selected
			child.disabled = disabled
			return

static func _decorate_icon(control:Button, icon_id:String, tooltip:String, left_aligned:bool = true)->void:
	control.tooltip_text = tooltip
	var icon := UIIcon.new()
	icon.icon_id = icon_id
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if left_aligned else Control.PRESET_CENTER)
	if left_aligned:
		icon.offset_left = 9
		icon.offset_right = 45
		icon.offset_top = -18
		icon.offset_bottom = 18
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
			var old_style := control.get_theme_stylebox(state)
			if old_style == null:
				continue
			var style := old_style.duplicate() as StyleBox
			style.content_margin_left = maxf(style.content_margin_left, 52.0)
			control.add_theme_stylebox_override(state, style)
	else:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color"]:
			control.add_theme_color_override(state, Color(0,0,0,0))
		icon.offset_left = -24
		icon.offset_right = 24
		icon.offset_top = -24
		icon.offset_bottom = 24
	control.add_child(icon)

static func set_weapon_button(control: Button, weapon: int, unlocked: bool, selected: bool, display_text: String = "") -> void:
	# Locked choices deliberately reveal neither their names nor silhouettes with detail.
	control.text = ("✓ " if selected else "") + (display_text if unlocked else "???\n累計%d達成で解放" % Progression.THRESHOLDS[weapon])
	var icon: WeaponIcon
	for child in control.get_children():
		if child is WeaponIcon:
			icon = child
			break
	if icon == null:
		icon = WeaponIcon.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.add_child(icon)
		# Reserve a real text area so long unlocked names cannot overlap the icon.
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
			var style := control.get_theme_stylebox(state).duplicate() as StyleBox
			style.content_margin_left = 84.0
			style.content_margin_right = 12.0
			control.add_theme_stylebox_override(state, style)
	icon.weapon_id = weapon
	icon.locked = not unlocked
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	icon.offset_left = 12
	icon.offset_right = 74
	icon.offset_top = -20
	icon.offset_bottom = 20
	icon.custom_minimum_size = Vector2(62, 40)
	icon.queue_redraw()

static func label(parent:Node, text:String, size:int = 16)->Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_size_override("font_size", size)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(control)
	return control

static func column(parent:Node, separation:int = 8)->VBoxContainer:
	var control := VBoxContainer.new()
	control.add_theme_constant_override("separation", separation)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)
	return control

static func page(g, color:String = "09151e")->Control:
	var control := ColorRect.new()
	control.color = Color(color)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.ui.add_child(control)
	return control

static func margin(parent:Control, bottom:int = 90)->MarginContainer:
	var control := MarginContainer.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top"]:
		control.add_theme_constant_override("margin_" + side, 24)
	control.add_theme_constant_override("margin_bottom", bottom)
	parent.add_child(control)
	return control

static func build(g)->void:
	g.ui = CanvasLayer.new()
	g.add_child(g.ui)
	_build_prep(g)
	_build_army(g)
	_build_hud(g)
	_build_result(g)
	g.records_view = V2Records.new()
	g.records_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.ui.add_child(g.records_view)
	g.records_view.closed.connect(g._show_prep)
	g.records_view.record_selected.connect(g._open_history_record)
	g.records_view.hide()
	g.pause_panel = g._build_pause_panel()
	g.ui.add_child(g.pause_panel)
	g.goal_display_check.hide()
	g.goal_notice_check.hide()
	g.effects_check = CheckBox.new()
	g.effects_check.text = "部隊・標的出現の音と強い演出"
	g.effects_check.toggled.connect(func(_value): g._settings_changed())
	g.setting_sections[2].add_child(g.effects_check)
	label(g.setting_sections[0], "60秒測定中の設定適用は現在の測定を途中終了し、新条件で測定を開始します。", 14)
	g._build_navigation()
	_decorate_navigation(g)
	g._build_info_panel()
	g._build_condition_picker()
	g.condition_measure = CheckBox.new()
	g.condition_measure.text = "60秒測定（難易度は固定）"
	g.condition_measure.toggled.connect(func(_value): g._refresh_condition_picker())
	g.condition_card.get_child(0).add_child(g.condition_measure)
	var theme := TrainerTheme.create()
	for control in g.ui.get_children():
		if control is Control:
			control.theme = theme

static func _build_prep(g)->void:
	g.prep_panel = g._panel()
	g.prep_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.ui.add_child(g.prep_panel)
	var body := column(margin(g.prep_panel), 10)
	label(body, "AIM RUNNER  /  " + SupplyLineUpdater.current_version(), 20)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var content := column(center)
	content.custom_minimum_size.x = 880
	label(content, "一つ撃つところから、次の練習へ", 26)
	var modes := HBoxContainer.new()
	content.add_child(modes)
	g.free_button = icon_button(modes, "自由練習 — 無制限", "play", g._select_measurement.bind(false), true, "自由練習")
	g.free_button.custom_minimum_size = Vector2(112, 92)
	g.measure_button = icon_button(modes, "兵士を作る — 60秒測定", "lock", g._select_measurement.bind(true), false, "兵士の60秒測定。解放後に選べます")
	g.measure_button.custom_minimum_size = Vector2(76, 64)
	# The prep screen presents one large play action; the measurement entry lives in Tab.
	modes.hide()
	g.training_kind_info = label(content, "", 15)
	g.training_kind_info.hide()
	var weapons := GridContainer.new()
	weapons.columns = 3
	content.add_child(weapons)
	for weapon in 5:
		var control := button(weapons, "", g._select_weapon.bind(weapon))
		control.toggle_mode = true
		control.custom_minimum_size = Vector2(272, 62)
		g.weapon_buttons.append(control)
	weapons.hide()
	g.difficulty_row = HBoxContainer.new()
	content.add_child(g.difficulty_row)
	for difficulty in 3:
		var control := button(g.difficulty_row, Balance.DIFFICULTY[difficulty].name, g._select_difficulty.bind(difficulty))
		control.toggle_mode = true
		g.difficulty_buttons.append(control)
	g.difficulty_row.hide()
	g.difficulty_info = label(content, "", 14)
	g.difficulty_info.hide()
	g.start_button = icon_button(content, "自由練習を開始", "play", g._request_start, true, "自由練習を開始")
	g.start_button.custom_minimum_size.y = 88
	g.condition_label = label(content, "", 15)
	g.condition_label.hide()
	g.prep_goal = label(content, "", 16)
	g.prep_goal.add_theme_color_override("font_color", Color("91d6d0"))
	g.migration_label = label(body, "", 15)
	g.migration_retry = button(body, "設定引継ぎ・保存を再試行", g._retry_migration)
	g.migration_ack = button(body, "説明を確認して続ける", g._ack_migration)
	g.update_hint = button(body, "更新の準備ができました — 更新情報へ", g._open_update_info)
	g.update_hint.hide()

static func _decorate_navigation(g)->void:
	var nav_icons := ["play", "squad", "history"]
	var nav_tips := ["練習へ", "部隊と戦線", "練習記録"]
	for i in mini(g.navigation_buttons.size(), nav_icons.size()):
		var control:Button = g.navigation_buttons[i]
		control.custom_minimum_size = Vector2(126, 56)
		control.add_theme_font_size_override("font_size", 14)
		_decorate_icon(control, nav_icons[i], nav_tips[i], false)
	var row:HBoxContainer = g.navigation.get_child(0)
	var controls:Array = row.get_children()
	if controls.size() >= 7:
		for index in [4, 5, 6]:
			controls[index].custom_minimum_size = Vector2(56, 56)
		_decorate_icon(controls[4], "settings", "設定", false)
		_decorate_icon(controls[5], "help", "ヘルプと操作方法", false)
		_decorate_icon(controls[6], "feedback", "意見を送る", false)

static func _build_army(g)->void:
	g.army_panel = page(g)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin(g.army_panel).add_child(columns)
	var left_card = g._panel()
	left_card.custom_minimum_size.x = 390
	left_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_card.size_flags_stretch_ratio = 0.4
	columns.add_child(left_card)
	var left := column(left_card, 7)
	g.army_title = label(left, "三人の遠征隊", 24)
	g.supply_label = label(left, "", 17)
	g.power_label = label(left, "", 15)
	var slots := HBoxContainer.new()
	left.add_child(slots)
	for weapon in 3:
		var control := button(slots, "", g._select_soldier.bind(weapon))
		control.toggle_mode = true
		g.slot_buttons.append(control)
	g.profile_name = LineEdit.new()
	g.profile_name.max_length = 24
	g.profile_name.placeholder_text = "名前（任意）"
	g.profile_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var naming := HBoxContainer.new()
	left.add_child(naming)
	naming.add_child(g.profile_name)
	button(naming, "保存", g._save_name)
	g.soldier_summary = label(left, "", 17)
	g.soldier_flavor = label(left, "", 14)
	g.armor_summary = label(left, "", 14)
	g.protection_button = button(left, "", g._purchase_protection)
	g.deployed_check = CheckBox.new()
	g.deployed_check.text = "この固定枠から出撃（次区間で反映）"
	g.deployed_check.toggled.connect(g._toggle_deployed)
	left.add_child(g.deployed_check)
	var extras := HBoxContainer.new()
	left.add_child(extras)
	button(extras, "プロフィール詳細", g._open_soldier_details)
	g.revert_button = button(extras, "直前の採用へ戻す", g._revert_profile)
	g.army_message = label(left, "", 14)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var right := column(columns)
	right.size_flags_stretch_ratio = 0.6
	g.front_label = label(right, "", 20)
	g.battle_summary = label(right, "", 15)
	g.diorama = load("res://v2_diorama.gd").new()
	g.diorama.custom_minimum_size = Vector2(520, 330)
	g.diorama.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(g.diorama)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	g.retry_battle_button = icon_button(actions, "無料で再挑戦", "play", g._retry_battle, true, "この戦線へ再挑戦")
	g.retry_battle_button.custom_minimum_size = Vector2(72, 58)
	g.continue_button = button(actions, "継続戦線へ進む", g._continue_battle)
	label(right, "実戦：記録の発射リズム × 実測命中率。短期の命中率は毎回変わります。", 14)
	g.army_resume = icon_button(right, "同じ練習に戻る", "play", g._resume_from_army, true, "同じ練習に戻る")
	g.army_resume.custom_minimum_size = Vector2(72, 58)
	g.army_end = icon_button(right, "この練習を終了して結果へ", "stop", g._finish_from_army, false, "この練習を終了して結果を見る")
	g.army_end.custom_minimum_size = Vector2(64, 52)

static func _build_hud(g)->void:
	g.hud = Control.new()
	g.hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.ui.add_child(g.hud)
	var stack := column(g.hud, 6)
	stack.position = Vector2(24, 20)
	stack.custom_minimum_size.x = 440
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.timer_label = label(stack, "", 16)
	g.stat_label = label(stack, "", 20)
	g.credit_hud = label(stack, "", 15)
	g.countdown_label = label(stack, "", 18)
	g.intention_label = label(stack, "", 15)
	g.goal_hud = label(stack, "", 14)
	g.goal_notification = label(stack, "", 14)
	g.hit_label = label(g.hud, "", 15)
	g.hit_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	g.hit_label.offset_left = 24
	g.hit_label.offset_right = 780
	g.hit_label.offset_top = -58
	g.hit_label.offset_bottom = -18
	g.crosshair = AimCrosshair.new()
	g.crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.hud.add_child(g.crosshair)
	# Presentation-only overlay. Kept in the HUD subtree so pause UI stays above it.
	g.countdown_display = load("res://countdown_display.gd").new()
	g.hud.add_child(g.countdown_display)
	g.exit_ring = load("res://exit_ring.gd").new()
	g.exit_ring.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	g.exit_ring.offset_left = 24
	g.exit_ring.offset_right = 60
	g.exit_ring.offset_top = -116
	g.exit_ring.offset_bottom = -80
	g.hud.add_child(g.exit_ring)
	g.exit_hint = label(g.hud, "離すとキャンセル", 15)
	g.exit_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	g.exit_hint.offset_left = 70
	g.exit_hint.offset_right = 350
	g.exit_hint.offset_top = -110
	g.exit_hint.offset_bottom = -80
	g.exit_ring.hide()
	g.exit_hint.hide()
	g.goal_hud.hide()
	g.goal_notification.hide()

static func _build_result(g)->void:
	var parts:Array = g._modal_overlay(1100)
	g.result_panel = parts[0]
	g.result_card = parts[1]
	g.ui.add_child(g.result_panel)
	var body := column(g.result_card, 8)
	g.result_title = label(body, "測定結果", 25)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)
	var left := column(columns)
	left.size_flags_stretch_ratio = 0.48
	g.replay_label = label(left, "記録の再現（実測の発射・命中・外れ）", 16)
	g.replay_diorama = load("res://v2_diorama.gd").new()
	g.replay_diorama.custom_minimum_size = Vector2(430, 240)
	left.add_child(g.replay_diorama)
	var replay_actions := HBoxContainer.new()
	left.add_child(replay_actions)
	g.replay_button = icon_button(replay_actions, "記録を再生", "play", g._restart_replay, false, "記録を再生")
	g.replay_button.custom_minimum_size = Vector2(68, 54)
	g.skip_replay_button = button(replay_actions, "再現をスキップ", g._skip_replay)
	g.trial_button = button(left, "兵士の試射：現在と候補を比較", g._start_trial)
	var right := column(columns)
	g.result_detail = label(right, "", 15)
	g.result_values = label(right, "", 20)
	g.result_comparison = label(right, "", 15)
	g.result_review = ShootingReview.new()
	right.add_child(g.result_review)
	g.result_points = label(right, "", 20)
	g.result_wallet = label(right, "", 14)
	button(right, "詳細・計算条件", g._open_v2_result_details)
	g.result_flavor = label(body, "", 17)
	g.adopt_button = icon_button(body, "この記録を採用", "squad", g._adopt_result, true, "この記録から兵士を作る")
	g.adopt_button.custom_minimum_size.y = 64
	g.result_message = label(body, "", 14)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	button(actions, "同じ条件でもう一度", g._retry_training, true)
	button(actions, "自由練習・条件選択へ", g._show_prep)
	button(actions, "部隊へ", g._show_army)
	g.intention_option = OptionButton.new()
	g.intention_option.add_item("指定なし")
	g.intention_option.hide()
	body.add_child(g.intention_option)
	g.result_panel.hide()
