extends "res://v2_game.gd"

# 0.21のFPS種目と進行接続。兵士は既存3固定枠のまま。
var progression_view:ProgressionView
var progress_dirty := true
var progress_retry_clock := 1.0
var pending_weapon := -1
var roster_open := false
var grid_bag:Array[int] = []
var grid_previous := -1
var grid_switches:Array[float] = []
var extra_rng := RandomNumberGenerator.new()
var projectiles:Array[Dictionary] = []
var projectile_nodes:Dictionary = {}
var grenade_events:Array[Dictionary] = []
var grenade_serial := 0
var grenade_generation := 0
var group_respawn := -1.0
var blast_effects:Array[Dictionary] = []
var trajectory:MeshInstance3D
var trajectory_timer := 0.0
var extra_result:Label
var progress_context:Array = []
var save_worker := V2SaveWorker.new()
var iris_intro:IrisIntro
var spawn_audio:SpawnAudio
var intro_hint:Label
var intro_session := false
var intro_first_spawn := false
var sound_cache:Dictionary = {}
var async_save_warning := false
var countdown_display:CountdownDisplay
var durable_busy := false
var busy_panel:Control
var busy_label:Label
var boot_error := false
var boot_notice := false
var boot_launching := false
var presentation_ready := false
var presentation_serial := 0
var countdown_first_frame := false
var phase_shoot_held := false
var boot_retry:Button
var close_requested := false
enum Interaction { NONE, TAB, TARGET_EDIT, MAIN_TARGET_EDIT, RESET_TOOLS, RESET_CONFIRM, RESETTING }
var interaction := Interaction.NONE
var tab_resume_mode := Mode.TRAINING
var tab_held := false
var tab_panel:WeaponTray
var tab_weapons:Array[Button] = []
var tab_measure:Button
var target_editor:Control
var target_slider:HSlider
var target_preview:Control
var target_values:Label
var target_error:Label
var draft_risk := TargetScoring.DEFAULT_RISK
var training_risk := TargetScoring.DEFAULT_RISK
var reset_panel:Control
var reset_confirm:Control
var reset_error:Label
var reset_thread:Thread
var switch_in_progress := false
var credit_feedback_amount := 0
var tab_error:Label
var tab_hint:Label
var reset_partial := false

func _ready()->void:
	super._ready()
	feedback_url = ReleaseVersion.FEEDBACK_URL
	DisplayServer.window_set_title("Aim Runner " + SupplyLineUpdater.current_version())
	_update_progress_ui()
	_build_sound_cache()
	if not is_test_mode:
		_begin_boot()

func _build_ui()->void:
	super._build_ui()
	var prep_actions := HBoxContainer.new()
	start_button.get_parent().add_child(prep_actions)
	start_button.get_parent().move_child(prep_actions, start_button.get_index() + 1)
	V2Interface.button(prep_actions, "ターゲット編集", _open_main_target_editor, true)
	V2Interface.button(prep_actions, "実績一覧", _open_achievements)
	V2Interface.button(pause_menu, "実績一覧", _open_achievements)
	for control in pause_menu.get_children():
		if control is Button and control.text == "練習条件を変更":control.hide()
	progression_view = ProgressionView.new()
	ui.add_child(progression_view)
	progression_view.theme = TrainerTheme.create()
	progression_view.weapon_selected.connect(_choose_roster_weapon)
	progression_view.closed.connect(_close_progress_overlay)
	spawn_audio = SpawnAudio.new()
	add_child(spawn_audio)
	spawn_audio.configure(data.settings)
	iris_intro = IrisIntro.new()
	ui.add_child(iris_intro)
	ui.move_child(iris_intro,0)
	iris_intro.finished.connect(_complete_intro)
	intro_hint = V2Interface.label(ui, "中央の標的を撃って開始 ／ Enterでスキップ", 17)
	intro_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	intro_hint.offset_left = -245
	intro_hint.offset_right = 245
	intro_hint.offset_top = -64
	intro_hint.offset_bottom = -36
	intro_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_hint.hide()
	extra_result = V2Interface.label(replay_diorama.get_parent(), "", 18)
	extra_result.custom_minimum_size = Vector2(400, 180)
	replay_diorama.get_parent().move_child(extra_result, replay_diorama.get_index() + 1)
	extra_result.hide()
	_build_busy_panel()
	_build_session_controls()

func _build_busy_panel()->void:
	busy_panel = ColorRect.new()
	busy_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	busy_panel.color = Color(0.02,0.03,0.04,0.88)
	busy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(busy_panel)
	busy_label = V2Interface.label(busy_panel,"保存しています…",28)
	busy_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	busy_label.offset_left = -340
	busy_label.offset_right = 340
	busy_label.offset_top = -60
	busy_label.offset_bottom = 60
	busy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_retry = V2Interface.button(busy_panel,"保存を再読み込み",_boot_retry_action)
	boot_retry.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	boot_retry.offset_left = -130
	boot_retry.offset_right = 130
	boot_retry.offset_top = 110
	boot_retry.offset_bottom = 160
	boot_retry.hide()
	busy_panel.hide()

func _commit(candidate:Dictionary)->bool:
	if bool(data.get("migration_failed",false)) or durable_busy:
		return false
	if is_test_mode:
		data = candidate
		combat.set_data(data)
		progress_dirty = true
		return true
	durable_busy = true
	boot_retry.hide()
	busy_label.text = "保存しています…\nこの画面のままお待ちください"
	busy_panel.show()
	ui.move_child(busy_panel,ui.get_child_count()-1)
	Input.action_release("shoot")
	measurement_shooting = false
	burst_remaining = 0
	mouse_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# まず処理中を描画し、進行中の保存だけを非同期で完了させる。
	await get_tree().process_frame
	while save_worker.running():
		save_worker.poll()
		await get_tree().process_frame
	if not save_worker.configured():save_worker.configure(data)
	save_worker.start_transaction(candidate)
	while save_worker.running():
		save_worker.poll()
		await get_tree().process_frame
	var okay := save_worker.error.is_empty()
	if okay:
		data = candidate
		combat.set_data(data)
		save_worker.mark_flushed()
		save_worker.accept_refs(data)
		progress_dirty = true
		save_warning = false
		async_save_warning = false
	else:
		save_warning = true
	busy_panel.hide()
	durable_busy = false
	if close_requested:
		close_requested = false
		call_deferred("_notification",NOTIFICATION_WM_CLOSE_REQUEST)
	return okay

# 通常checkpointは受付だけ。確定が必要な境界は_flush_currentをawaitする。
func _save_current()->bool:
	if bool(data.get("migration_failed",false)):
		return false
	_sync_combat_save()
	_request_progress_save()
	return true

func _flush_current()->bool:
	_sync_combat_save()
	return await _commit(V2Save.transaction_copy(data))

func _begin_boot()->void:
	prep_panel.hide()
	army_panel.hide()
	result_panel.hide()
	records_view.hide()
	if bool(data.get("migration_failed",false)):
		_show_boot_failure()
		return
	if (data.has("legacy_backup") and not bool(data.get("v2_notice_seen",false))) or not str(data.get("recovery_notice","")).is_empty():
		_show_boot_notice()
		return
	boot_error = false
	boot_notice = false
	busy_panel.hide()
	boot_retry.hide()
	selected_weapon = 0
	selected_difficulty = TrainingCatalog.safe_difficulty(data.get("selected_difficulty",0))
	selected_measurement = false
	boot_launching = true
	_start_training()
	boot_launching = false

func _remember_selection()->void:
	if not boot_launching:
		super._remember_selection()

func _show_boot_failure()->void:
	boot_error = true
	boot_notice = false
	boot_retry.text = "保存を再読み込み"
	mode = Mode.PAUSED
	mode_before_pause = Mode.PREP
	prep_panel.hide()
	pause_panel.hide()
	info_panel.hide()
	busy_label.text = "保存データを確認してください\n" + str(data.get("migration_error","保存を読み込めません。")) + "\n原本を保全したまま再試行できます。"
	busy_label.add_theme_font_size_override("font_size",20)
	busy_label.offset_left = -450
	busy_label.offset_right = 450
	busy_panel.show()
	boot_retry.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _show_boot_notice()->void:
	boot_notice = true
	boot_error = false
	mode = Mode.PAUSED
	mode_before_pause = Mode.PREP
	prep_panel.hide()
	pause_panel.hide()
	info_panel.hide()
	busy_label.text = str(data.get("recovery_notice","旧データを別名で保全し、個人設定を引き継ぎました。\n旧版の育成・履歴は変更せず保存しています。"))
	busy_label.add_theme_font_size_override("font_size",20)
	busy_label.offset_left = -450
	busy_label.offset_right = 450
	boot_retry.text = "確認して練習へ"
	busy_panel.show()
	boot_retry.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _boot_retry_action()->void:
	if durable_busy:return
	if boot_error:
		_retry_migration()
	elif boot_notice:
		var candidate := V2Save.transaction_copy(data)
		candidate.v2_notice_seen = true
		candidate.erase("recovery_notice")
		if await _commit(candidate):
			_begin_boot()
		else:
			_show_boot_notice()
			busy_label.text = "確認状態の保存に失敗しました。原本と成果を保持しています。\n保存先を確認して再試行してください。"
			boot_retry.text = "保存を再試行"

func _retry_migration()->void:
	if is_test_mode:
		return
	data = V2Save.load_data()
	combat.configure(data)
	_apply_settings()
	if not bool(data.get("migration_failed",false)):
		_close_info()
		_begin_boot()
	else:
		_show_boot_failure()

func _request_progress_save()->void:
	if not is_test_mode:
		save_worker.request()

func _exit_tree()->void:
	save_worker.finish()
	for player_node in [audio_player,hit_audio_player]:
		if is_instance_valid(player_node):
			player_node.stop()
			player_node.stream = null
	sound_cache.clear()

func _complete_intro()->void:
	if not intro_session:
		return
	intro_session = false
	intro_hint.hide()
	data.intro_seen = true
	_request_progress_save()
	for target in targets:target.show()
	countdown = 3.0
	countdown_first_frame = true
	countdown_display.show_number(3)
	_arm_presentation()

func _arm_presentation()->void:
	presentation_ready = false
	presentation_serial += 1
	var serial := presentation_serial
	if DisplayServer.get_name() == "headless":return
	RenderingServer.frame_post_draw.connect(func():
		if serial == presentation_serial:presentation_ready = true
	,CONNECT_ONE_SHOT)

func _presentation_drawn_for_test()->void:
	if is_test_mode or OS.get_environment("SLT_TEST_DATA") == "1":presentation_ready = true

func _build_sound_cache()->void:
	var silent := AudioStreamPlayer.new()
	silent.volume_db = -80.0
	add_child(silent)
	for hit in [false,true]:
		for choice in 3:
			super._play_synth(silent,choice,hit,1.0,1.0)
			sound_cache[str(hit)+str(choice)] = silent.stream
			silent.stop()
	silent.queue_free()

func _play_synth(player_node:AudioStreamPlayer,choice:int,is_hit:bool,volume:float,pitch:float)->void:
	if choice == 3:
		player_node.stop()
		return
	var key := str(is_hit)+str(choice)
	if not sound_cache.has(key):
		super._play_synth(player_node,choice,is_hit,volume,pitch)
		return
	player_node.stream = sound_cache[key]
	player_node.volume_db = linear_to_db(maxf(0.00001,volume))
	player_node.pitch_scale = pitch
	player_node.play()

func _apply_settings()->void:
	super._apply_settings()
	if spawn_audio:
		spawn_audio.configure(data.settings)

func _refresh_army_runtime()->void:
	super._refresh_army_runtime()
	if not profile_name:
		return
	for weapon in slot_buttons.size():
		if not Progression.unlocked(data,weapon):
			slot_buttons[weapon].text = "??? 未解放"
	var known := Progression.unlocked(data,selected_soldier)
	profile_name.editable = known
	if not known:
		profile_name.text = "???"
		soldier_summary.text = "???\n練習の達成条件を満たすと名前が分かります。"
		soldier_flavor.text = "未解放の武器"

func _save_name()->void:
	if Progression.unlocked(data,selected_soldier):
		super._save_name()

func _open_soldier_details()->void:
	if not Progression.unlocked(data,selected_soldier):
		info_title.text = "???"
		info_text.text = "練習の達成条件を満たすと、この武器の名前と情報が分かります。"
		info_review.hide()
		info_panel.show()
		return
	super._open_soldier_details()

func _checkpoint_training()->bool:
	checkpoint_timer = 0.0
	if not _training_session_open() or training_elapsed <= 0.0:
		return not bool(data.get("migration_failed", false))
	# memory台帳は即時。発砲経路では履歴全体の複製/JSON保存を行わない。
	V2Ledger.checkpoint(data, _session_record())
	progress_dirty = true
	if mode == Mode.TRAINING:
		_request_progress_save()
		return true
	return _save_current()

func _refresh_prep()->void:
	if not free_button:
		return
	selected_difficulty = TrainingCatalog.safe_difficulty(selected_difficulty)
	if not Progression.unlocked(data, selected_weapon):
		selected_weapon = 0
	if selected_weapon >= 3:
		selected_measurement = false
	free_button.text = ("✓ " if not selected_measurement else "") + "自由練習 — 無制限"
	measure_button.text = ("✓ " if selected_measurement else "") + "兵士を作る — 60秒測定"
	measure_button.disabled = selected_weapon >= 3 or not Progression.measurement_unlocked(data)
	var rows := Progression.weapon_rows(data)
	for weapon in 5:
		var row:Dictionary = {}
		for item in rows:
			if int(item.id) == weapon:
				row = item
		weapon_buttons[weapon].hide()
		var unlocked := Progression.unlocked(data, weapon)
		weapon_buttons[weapon].disabled = not unlocked
		V2Interface.set_weapon_button(weapon_buttons[weapon], weapon, unlocked, weapon == selected_weapon, TrainingCatalog.NAMES[weapon]+"\n"+TrainingCatalog.TITLES[weapon] if unlocked else "???\n累計%d達成で解放" % Progression.THRESHOLDS[weapon])
		weapon_buttons[weapon].set_pressed_no_signal(weapon == selected_weapon)
	for difficulty in 3:
		difficulty_buttons[difficulty].set_pressed_no_signal(difficulty == selected_difficulty)
	difficulty_row.hide()
	difficulty_info.hide()
	training_kind_info.hide()
	prep_goal.hide()
	training_kind_info.text = "60秒の有効な測定から兵士を作ります。途中終了は進行達成に含めません。" if selected_measurement else "自由練習の撃破・有効追従1秒で達成を積み、次の武器へ。"
	if selected_weapon >= 3:
		training_kind_info.text += " この練習は兵士に採用できません。"
	difficulty_info.text = "測定は従来の固定条件・位置固定。視点操作は自由です。" if selected_measurement else TrainingCatalog.difficulty_text(selected_weapon, selected_difficulty)
	start_button.text = "練習開始"
	start_button.disabled = bool(data.get("migration_failed", false))
	condition_label.visible = start_button.disabled or save_warning
	condition_label.text = str(data.get("migration_error", "保存に失敗しました。保存先を確認して再試行してください。"))
	prep_goal.text = "累計達成 %d" % Progression.total(data)
	migration_label.visible = start_button.disabled
	migration_label.text = str(data.get("migration_error", ""))
	migration_retry.visible = start_button.disabled
	migration_ack.hide()
	_refresh_army_runtime()

func _select_weapon(weapon:int)->void:
	if mode != Mode.PREP or not Progression.unlocked(data, weapon):
		return
	selected_weapon = weapon
	if weapon >= 3:
		selected_measurement = false
	_refresh_prep()
	_remember_selection()

func _select_difficulty(value:int)->void:
	selected_difficulty = TrainingCatalog.safe_difficulty(value)
	_refresh_prep()
	_remember_selection()

func _select_measurement(value:bool)->void:
	if value and (selected_weapon >= 3 or not Progression.unlocked(data, selected_weapon) or not Progression.measurement_unlocked(data)):
		return
	super._select_measurement(value)

func _progress_model()->Dictionary:
	var rows := Progression.weapon_rows(data)
	for row in rows:
		row.description = TrainingCatalog.DESCRIPTIONS[int(row.id)] if bool(row.unlocked) else "あと%d達成" % int(row.remaining)
		row.title = TrainingCatalog.TITLES[int(row.id)] if bool(row.unlocked) else ""
	return {"total":Progression.total(data), "rows":rows, "achievements":Progression.achievements(data), "effects_enabled":bool(data.settings.get("effects_enabled", true))}

func _update_progress_ui()->void:
	if not progression_view or bool(data.get("migration_failed", false)):
		return
	if progress_dirty:
		progress_dirty = false
		progress_retry_clock = 0.0
		progression_view.refresh(_progress_model())
		var pending := Progression.pending_notifications(data)
		if not pending.is_empty():
			for achievement in pending:
				Progression.mark_seen(data, str(achievement.id))
				progression_view.enqueue_notification(achievement)
			_request_progress_save()
			progress_retry_clock = 0.0
	var training := mode in [Mode.TRAINING, Mode.COUNTDOWN]
	var context := [training, roster_open, roster_open]
	if context != progress_context:
		progress_context = context
		progression_view.set_context(context[0], context[1], context[2])
	progression_view.set_notifications_active(app_focused and mode != Mode.PAUSED and not info_panel.visible)

func _open_roster()->void:
	if mode in [Mode.TRAINING, Mode.COUNTDOWN]:
		return
	roster_open = true
	if mode == Mode.PAUSED:
		pause_panel.hide()
	_update_progress_ui()

func _open_achievements()->void:
	if mode in [Mode.TRAINING, Mode.COUNTDOWN]:
		return
	if mode == Mode.PAUSED:
		pause_panel.hide()
	progression_view.refresh(_progress_model())
	progression_view.show_achievements()

func _close_progress_overlay()->void:
	roster_open = false
	if mode == Mode.PAUSED:
		pause_panel.show()
		pause_menu.show()
		settings_page.hide()
	_update_progress_ui()

func _choose_roster_weapon(weapon:int)->void:
	if not Progression.unlocked(data, weapon):
		return
	if mode == Mode.PAUSED:
		pending_weapon = weapon
		progression_view.close_overlay()
		_close_progress_overlay()
		pause_warning.text = "%sを選択。『再開』で別の練習へ切り替えます。" % TrainingCatalog.NAMES[weapon]
		pause_warning.show()
	else:
		progression_view.close_overlay()
		roster_open = false
		_show_prep()
		_select_weapon(weapon)

func _input(event:InputEvent)->void:
	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:tab_held = event.pressed
	if durable_busy:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		if event.echo:return
		tab_held = event.pressed
		if event.pressed:
			_open_tab()
		elif interaction == Interaction.TAB:
			_close_tab()
		return
	if event.is_action_pressed("pause") and interaction != Interaction.NONE:
		if event is InputEventKey and event.echo:return
		get_viewport().set_input_as_handled()
		if interaction == Interaction.MAIN_TARGET_EDIT:
			_cancel_target_edit()
		elif interaction in [Interaction.TAB,Interaction.TARGET_EDIT]:
			target_editor.hide()
			tab_panel.present(false, false)
			interaction = Interaction.NONE
			mode = tab_resume_mode
			_open_pause()
		elif interaction in [Interaction.RESET_TOOLS,Interaction.RESET_CONFIRM]:
			_cancel_reset()
		return

func _unhandled_input(event:InputEvent)->void:
	if event.is_action_released("shoot"):phase_shoot_held = false
	if durable_busy or boot_error or boot_notice:return
	if interaction != Interaction.NONE:return
	if mode == Mode.COUNTDOWN and intro_session and iris_intro.waiting:
		if event.is_action_pressed("pause"):_open_pause()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
			iris_intro.skip()
		elif event.is_action_pressed("shoot") and not phase_shoot_held:
			_guidance_shot()
			phase_shoot_held = true
		Input.action_release("shoot")
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.COUNTDOWN and not event.is_action_pressed("pause"):
		if event.is_action_pressed("shoot"):phase_shoot_held = true
		elif event.is_action_released("shoot"):phase_shoot_held = false
		Input.action_release("shoot")
		measurement_shooting = false
		burst_remaining = 0
		mouse_blocked = true
		return
	if event.is_action_pressed("pause") and progression_view and (roster_open or progression_view.is_overlay_open()):
		progression_view.close_overlay()
		_close_progress_overlay()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and mode in [Mode.COUNTDOWN,Mode.TRAINING] and not info_panel.visible:
		_open_pause()
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.TRAINING and not training_measurement and training_weapon >= 3 and event.is_action_pressed("shoot"):
		if not mouse_blocked and not exit_holding:
			_fire_shot()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _resume_pause()->void:
	if boot_error or boot_notice or durable_busy:return
	if pending_weapon >= 0 and pending_weapon != training_weapon:
		if not Progression.unlocked(data, pending_weapon):
			pending_weapon = -1
			return
		condition_weapon.select(pending_weapon)
		condition_difficulty.select(training_difficulty)
		condition_measure.set_pressed_no_signal(training_measurement and pending_weapon < 3)
		condition_panel.show()
		await _confirm_condition_picker()
		if mode != Mode.PAUSED:
			pending_weapon = -1
		return
	pending_weapon = -1
	super._resume_pause()

func _finish_training(full_time:bool)->void:
	if iris_intro and iris_intro.is_active():
		iris_intro.clear()
	intro_session = false
	interaction = Interaction.NONE
	if tab_panel:tab_panel.present(false, false)
	if target_editor:target_editor.hide()
	countdown_display.clear()
	await super._finish_training(full_time)

func _open_pause()->void:
	if mode == Mode.PAUSED or durable_busy:
		return
	# 停止とmenuを最優先。checkpointとrequestにディスク待ちはない。
	mode_before_pause = mode
	mode = Mode.PAUSED
	_reset_exit_hold()
	burst_remaining = 0
	measurement_shooting = false
	next_auto_shot = -1.0
	Input.action_release("shoot")
	phase_shoot_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	audio_player.stop()
	hit_audio_player.stop()
	mouse_blocked = true
	crosshair.hide()
	pause_warning.hide()
	settings_standalone = false
	pause_panel.show()
	pause_menu.show()
	settings_page.hide()
	pause_end_button.visible = true
	iris_intro.hide()
	intro_hint.hide()
	countdown_display.clear()
	_update_battle_view()
	_sync_navigation()
	_checkpoint_training()
	_save_current()

func _refresh_condition_picker()->void:
	if not condition_measure:
		return
	for weapon in condition_weapon.item_count:
		condition_weapon.set_item_disabled(weapon, not Progression.unlocked(data, weapon))
		condition_weapon.set_item_text(weapon,TrainingCatalog.NAMES[weapon] if Progression.unlocked(data,weapon) else "??? — 累計%d達成" % Progression.THRESHOLDS[weapon])
	var extra := condition_weapon.selected >= 3
	if extra:
		condition_measure.set_pressed_no_signal(false)
	condition_measure.disabled = extra
	super._refresh_condition_picker()
	if not Progression.unlocked(data,condition_weapon.selected):
		condition_description.text = "??? — 累計%d達成で解放" % Progression.THRESHOLDS[condition_weapon.selected]
	if extra:
		condition_description.text = TrainingCatalog.difficulty_text(condition_weapon.selected, 0)
		condition_difficulty.disabled = true

func _confirm_condition_picker()->void:
	if not Progression.unlocked(data, condition_weapon.selected):
		condition_warning.text = "この練習はまだ解放されていません。"
		return
	if condition_weapon.selected >= 3:
		condition_measure.set_pressed_no_signal(false)
	if iris_intro and iris_intro.is_active():
		iris_intro.clear()
		intro_session = false
	await super._confirm_condition_picker()

func _guidance_shot()->bool:
	var test_headless := is_test_mode and OS.get_environment("SLT_TEST_DATA") == "1" and DisplayServer.get_name() == "headless"
	if mode != Mode.COUNTDOWN or not intro_session or not iris_intro.waiting or not app_focused or (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not test_headless):return false
	_play_shot_sound()
	var hit := _ray_hit()
	if hit.is_empty() or int(hit.get("index",-1)) != 0:return false
	_play_hit_sound(0,true)
	Progression.guidance_hit(data)
	progress_dirty = true
	_request_progress_save()
	_update_progress_ui()
	iris_intro.open_from(camera.unproject_position(targets[0].global_position), bool(data.settings.get("effects_enabled",true)))
	return true

func _session_card(width:float)->Array:
	var parts := _modal_overlay(width)
	ui.add_child(parts[0])
	var body := V2Interface.column(parts[1],12)
	parts[0].hide()
	return [parts[0],body]

func _build_session_controls()->void:
	tab_panel = WeaponTray.new()
	ui.add_child(tab_panel)
	tab_panel.build(self)
	tab_weapons = tab_panel.weapon_buttons
	tab_measure = tab_panel.measure_button
	tab_error = tab_panel.error_label
	tab_hint = V2Interface.label(hud, "Tab　武器・練習", 20)
	tab_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tab_hint.offset_left = -224
	tab_hint.offset_right = -24
	tab_hint.offset_top = -76
	tab_hint.offset_bottom = -26
	tab_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tab_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color("284651")
	hint_style.border_color = Color("f5d77b")
	hint_style.set_border_width_all(2)
	hint_style.set_corner_radius_all(6)
	tab_hint.add_theme_stylebox_override("normal", hint_style)
	tab_hint.add_theme_color_override("font_color", Color("fff0b0"))
	tab_hint.hide()
	var parts := _session_card(620)
	target_editor = parts[0]
	var body:VBoxContainer = parts[1]
	var editor_header := HBoxContainer.new()
	body.add_child(editor_header)
	var editor_title := V2Interface.label(editor_header, "ターゲット編集", 24)
	editor_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_editor := V2Interface.button(editor_header, "閉じる", _cancel_target_edit)
	close_editor.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_editor.custom_minimum_size.x = 88
	target_values = V2Interface.label(body, "", 16)
	target_preview = TargetCurvePreview.new()
	body.add_child(target_preview)
	target_slider = HSlider.new()
	target_slider.min_value = 0.0
	target_slider.max_value = 1.0
	target_slider.step = 0.01
	target_slider.custom_minimum_size = Vector2(480,48)
	body.add_child(target_slider)
	target_slider.value_changed.connect(_target_draft_changed)
	var editor_actions := HBoxContainer.new()
	body.add_child(editor_actions)
	V2Interface.button(editor_actions, "適用", _apply_target_edit, true)
	V2Interface.button(editor_actions, "キャンセル", _cancel_target_edit)
	target_error = V2Interface.label(body, "", 16)
	target_error.hide()
	parts = _session_card(590)
	reset_panel = parts[0]
	body = parts[1]
	V2Interface.label(body,"検証用操作",25)
	V2Interface.button(body,"全データを初期化",_request_reset_confirmation)
	reset_error = V2Interface.label(body,"",17)
	reset_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	V2Interface.button(body,"戻る",_cancel_reset)
	parts = _session_card(590)
	reset_confirm = parts[0]
	body = parts[1]
	var explanation := V2Interface.label(body,"クレジット、解放、記録、部隊と個人設定をすべて初期化します。\n初期化前のデータは自動読込されない場所へ保全します。",20)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cancel_reset := V2Interface.button(body,"キャンセル",_cancel_reset,true)
	cancel_reset.name = "CancelReset"
	V2Interface.button(body,"全データを初期化する",_reset_all_data)
	var tools := V2Interface.button(pause_menu, "検証用操作", _open_reset_tools)
	tools.tooltip_text = "検証用操作"
	pause_menu.move_child(tools,pause_menu.get_child_count()-1)

func _stop_training_input()->void:
	Input.action_release("shoot")
	measurement_shooting = false
	burst_remaining = 0
	next_auto_shot = -1.0
	next_burst_shot = -1.0
	phase_shoot_held = false
	mouse_blocked = true
	_reset_exit_hold()
	audio_player.stop()
	hit_audio_player.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _open_tab()->void:
	if interaction != Interaction.NONE or mode not in [Mode.TRAINING,Mode.COUNTDOWN] or durable_busy or intro_session:return
	tab_resume_mode = mode
	mode_before_pause = mode
	mode = Mode.PAUSED
	interaction = Interaction.TAB
	_stop_training_input()
	crosshair.hide()
	countdown_display.clear()
	_refresh_tab()
	tab_error.hide()
	tab_panel.present(true)
	if not bool(data.get("tab_guide_seen", false)):
		data.tab_guide_seen = true
		tab_hint.hide()
		_request_progress_save()
	_checkpoint_training()

func _refresh_tab()->void:
	tab_panel.refresh(data, training_weapon, training_measurement)

func _close_tab()->void:
	if interaction != Interaction.TAB or durable_busy or switch_in_progress:return
	tab_panel.present(false)
	interaction = Interaction.NONE
	mode = tab_resume_mode
	Input.action_release("shoot")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_blocked = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	measurement_frame_elapsed = training_elapsed
	measurement_frame_usec = Time.get_ticks_usec()
	crosshair.show()
	if mode == Mode.COUNTDOWN:
		countdown_display.show_number(clampi(ceili(countdown),1,3))
		_arm_presentation()

func _tab_choose_weapon(weapon:int)->void:
	if interaction != Interaction.TAB or not Progression.unlocked(data,weapon) or switch_in_progress:return
	if weapon == training_weapon:
		_refresh_tab()
		return
	await _switch_session(weapon,false,training_risk)

func _tab_start_measurement()->void:
	if interaction != Interaction.TAB or not Progression.measurement_unlocked(data) or selected_weapon >= 3:return
	await _switch_session(selected_weapon,true,training_risk)

func _switch_session(weapon:int,measured:bool,risk:float)->bool:
	if switch_in_progress or durable_busy:return false
	switch_in_progress = true
	var old_player := player.transform
	var old_camera := camera.rotation
	var previous_final := measured_final
	if training_measurement and measured_final.is_empty():
		var pending := V2Measurement.new()
		pending.record = measurement.record.duplicate(true)
		measured_final = pending.completed(training_elapsed,true,measurement_settings_changed)
	var record := _completed_record()
	var candidate := V2Save.transaction_copy(data)
	V2Ledger.finish(candidate,record,"練習変更",measured_final)
	candidate.selected_weapon = weapon
	candidate.selected_measurement = false
	candidate.target_risk = risk
	if not await _commit(candidate):
		measured_final = previous_final
		switch_in_progress = false
		target_editor.hide()
		interaction = Interaction.TAB
		_refresh_tab()
		tab_error.text = "保存に失敗しました。成果と現在の練習を保持しています。再試行できます。"
		tab_error.show()
		if not app_focused or not tab_held:
			tab_panel.present(false, false)
			interaction = Interaction.NONE
			mode = Mode.TRAINING
			_open_pause()
			pause_warning.text = tab_error.text
			pause_warning.show()
		else:tab_panel.present(true)
		return false
	target_editor.hide()
	reward_committed = true
	selected_weapon = weapon
	selected_measurement = measured
	_start_training()
	player.transform = old_player
	camera.rotation = old_camera
	mode = Mode.PAUSED
	mode_before_pause = Mode.TRAINING
	tab_resume_mode = Mode.TRAINING
	interaction = Interaction.TAB
	countdown_display.clear()
	_stop_training_input()
	crosshair.hide()
	_refresh_tab()
	tab_panel.present(true)
	switch_in_progress = false
	if not app_focused:
		tab_panel.present(false, false)
		interaction = Interaction.NONE
		mode = Mode.TRAINING
		_open_pause()
	elif not tab_held:_close_tab()
	return true

func _tab_stop()->void:
	if interaction != Interaction.TAB:return
	tab_panel.present(false, false)
	interaction = Interaction.NONE
	await _finish_training(false)

func _open_target_editor()->void:
	if interaction != Interaction.TAB or training_measurement or training_weapon == 4:
		return
	interaction = Interaction.TARGET_EDIT
	tab_panel.present(false, false)
	_show_target_editor(training_risk)

func _open_main_target_editor()->void:
	if mode != Mode.PREP or interaction != Interaction.NONE or durable_busy:
		return
	interaction = Interaction.MAIN_TARGET_EDIT
	_show_target_editor(float(data.get("target_risk", TargetScoring.DEFAULT_RISK)))

func _show_target_editor(risk:float)->void:
	target_error.hide()
	target_slider.set_value_no_signal(risk)
	_target_draft_changed(risk)
	ui.move_child(target_editor, ui.get_child_count() - 1)
	target_editor.show()

func _target_draft_changed(value:float)->void:
	draft_risk = TargetScoring.safe_risk(value)
	var weapon := _preview_weapon()
	var unit := "命中1発"
	if weapon == 1:
		unit = "有効追従1秒"
	elif weapon == 2:
		unit = "命中1発（3発撃破加点は別）"
	target_values.text = "%sの%sあたりの参考点。速度・連続加点と端数処理前。\n自由練習に適用。60秒測定とグレネードは固定配点。" % [TrainingCatalog.NAMES[weapon], unit]
	if target_preview:
		target_preview.configure(Callable(self, "_preview_target_points"), draft_risk)

func _preview_weapon()->int:
	if interaction == Interaction.MAIN_TARGET_EDIT:
		return 0 if selected_weapon == 4 else selected_weapon
	return training_weapon

func _preview_target_points(q:float,risk:float)->float:
	var weapon := _preview_weapon()
	var base := 100.0 if weapon == 1 else (15.0 if weapon == 2 else 45.0)
	var difficulty := 0 if interaction == Interaction.MAIN_TARGET_EDIT else training_difficulty
	var weight := float(Balance.POINT_WEIGHTS[0 if weapon == 3 else clampi(weapon,0,2)]) * float(Balance.DIFFICULTY[difficulty].reward)
	return base*weight*TargetScoring.reward_factor(q,risk)



func _apply_target_edit()->void:
	if durable_busy:
		return
	if interaction == Interaction.MAIN_TARGET_EDIT:
		var candidate := V2Save.transaction_copy(data)
		candidate.target_risk = draft_risk
		if not await _commit(candidate):
			target_error.text = "保存できませんでした。保存先を確認して再試行してください。"
			target_error.show()
			return
		_cancel_target_edit()
		return
	if interaction != Interaction.TARGET_EDIT:
		return
	if not is_equal_approx(draft_risk, training_risk):
		await _switch_session(training_weapon, false, draft_risk)
		return
	_cancel_target_edit()

func _cancel_target_edit()->void:
	if durable_busy:
		return
	if interaction == Interaction.MAIN_TARGET_EDIT:
		target_editor.hide()
		interaction = Interaction.NONE
		return
	if interaction != Interaction.TARGET_EDIT:
		return
	target_editor.hide()
	interaction = Interaction.TAB
	if tab_held:
		tab_panel.present(true)
	else:
		_close_tab()

func _open_reset_tools()->void:
	if mode != Mode.PAUSED or durable_busy or interaction != Interaction.NONE:return
	interaction = Interaction.RESET_TOOLS
	pause_panel.hide()
	reset_error.text = ""
	reset_panel.show()

func _request_reset_confirmation()->void:
	if interaction != Interaction.RESET_TOOLS:return
	interaction = Interaction.RESET_CONFIRM
	reset_panel.hide()
	reset_confirm.show()
	reset_confirm.find_child("CancelReset",true,false).grab_focus()

func _cancel_reset()->void:
	if interaction not in [Interaction.RESET_TOOLS,Interaction.RESET_CONFIRM]:return
	reset_panel.hide()
	reset_confirm.hide()
	interaction = Interaction.NONE
	if reset_partial:
		reset_partial = false
		combat.configure(data)
		_apply_settings()
		_sync_settings_controls(data.settings)
		_clear_targets()
		_clear_extra_visuals()
		intro_session = false
		iris_intro.clear()
		progress_dirty = true
		_begin_boot()
		return
	pause_panel.show()
	pause_menu.show()
	settings_page.hide()

func _reset_all_data()->void:
	if interaction != Interaction.RESET_CONFIRM or durable_busy:return
	interaction = Interaction.RESETTING
	durable_busy = true
	mode = Mode.PAUSED
	_stop_training_input()
	reset_confirm.hide()
	iris_intro.hide()
	countdown_display.clear()
	busy_label.text = "初期化前データを保全しています…"
	busy_panel.show()
	ui.move_child(busy_panel,ui.get_child_count()-1)
	await get_tree().process_frame
	# runningの完了後にqueue/cacheを破棄。旧世代writerが新世代へ戻る経路を消す。
	while save_worker.running():
		save_worker.poll()
		await get_tree().process_frame
	var outcome:Dictionary
	if is_test_mode:
		outcome = {"okay":true,"data":V2Save.defaults()}
	else:
		reset_thread = Thread.new()
		var started := reset_thread.start(V2Save.reset_all)
		if started != OK:
			reset_thread = null
			outcome = {"okay":false,"error":"初期化処理を開始できません。元データは保持しています。"}
		else:
			while reset_thread.is_alive():await get_tree().process_frame
			outcome = reset_thread.wait_to_finish()
			reset_thread = null
	busy_panel.hide()
	durable_busy = false
	if not bool(outcome.get("okay",false)):
		interaction = Interaction.RESET_TOOLS
		reset_error.text = str(outcome.get("error","初期化に失敗しました。"))+"\n"+str(outcome.get("backup",""))
		reset_panel.show()
		if outcome.has("new_data"):
			data = outcome.new_data
			save_worker = V2SaveWorker.new()
			save_worker.configure(data)
			reward_committed = true
			reset_partial = true
			training_in_army = false
		return
	data = outcome.data
	save_worker = V2SaveWorker.new()
	save_worker.configure(data)
	reward_committed = true
	training_in_army = false
	intro_session = false
	iris_intro.clear()
	_clear_targets()
	_clear_extra_visuals()
	combat.configure(data)
	interaction = Interaction.NONE
	tab_held = false
	pending_weapon = -1
	selected_weapon = 0
	selected_difficulty = 0
	selected_measurement = false
	session_id = ""
	measured_final.clear()
	candidate_record.clear()
	last_result_record.clear()
	progression_view.queue_free()
	progression_view = ProgressionView.new()
	ui.add_child(progression_view)
	progression_view.theme = TrainerTheme.create()
	progression_view.weapon_selected.connect(_choose_roster_weapon)
	progression_view.closed.connect(_close_progress_overlay)
	progress_context.clear()
	progress_dirty = true
	_apply_settings()
	_sync_settings_controls(data.settings)
	_begin_boot()
	if close_requested:
		close_requested = false
		call_deferred("_notification",NOTIFICATION_WM_CLOSE_REQUEST)

func _on_focus_lost()->void:
	if interaction in [Interaction.TAB,Interaction.TARGET_EDIT]:
		tab_held = false
		tab_panel.present(false, false)
		target_editor.hide()
		interaction = Interaction.NONE
		mode = tab_resume_mode
		_open_pause()
	super._on_focus_lost()

func _add_point_feedback(before:Dictionary,_display:bool)->void:
	var after := _training_result()
	var added := maxi(0,int(after.score)-int(before.get("score",0)))
	if added <= 0:return
	if hit_flash <= 0.0:credit_feedback_amount = 0
	credit_feedback_amount += added
	hit_label.text = "+%d" % credit_feedback_amount
	hit_label.add_theme_font_size_override("font_size",28)
	hit_label.add_theme_color_override("font_color",Color("ffe3a0"))
	hit_flash = 1.8
	point_display_timer = 1.4

func _start_training()->void:
	if selected_measurement and not Progression.measurement_unlocked(data):selected_measurement = false
	# 三段階の旧難易度は履歴だけに残す。新しい自由練習は共通形状＋編集曲線。
	if not selected_measurement:selected_difficulty = 0
	if not Progression.unlocked(data, selected_weapon):
		return
	if selected_weapon >= 3:
		selected_measurement = false
	intro_session = boot_launching
	training_risk = TargetScoring.safe_risk(data.get("target_risk",TargetScoring.DEFAULT_RISK))
	credit_feedback_amount = 0
	phase_shoot_held = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	intro_first_spawn = intro_session
	iris_intro.clear()
	intro_hint.visible = false
	intro_hint.text = ""
	selected_difficulty = TrainingCatalog.safe_difficulty(selected_difficulty)
	pending_weapon = -1
	roster_open = false
	_clear_extra_visuals()
	grid_bag.clear()
	grid_previous = -1
	grid_switches.clear()
	grenade_events.clear()
	grenade_serial = 0
	grenade_generation = 0
	group_respawn = -1.0
	extra_rng.seed = int(Time.get_ticks_usec())
	super._start_training()
	if not is_test_mode and not save_worker.configured():
		save_worker.configure(data)
	countdown_label.hide()
	countdown_first_frame = true
	_arm_presentation()
	if intro_session:
		# 既存武器は保持し、誘導用の標的だけを静止させる。
		if not targets.is_empty():
			targets[0].position = Vector3(0,1.7,-5)
			for index in range(1,targets.size()):targets[index].hide()
		iris_intro.start_wait(camera.unproject_position(targets[0].global_position), 74.0)
		iris_intro.set_prompt_clicking(bool(data.settings.get("effects_enabled", true)))
		countdown_display.clear()
	else:
		countdown_display.show_number(3)
	if not training_measurement:
		shooting_metrics.setting_key = ShootingMetrics.setting_key(training_weapon, training_difficulty, data.settings)
		shooting_metrics.setting_key += "|practice-021"
	if training_weapon == 4:
		trajectory = MeshInstance3D.new()
		trajectory.name = "TrajectoryGuide"
		world.add_child(trajectory)
		_update_trajectory()
	_update_progress_ui()

func _spawn_targets()->void:
	if training_weapon >= 3:
		training_difficulty = 0
	super._spawn_targets()
	if training_weapon == 1 and spawn_audio and not targets.is_empty():
		spawn_audio.spawn_at(camera.unproject_position(targets[0].global_position))
	if training_weapon == 3:
		for cell in 9:
			var marker := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.10
			torus.outer_radius = 0.13
			marker.mesh = torus
			marker.rotation_degrees.x = 90
			marker.position = TrainingExtras.grid_position(cell)
			marker.material_override = _material(Color("34505a"))
			target_root.add_child(marker)
	elif training_weapon == 4:
		for index in range(1, 5):
			var target := targets[0].duplicate() as StaticBody3D
			target.set_meta("target_index", index)
			target_root.add_child(target)
			targets.append(target)
			target_progress.append(0)
			target_spawn_times.append(0.0)
			target_precisions.append(0.0)
		for index in targets.size():
			_relocate_target(index)

func _relocate_target(index:int)->void:
	if intro_first_spawn and index == 0:
		intro_first_spawn = false
		targets[index].position = Vector3(0.0,1.7,-7.0)
		target_progress[index] = 0
		target_precisions[index] = 0.0
		target_spawn_times[index] = training_elapsed
		_play_spawn(index)
		return
	_relocate_target_actual(index)
	_play_spawn(index)

func _play_spawn(index:int)->void:
	if intro_session and index != 0:return
	if spawn_audio and index < targets.size() and training_weapon != 1:
		spawn_audio.spawn_at(camera.unproject_position(targets[index].global_position))

func _relocate_target_actual(index:int)->void:
	if training_weapon == 3:
		if not targets.is_empty():
			grid_previous = TrainingExtras.next_cell(grid_bag, grid_previous, extra_rng)
			targets[index].position = TrainingExtras.grid_position(grid_previous)
			target_spawn_times[index] = training_elapsed
		return
	if training_weapon == 4:
		targets[index].position = TrainingExtras.GRENADE_POSITIONS[index]
		targets[index].set_meta("alive", true)
		targets[index].set_meta("hp", TrainingExtras.TARGET_HP)
		targets[index].show()
		target_progress[index] = 0
		return
	if training_measurement:
		super._relocate_target(index)
		return
	# 最初から右一覧用の空間を空ける。制限後の位置同士でも重ならない。
	var range_x:float = Balance.DIFFICULTY[training_difficulty].range
	var previous := targets[index].position
	var candidate := previous
	for attempt in 64:
		candidate = Vector3(randf_range(-range_x, minf(range_x, 1.5)), randf_range(1.1,4.1), randf_range(-10.5,-5.0))
		var valid := candidate.distance_to(previous) > 2.5
		for other in targets.size():
			if other != index and candidate.distance_to(targets[other].position) < 1.6:
				valid = false
		if valid:
			break
	targets[index].position = candidate
	target_progress[index] = 0
	target_precisions[index] = 0.0
	target_spawn_times[index] = training_elapsed

func _auto_position(phase:float)->Vector3:
	if training_measurement:
		return super._auto_position(phase)
	var range_x:float = Balance.DIFFICULTY[training_difficulty].range
	return Vector3(-1.8 + sin(phase) * minf(range_x * 0.62, 4.6), 2.45 + sin(phase * 0.63) * 1.15, -7.5 + cos(phase * 0.37) * 1.5)

func _update_targets(delta:float)->void:
	if intro_session:return
	if training_weapon < 3:
		super._update_targets(delta)
		return
	if training_weapon == 4 and group_respawn >= 0.0:
		group_respawn -= delta
		if group_respawn <= 0.0:
			group_respawn = -1.0
			grenade_generation += 1
			for index in targets.size():
				_relocate_target(index)
	for target in targets:
		target.get_node("CenterMark").position = (camera.global_position - target.global_position).normalized() * float(Balance.DIFFICULTY[training_difficulty].radius) * 1.015

func _ray_hit()->Dictionary:
	if training_measurement:
		return super._ray_hit()
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var endpoint := origin - camera.global_transform.basis.z * 100.0
	var distance := INF
	var result:Dictionary = {}
	var radius:float = Balance.DIFFICULTY[training_difficulty].radius
	for index in targets.size():
		if not targets[index].is_visible_in_tree() or not bool(targets[index].get_meta("alive", true)):
			continue
		var fraction := TrainingExtras.segment_sphere(origin, endpoint, targets[index].global_position, radius)
		if fraction < distance:
			distance = fraction
			# 旧自由練習と同じ100mレイの差分をqへ渡し、浮動小数の端数も維持する。
			var q := Balance.center_quality(origin, endpoint - origin, targets[index].global_position, radius)
			result = {"index":index, "q":q, "precision":TargetScoring.reward_factor(q,training_risk)-1.0 if training_weapon != 4 else pow(q,1.5)}
	return result

func _fire_shot()->void:
	if mode != Mode.TRAINING or durable_busy or intro_session:return
	if training_weapon < 3:
		super._fire_shot()
		_maybe_progress_checkpoint()
		return
	if mode != Mode.TRAINING or mouse_blocked or exit_holding or fire_cooldown > 0.0:
		return
	if training_weapon == 4:
		if projectiles.size() >= TrainingExtras.MAX_PROJECTILES:
			return
		stats.shots = int(stats.shots) + 1
		activity_window = 0.3
		var projectile := TrainingExtras.launch(camera.global_position, -camera.global_transform.basis.z, grenade_serial)
		projectiles.append(projectile)
		var node := _sphere(0.10, Color("ffc265"))
		node.position = projectile.position
		world.add_child(node)
		projectile_nodes[grenade_serial] = node
		grenade_serial += 1
		fire_cooldown = TrainingExtras.GRENADE_INTERVAL
		_play_shot_sound()
		return
	var before := _training_result()
	var hit := _ray_hit()
	stats.shots = int(stats.shots) + 1
	activity_window = 0.2
	fire_cooldown = TrainingExtras.GRID_INTERVAL
	_play_shot_sound()
	ShootingMetrics.bullet(shooting_metrics, float(hit.get("q", 0.0)))
	if hit.is_empty():
		streak = 0
		return
	stats.hits = int(stats.hits) + 1
	stats.kills = int(stats.kills) + 1
	stats.base_points = float(stats.base_points) + 45.0
	stats.center_bonus = float(stats.center_bonus) + 45.0 * float(hit.precision)
	grid_switches.append(maxf(0.0, training_elapsed - target_spawn_times[0]))
	if grid_switches.size() > 2000:
		grid_switches.pop_front()
	streak += 1
	_play_hit_sound(streak, float(hit.q) >= 0.8)
	_relocate_target(0)
	_add_point_feedback(before, true)
	_maybe_progress_checkpoint()

func _process_weapon(delta:float)->void:
	if training_weapon < 3:
		super._process_weapon(delta)
		return
	if training_weapon != 4 or exit_holding:
		return
	var positions := _grenade_positions()
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		var impact := TrainingExtras.advance(projectile, delta, positions, float(Balance.DIFFICULTY[training_difficulty].radius))
		projectile_nodes[int(projectile.id)].position = projectile.position
		if not impact.is_empty():
			if not bool(impact.get("expired", false)):
				_explode(projectile, impact)
			else:
				grenade_events.append({"shot_id":projectile.id,"impact_time":training_elapsed,"position":V2Measurement.vector_array(impact.position),"direct_targets":[],"blast_targets":[],"killed":0,"expired":true})
			projectile_nodes[int(projectile.id)].queue_free()
			projectile_nodes.erase(int(projectile.id))
			projectiles.remove_at(index)
			positions = _grenade_positions()
	while grenade_events.size() > 2000:
		grenade_events.pop_front()
	trajectory_timer -= delta
	if trajectory_timer <= 0.0:
		_update_trajectory()
		trajectory_timer = 1.0 / 15.0

func _grenade_positions()->Array[Vector3]:
	var positions:Array[Vector3] = []
	for target in targets:
		positions.append(target.global_position if bool(target.get_meta("alive", true)) else Vector3(10000,10000,10000))
	return positions

func _explode(projectile:Dictionary, impact:Dictionary)->void:
	var before := _training_result()
	var victims := TrainingExtras.victims(impact.position, _grenade_positions(), int(impact.direct_index))
	var direct_ids:Array[String] = []
	var blast_ids:Array[String] = []
	for index in victims:
		if not bool(targets[index].get_meta("alive", true)):
			continue
		var remaining_hp := maxf(0.0, float(targets[index].get_meta("hp", TrainingExtras.TARGET_HP)) - TrainingExtras.BLAST_DAMAGE)
		targets[index].set_meta("hp", remaining_hp)
		if remaining_hp > 0.0:
			continue
		targets[index].set_meta("alive", false)
		targets[index].hide()
		stats.kills = int(stats.kills) + 1
		var id := "%d:%d" % [grenade_generation, index]
		if index == int(impact.direct_index):
			direct_ids.append(id)
		else:
			blast_ids.append(id)
	var killed := direct_ids.size() + blast_ids.size()
	if killed > 0:
		stats.hits = int(stats.hits) + 1
		stats.base_points = float(stats.base_points) + minf(9.0, 6.0 + killed)
		streak += 1
		_play_hit_sound(streak, not direct_ids.is_empty())
	else:
		streak = 0
	var event := {"shot_id":projectile.id, "impact_time":training_elapsed, "position":V2Measurement.vector_array(impact.position), "direct_targets":direct_ids, "blast_targets":blast_ids, "killed":killed}
	grenade_events.append(event)
	if grenade_events.size() > 2000:
		grenade_events.pop_front()
	var effect := _sphere(TrainingExtras.BLAST_RADIUS, Color("edb75a", 0.18))
	effect.position = impact.position
	world.add_child(effect)
	blast_effects.append({"node":effect, "remaining":0.28})
	while blast_effects.size() > TrainingExtras.MAX_EFFECTS:
		blast_effects.pop_front().node.queue_free()
	if _grenade_positions().all(func(position): return position.x > 999):
		group_respawn = 0.35
	hit_label.text = "着弾 (%.1f, %.1f, %.1f) ／ 直撃 %d・爆風 %d体 ／ 今回 %d体" % [impact.position.x, impact.position.y, impact.position.z, direct_ids.size(), blast_ids.size(), killed]
	hit_flash = 1.5
	_add_point_feedback(before, false)
	_maybe_progress_checkpoint()

func _sphere(radius:float, color:Color)->MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	var material := _material(color)
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	return node

func _update_trajectory()->void:
	if not is_instance_valid(trajectory):
		return
	var points := TrainingExtras.predict(camera.global_position, -camera.global_transform.basis.z, _grenade_positions(), float(Balance.DIFFICULTY[training_difficulty].radius))
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(Color("82c4a6")))
	for index in range(1, points.size()):
		mesh.surface_add_vertex(points[index - 1])
		mesh.surface_add_vertex(points[index])
	mesh.surface_end()
	trajectory.mesh = mesh

func _clear_extra_visuals()->void:
	for node in projectile_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	projectile_nodes.clear()
	projectiles.clear()
	for effect in blast_effects:
		if is_instance_valid(effect.node):
			effect.node.queue_free()
	blast_effects.clear()
	if is_instance_valid(trajectory):
		trajectory.queue_free()
	trajectory = null

func _physics_process(delta:float)->void:
	if durable_busy:
		player.velocity = Vector3.ZERO
		return
	super._physics_process(delta)

func _process(delta:float)->void:
	progress_retry_clock += minf(delta, 0.25)
	save_worker.poll()
	if not save_worker.error.is_empty():
		save_warning = true
		async_save_warning = true
	elif async_save_warning and not save_worker.pending():
		save_warning = false
		async_save_warning = false
	if durable_busy:
		return
	if mode == Mode.PAUSED and not boot_error and not boot_notice and pending_weapon < 0:
		if not save_worker.error.is_empty():
			pause_warning.text = "成果の保存に失敗しました。画面に保持して再試行中です。" if save_worker.pending() else "成果の保存に失敗しました。操作を再試行できます。"
			pause_warning.show()
		elif save_worker.pending():
			pause_warning.text = "成果の保存中です。メニューは操作できます。"
			pause_warning.show()
		elif pause_warning.text.begins_with("成果の保存"):
			pause_warning.hide()
	if mode == Mode.COUNTDOWN:
		_process_presentation(delta)
	else:
		super._process(delta)
	_maybe_progress_checkpoint()
	_update_progress_ui()
	if iris_intro:
		iris_intro.visible = iris_intro.is_active() and mode == Mode.COUNTDOWN
		intro_hint.visible = iris_intro.visible and iris_intro.waiting
		if intro_hint.visible and not targets.is_empty():
			iris_intro.set_guidance_target(camera.unproject_position(targets[0].global_position))
	if not is_test_mode:
		save_worker.dispatch(data)
	if mode not in [Mode.COUNTDOWN, Mode.TRAINING, Mode.PAUSED] and not training_in_army:
		_clear_extra_visuals()
	if is_instance_valid(trajectory):
		trajectory.visible = mode == Mode.TRAINING
	if mode == Mode.TRAINING:
		for index in range(blast_effects.size() - 1, -1, -1):
			blast_effects[index].remaining -= minf(delta, 0.25)
			if float(blast_effects[index].remaining) <= 0.0:
				blast_effects[index].node.queue_free()
				blast_effects.remove_at(index)

func _process_presentation(delta:float)->void:
	Input.action_release("shoot")
	measurement_shooting = false
	burst_remaining = 0
	mouse_blocked = true
	if not app_focused or not presentation_ready or delta <= 0.0 or delta > 0.25:
		return
	if intro_session:
		if iris_intro.waiting:
			return
		iris_intro.advance(delta,true)
		return
	if countdown_first_frame:
		countdown_first_frame = false
		countdown_display.show_number(3)
		return
	countdown = maxf(0.0,countdown-delta)
	if countdown > 0.000001:
		countdown_display.show_number(clampi(ceili(countdown-0.000001),1,3))
	else:
		mode = Mode.TRAINING
		countdown_label.text = ""
		countdown_display.clear()
		intention_label.hide()
		Input.action_release("shoot")
		mouse_blocked = phase_shoot_held or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		measurement_frame_elapsed = 0.0
		measurement_frame_usec = Time.get_ticks_usec()
	_update_battle_view()

func _notification(what:int)->void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:return
	if durable_busy:
		close_requested = true
		return
	if bool(data.get("migration_failed",false)):
		get_tree().quit()
		return
	if _training_session_open():
		await _finish_training(false)
		if not reward_committed:return
		# finishの確定候補が最新成果を含む。終了直前に同じ全履歴を二重保存しない。
		get_tree().quit()
		return
	if not await _flush_current():
		info_title.text = "終了保存に失敗しました"
		info_text.text = "成果を保持して終了を中止しました。ウィンドウを閉じる操作で再試行できます。"
		info_review.hide()
		info_panel.show()
		return
	get_tree().quit()

func _apply_update()->void:
	if not updater or not updater.ready_to_apply or _training_session_open() or durable_busy:
		return
	if not await _flush_current():
		_update_status("保存に失敗したため更新を中止しました")
		return
	updater.apply_update()

func _maybe_progress_checkpoint()->void:
	if training_measurement or mode != Mode.TRAINING or training_elapsed <= 0.0:
		return
	var previous:Dictionary = data.get("active_training", {})
	if str(previous.get("id", "")) != session_id:
		previous = {}
	var changed := int(stats.get("kills", 0)) > int(previous.get("progress_kills", 0))
	if training_weapon == 1:
		var stored:float = data.progression.tracking_seconds
		changed = floori(stored + maxf(0.0, float(stats.track_time) - float(previous.get("progress_tracking_seconds", 0.0))) + 0.000001) > floori(stored + 0.000001)
	if changed:
		_checkpoint_training()
		progress_retry_clock = 0.0

func _session_record()->Dictionary:
	var record := super._session_record()
	record.progress_kills = int(stats.get("kills", 0))
	record.progress_tracking_seconds = float(stats.get("track_time", 0.0))
	record.progress_measurement = training_measurement
	record.scoring_version = Balance.SCORING_VERSION if training_measurement or training_weapon == 4 else TargetScoring.VERSION
	record.target_risk = training_risk if not training_measurement and training_weapon != 4 else null
	if training_weapon >= 3:
		record.extra = {"rule_version":1, "grid_switches":grid_switches.duplicate(), "grenade_events":grenade_events.duplicate(true), "in_flight":projectiles.size(), "blast_radius":TrainingExtras.BLAST_RADIUS, "blast_damage":TrainingExtras.BLAST_DAMAGE}
	return record

func _training_result()->Dictionary:
	if not training_measurement and training_weapon != 4:
		return TargetScoring.score(0 if training_weapon == 3 else training_weapon,training_difficulty,stats,session_fraction)
	if training_weapon < 3:
		return super._training_result()
	return Balance.score_and_reward(0 if training_weapon == 3 else 2, training_difficulty, stats if training_weapon == 3 else _grenade_score_stats(), 0, 0, training_elapsed, session_fraction)

func _grenade_score_stats()->Dictionary:
	var values := stats.duplicate(true)
	# 1発あたり最大9クレジット。巻き込み人数を命中弾数にしない。
	values.base_points = float(stats.get("base_points", 0.0)) / float(Balance.POINT_WEIGHTS[2]) / float(Balance.DIFFICULTY[training_difficulty].reward)
	return values

func _update_hud()->void:
	var result := _training_result()
	timer_label.text = "%02d" % ceili(maxf(0.0,60.0-training_elapsed)) if training_measurement else Balance.clock_text(training_elapsed)
	stat_label.text = "+%d" % int(result.score)
	stat_label.tooltip_text = "今回の獲得クレジット"
	credit_hud.text = "◎ %.1f%%    ◈ %s    ◉ %d" % [float(result.accuracy)*100.0,BigUInt.format(str(data.credits)),Progression.total(data)]
	credit_hud.tooltip_text = "命中・追従率 ／ 所持クレジット ／ 累計達成。"+("保存に失敗し再試行しています。" if save_warning else "保存中。" if save_worker.pending() else "")
	if save_warning:credit_hud.text += " !"
	exit_hint.hide()
	if tab_hint:
		tab_hint.visible = mode == Mode.TRAINING and not training_measurement \
			and int(stats.get("hits", 0)) >= 3 and not bool(data.get("tab_guide_seen", false))

func _show_prep()->void:
	selected_measurement = false
	if not Progression.unlocked(data, selected_weapon):
		selected_weapon = 0
	super._show_prep()

func _present_result()->void:
	var weapon := int(last_result_record.get("weapon", 0))
	if weapon < 3:
		extra_result.hide()
		replay_diorama.show()
		super._present_result()
		return
	_stop_replay()
	result_title.text = TrainingCatalog.TITLES[weapon] + "の結果"
	result_detail.text = TrainingCatalog.NAMES[weapon] + " ／ 自由練習専用"
	result_points.text = "今回獲得 %d クレジット" % int(last_result_record.get("credits", 0))
	result_wallet.text = "所持 %s ／ 累計 %s" % [BigUInt.format(str(data.credits)), BigUInt.format(str(data.lifetime_credits))]
	var raw:Dictionary = last_result_record.get("metrics", {})
	result_values.show()
	result_values.text = "発射 %d発 ／ 命中弾 %d発\n命中率 %.1f%% ／ 撃破 %d体" % [int(raw.get("shots", 0)), int(raw.get("hits", 0)), float(last_result_record.get("accuracy", 0.0)) * 100.0, int(raw.get("kills", 0))]
	result_comparison.text = "この練習から兵士プロフィールは作りません。"
	result_flavor.text = "成果を保存しました。武器の自動変更や解放報酬の追加はありません。"
	result_review.hide()
	adopt_button.disabled = true
	adopt_button.text = "自由練習専用（兵士には採用できません）"
	result_message.text = ""
	replay_diorama.hide()
	extra_result.show()
	replay_label.text = "今回の射撃を確認"
	var extra:Dictionary = last_result_record.get("extra", {})
	if weapon == 3:
		var switches:Array = extra.get("grid_switches", [])
		var total := 0.0
		for value in switches:
			total += float(value)
		extra_result.text = "固定された9地点・同時に標的一つ\n命中弾の中心精度 %.1f%%\n撃破までの平均切替時間 %s\n全地点を一巡するシャッフル方式・連続同地点なし" % [float(raw.get("q_sum", 0.0)) / maxf(1, float(raw.get("hits", 0))) * 100.0, "%.2f秒" % (total / switches.size()) if not switches.is_empty() else "未計測"]
	else:
		var direct := 0
		var blast := 0
		for event in extra.get("grenade_events", []):
			direct += event.direct_targets.size()
			blast += event.blast_targets.size()
		extra_result.text = "直撃で撃破 %d体 ／ 爆風で撃破 %d体\n爆風半径2.2m・範囲内100ダメージ\n一発で複数撃破しても発射・命中弾は一発\n1発最大9クレジット・飛行中終了分は命中なし" % [direct, blast]
	replay_button.disabled = true
	skip_replay_button.disabled = true
	trial_button.disabled = true
	_update_battle_view()

func _open_v2_result_details()->void:
	if int(last_result_record.get("weapon", 0)) < 3:
		super._open_v2_result_details()
		return
	info_title.text = "自由練習の条件"
	info_text.text = TrainingCatalog.difficulty_text(int(last_result_record.weapon), 0) + "\n\n" + extra_result.text
	info_review.hide()
	info_panel.show()

func _open_help()->void:
	if mode not in [Mode.PREP, Mode.ARMY, Mode.RECORDS]:
		return
	info_title.text = "撃破・追従達成で次の練習へ"
	info_review.hide()
	info_text.text = "最初の標的を撃つと訓練場が開き、3・2・1の後に自由練習が始まります。最初の有効命中は生涯一度だけ進行へ反映され、射撃成績には入りません。\n\nTabを押している間だけ練習を停止し、武器・標的編集・兵士作成・終了を操作できます。Tabを離すと一覧が閉じます。ターゲット編集では適用またはキャンセルで戻ります。武器や配点の変更前後は別記録となり、追加の待ち時間はありません。Escは一時停止と設定です。\n\nターゲット編集はメイン画面からも開けます。左が広く低リスク、右が中心へ集中。右ほど中心の報酬が増え、端が減ります。数字は命中1発、アサルトのみ有効追従1秒が単位です。バーストは3発撃破の加点が別途あります。測定とグレネードは編集対象外です。\n\n撃破または有効追従累計1秒が1達成。右側の一覧には最初から五つの枠があり、累計10／100／500／1,500で武器を解放します。100達成で60秒の兵士作成が解放されます。既存の測定利用権は維持します。途中終了した測定は採用できません。\n\n兵士は三つの固定枠。検証用の全データ初期化はEsc内の「検証用操作」から二段階で実行でき、個人設定も初期値へ戻ります。"
	info_panel.show()
	_sync_navigation()
