extends "res://main.gd"

# v1 input/settings/free-practice remain in the base. v2 owns the new lifecycle.
var selected_measurement := false
var training_measurement := false
var measurement := V2Measurement.new()
var measured_final:Dictionary = {}
var measurement_rng := RandomNumberGenerator.new()
var measurement_seed := 1
var target_ids:Array[String] = []
var spawn_serial := 0
var quadrant_counts:Array[int] = [0, 0, 0, 0]
var next_auto_shot := -1.0
var next_burst_shot := -1.0
var burst_serial := 0
var burst_bullet := 0
var measurement_settings_changed := false
var measurement_shooting := false
var measurement_frame_elapsed := 0.0
var measurement_frame_usec := 0
var last_target_sample := -1.0
var combat := V2Combat.new()
var replay := V2Replay.new()
var trial := V2Combat.new()
var trial_running := false
var trial_elapsed := 0.0
var trial_phase := 0
var trial_results:Array[Dictionary] = []
var trial_data:Dictionary = {}
var candidate_record:Dictionary = {}
var selected_soldier := 0
var battle_summary_before := 0
var free_button:Button
var measure_button:Button
var difficulty_row:HBoxContainer
var training_kind_info:Label
var prep_goal:Label
var migration_retry:Button
var migration_ack:Button
var diorama:Control
var replay_diorama:Control
var slot_buttons:Array[Button] = []
var profile_name:LineEdit
var soldier_summary:Label
var soldier_flavor:Label
var armor_summary:Label
var protection_button:Button
var deployed_check:CheckBox
var revert_button:Button
var army_message:Label
var battle_summary:Label
var retry_battle_button:Button
var continue_button:Button
var replay_label:Label
var replay_button:Button
var skip_replay_button:Button
var trial_button:Button
var result_values:Label
var result_comparison:Label
var result_flavor:Label
var adopt_button:Button
var result_message:Label
var effects_check:CheckBox
var condition_measure:CheckBox

func _ready()->void:
	feedback_url = "https://github.com/cloford/supply-line-trainer/discussions/8"
	is_test_mode = is_test_mode or "--ui-test" in OS.get_cmdline_user_args()
	data = V2Save.defaults() if is_test_mode else V2Save.load_data()
	selected_weapon = TrainingCatalog.safe_index(data.get("selected_weapon", 0))
	selected_difficulty = TrainingCatalog.safe_index(data.get("selected_difficulty", 0))
	selected_measurement = bool(data.get("selected_measurement", false))
	_build_world()
	_build_ui()
	combat.configure(data)
	_apply_settings()
	_show_prep()
	get_viewport().focus_exited.connect(_on_focus_lost)
	get_viewport().focus_entered.connect(func(): app_focused = true; _update_battle_view())
	get_tree().set_auto_accept_quit(false)
	if not bool(data.get("migration_failed", false)):
		SupplyLineUpdater.acknowledge_update()
	if not is_test_mode:
		updater = SupplyLineUpdater.new()
		add_child(updater)
		updater.status_changed.connect(_update_status)
		updater.ready_changed.connect(func(_ready): _update_status(updater.status))
		if SupplyLineUpdater.available():
			updater.call_deferred("check", bool(data.settings.auto_update))

func _build_ui()->void:
	V2Interface.build(self)

func _notification(what:int)->void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if bool(data.get("migration_failed", false)):
			get_tree().quit()
			return
		if _training_session_open():
			_finish_training(false)
			if not reward_committed:
				return
		if not _save_current():
			info_title.text = "終了保存に失敗しました"
			info_text.text = "成果を保持したまま終了を中止しました。保存先を確認し、ウィンドウを閉じる操作で再試行してください。"
			info_review.hide()
			info_panel.show()
			return
		get_tree().quit()

func _save_current()->bool:
	_sync_combat_save()
	return is_test_mode or V2Save.save_data(data)

func _commit(candidate:Dictionary)->bool:
	if bool(data.get("migration_failed", false)):
		return false
	if not is_test_mode and not V2Save.save_data(candidate):
		save_warning = true
		return false
	data = candidate
	combat.set_data(data)
	save_warning = false
	return true

func _ack_migration()->void:
	var candidate := data.duplicate(true)
	candidate.v2_notice_seen = true
	if _commit(candidate):
		_refresh_prep()

func _retry_migration()->void:
	if is_test_mode:
		return
	data = V2Save.load_data()
	combat.configure(data)
	_apply_settings()
	_refresh_prep()

func _remember_selection()->void:
	data.selected_weapon = selected_weapon
	data.selected_difficulty = selected_difficulty
	data.selected_measurement = selected_measurement
	if not _save_current():
		save_warning = true

func _select_measurement(value:bool)->void:
	if mode != Mode.PREP:
		return
	selected_measurement = value
	_remember_selection()
	_refresh_prep()

func _refresh_prep()->void:
	if not free_button:
		return
	free_button.text = ("✓ " if not selected_measurement else "") + "自由練習 — 無制限"
	measure_button.text = ("✓ " if selected_measurement else "") + "兵士を作る — 60秒測定"
	for weapon in 3:
		weapon_buttons[weapon].text = ("✓ " if weapon == selected_weapon else "") + TrainingCatalog.TITLES[weapon] + "\n" + V2Rules.WEAPON_NAMES[weapon]
		weapon_buttons[weapon].set_pressed_no_signal(weapon == selected_weapon)
		difficulty_buttons[weapon].set_pressed_no_signal(weapon == selected_difficulty)
	difficulty_row.visible = not selected_measurement
	training_kind_info.text = "一回の60秒記録から一つの兵士プロフィール。採用は結果を見て手動で選べます。" if selected_measurement else "自由に練習し、射撃成果をクレジットとして保存。兵士の能力には変換しません。"
	difficulty_info.text = "測定は全武器共通の固定条件・位置固定。視点操作は自由です。" if selected_measurement else TrainingCatalog.difficulty_text(selected_weapon, selected_difficulty)
	start_button.text = "60秒測定を開始" if selected_measurement else "自由練習を開始"
	start_button.disabled = bool(data.get("migration_failed", false))
	condition_label.visible = start_button.disabled or save_warning
	condition_label.text = str(data.get("migration_error", "保存に失敗しました。保存先を確認して再試行してください。"))
	prep_goal.text = _next_goal_text(selected_weapon)
	migration_label.visible = not bool(data.get("v2_notice_seen", false)) or start_button.disabled
	migration_label.text = "v2では育成を刷新。感度・照準・音など個人設定だけを引き継ぎ、旧データは別名で保全します。\n新育成は0クレジット、ハンドガン1枠から。旧版のデータ・履歴は変更しません。"
	migration_retry.visible = start_button.disabled
	migration_ack.visible = migration_label.visible and not start_button.disabled
	_refresh_army_runtime()

func _next_goal_text(weapon:int)->String:
	if not V2Profiles.unlocked(data, weapon):
		return "次の加入：%s枠 — 累計 %s / %s クレジット（加入費なし）" % [V2Rules.WEAPON_NAMES[weapon], BigUInt.format(str(data.lifetime_credits)), V2Rules.UNLOCK_CREDITS[weapon]]
	return "%sの専用防具：有効な60秒測定 %d / 3回 — 無料で最大HP +20%%" % [V2Rules.WEAPON_NAMES[weapon], mini(3, int(data.measurement_counts[weapon]))]

func _show_prep()->void:
	super._show_prep()
	_stop_replay()
	_update_battle_view()

func _show_army()->void:
	super._show_army()
	_stop_replay()
	_refresh_army_runtime()
	_update_battle_view()

func _show_records()->void:
	super._show_records()
	_stop_replay()
	_update_battle_view()

func _open_help()->void:
	if mode not in [Mode.PREP, Mode.ARMY, Mode.RECORDS]:
		return
	info_title.text = "練習・測定と三人の部隊"
	info_review.hide()
	info_text.text = "自由練習は無制限、60秒測定は位置固定です。全武器を最初から練習できます。\n\n測定を完了し1発以上撃つと、記録からRPM・弾の命中率・命中時クリティカル率を算出します。命中ゼロでも有効。採用は手動です。\n\n部隊は各武器1枠・合計3人。累計1,000／3,000クレジットでアサルト／バーストが無料加入。各武器3回の測定で専用防具を無料解放します。\n\nEscで一時停止。部隊へ移動してから同じ練習に直接戻れます。部隊を見ている間は訓練だけ停止します。条件を確定変更した場合だけ別記録になります。\n\n実戦は採用記録の発射時刻を繰り返し、命中とクリティカルは記録由来の確率。『記録の再現』は実測の命中・外れをそのまま示す別モードです。"
	info_panel.show()
	_sync_navigation()

func _select_soldier(weapon:int)->void:
	selected_soldier = weapon
	_refresh_army_runtime()

func _refresh_army_runtime()->void:
	if not supply_label:
		return
	supply_label.text = "所持 %s クレジット" % BigUInt.format(str(data.credits))
	power_label.text = "部隊Lv.%d ／ 累計獲得 %s" % [V2Profiles.squad_level(data), BigUInt.format(str(data.lifetime_credits))]
	for weapon in 3:
		slot_buttons[weapon].text = ("✓ " if weapon == selected_soldier else "") + ["HG", "AR", "BR"][weapon] + (" 1枠" if V2Profiles.unlocked(data, weapon) else " 未加入")
		slot_buttons[weapon].set_pressed_no_signal(weapon == selected_soldier)
	var profile := V2Profiles.current(data, selected_soldier)
	if not profile_name.has_focus():
		profile_name.text = str(data.names[selected_soldier])
	soldier_summary.text = "%s\nRPM %.0f ／ 命中 %.1f%%\n命中時クリティカル %.1f%%" % [profile.label, float(profile.rpm), float(profile.p) * 100.0, float(profile.c) * 100.0]
	soldier_flavor.text = str(profile.flavor)
	var level := int(data.protection[selected_soldier])
	armor_summary.text = "測定防具 %d / 3回%s\n防護強化 %d / 5 ／ 次区間の最大HP %.0f" % [mini(3, int(data.measurement_counts[selected_soldier])), "・解放済み +20%" if bool(data.armor[selected_soldier]) else "・3回で無料 +20%", level, V2Profiles.hp(data, selected_soldier)]
	protection_button.text = "防護強化 完了" if level >= 5 else "防護 +10%% — %d クレジットで購入" % V2Rules.PROTECTION_COSTS[level]
	protection_button.disabled = not V2Profiles.unlocked(data, selected_soldier) or level >= 5 or bool(data.get("migration_failed", false)) or (level < 5 and BigUInt.compare(str(data.credits), str(V2Rules.PROTECTION_COSTS[level])) < 0)
	deployed_check.set_pressed_no_signal(bool(data.deployed[selected_soldier]))
	deployed_check.disabled = not V2Profiles.unlocked(data, selected_soldier)
	revert_button.disabled = data.previous_profiles[selected_soldier].is_empty()
	army_resume.visible = training_in_army
	army_end.visible = training_in_army
	var snapshot := combat.snapshot()
	if snapshot.is_empty():
		return
	front_label.text = "第一遠征 %d / 12" % mini(12, int(snapshot.section) + 1) if int(snapshot.section) < 12 else "継続戦線 %d" % (int(snapshot.section) - 11)
	var statuses := {"fighting":"交戦中", "marching":"次の区間へ前進", "retreat":"全員が撤退。未突破区間へ無料で再挑戦できます", "complete":"第一遠征を完了！ 続きを選べます（追加通貨なし）", "idle":"出撃する兵士を選んで再挑戦してください"}
	battle_summary.text = str(statuses.get(str(snapshot.status), snapshot.status))
	retry_battle_button.visible = str(snapshot.status) in ["retreat", "idle"]
	continue_button.visible = str(snapshot.status) == "complete"
	_update_battle_view()

func _save_name()->void:
	var candidate := data.duplicate(true)
	candidate.names[selected_soldier] = profile_name.text.strip_edges().left(24)
	if str(candidate.names[selected_soldier]).is_empty():
		candidate.names[selected_soldier] = ["ハンドガン兵", "アサルト兵", "バースト兵"][selected_soldier]
	army_message.text = "名前を保存しました（能力は変わりません）" if _commit(candidate) else "名前を保存できませんでした。"

func _purchase_protection()->void:
	var candidate := data.duplicate(true)
	if not V2Profiles.purchase(candidate, selected_soldier):
		return
	army_message.text = "防護強化を保存。次の区間・再挑戦から反映します。" if _commit(candidate) else "保存に失敗したため購入していません。"
	_refresh_army_runtime()

func _toggle_deployed(enabled:bool)->void:
	var candidate := data.duplicate(true)
	if V2Profiles.set_deployed(candidate, selected_soldier, enabled):
		army_message.text = "次の区間・再挑戦から出撃変更を反映します。" if _commit(candidate) else "保存できず、出撃状態を維持しました。"
	_refresh_army_runtime()

func _revert_profile()->void:
	var candidate := data.duplicate(true)
	if V2Profiles.revert(candidate, selected_soldier):
		army_message.text = "直前の採用へ戻しました。次の戦闘から反映します。" if _commit(candidate) else "保存に失敗しました。採用は変更していません。"
	_refresh_army_runtime()

func _open_soldier_details()->void:
	var profile := V2Profiles.current(data, selected_soldier)
	info_title.text = str(data.names[selected_soldier]) + " — プロフィール詳細"
	info_review.hide()
	info_text.text = _profile_detail(profile)
	for actor in combat.snapshot().get("allies", []):
		if int(actor.weapon) == selected_soldier:
			info_text.text += "\n\n現在区間の実戦：発射 %d ／ 命中 %d ／ クリティカル %d\nこれは直近実戦の値で、基準確率へ強制一致させません。" % [actor.shots, actor.hits, actor.criticals]
	info_panel.show()
	_sync_navigation()

func _profile_detail(profile:Dictionary)->String:
	if bool(profile.get("basic", false)):
		return "基礎兵士（ゲームの標準値）\n基準RPM %.0f（攻撃機会が継続する場合）\n命中率 %.1f%% ／ 命中時クリティカル %.1f%%\nこれは人の測定記録ではありません。発射数・命中数・命中弾Qは実測していません。\n有効な60秒測定を手動採用すると、一回の記録からPとQ、C=0.30Qを算出します。" % [profile.rpm, float(profile.p) * 100.0, float(profile.c) * 100.0]
	return "%s\n%s\n基準RPM %.1f（攻撃機会が継続する場合）\n基準命中率 P = H/N = %.3f\n命中弾中心精度 Q = Σq/H = %.3f\n命中時クリティカル C = 0.30Q = %.3f\n全攻撃のクリティカル確率 P×C = %.3f\nクリティカル倍率 1.5\n実発射 %d ／ 有効命中 %d\n発射間隔：平均 %.3f秒 ／ 標準偏差 %.3f秒\nプロフィール変換v%d\n%s" % [str(profile.label), str(profile.get("date", "ゲームの標準値。人の測定記録ではありません。")), profile.rpm, profile.p, profile.q, profile.c, float(profile.p) * float(profile.c), profile.get("shot_count", profile.rpm), profile.get("hit_count", 0), profile.get("interval_mean", 0.0), profile.get("interval_sd", 0.0), profile.profile_version, profile.flavor]

func _sync_combat_save()->void:
	if combat.state.is_empty():
		return
	for key in combat.persistent_state():
		data[key] = combat.persistent_state()[key]

func _process_battle(delta:float)->void:
	if bool(data.get("migration_failed", false)):
		return
	var events := combat.advance(delta)
	_sync_combat_save()
	if mode == Mode.ARMY:
		diorama.set_effects_enabled(bool(data.settings.get("effects_enabled", true)))
		diorama.consume(events)
		_play_battle_events(events)
		_refresh_army_runtime()
	for event in events:
		if str(event.type) in ["march", "section", "complete", "retreat"]:
			_save_current()
	battle_save_timer += delta
	if battle_save_timer >= 15.0:
		battle_save_timer = 0.0
		_save_current()

func _retry_battle()->void:
	if mode != Mode.ARMY:
		return
	var pending := combat.copy_runtime()
	var events := pending.retry(data)
	var candidate := data.duplicate(true)
	for key in pending.persistent_state():
		candidate[key] = pending.persistent_state()[key]
	if not _commit(candidate):
		army_message.text = "再挑戦の保存に失敗しました。再読み込みできます。"
		return
	combat = pending
	combat.set_data(data)
	diorama.reset_timeline()
	diorama.consume(events)
	_refresh_army_runtime()

func _continue_battle()->void:
	var pending := combat.copy_runtime()
	var events := pending.continue_expedition(data)
	var candidate := data.duplicate(true)
	for key in pending.persistent_state():
		candidate[key] = pending.persistent_state()[key]
	if not _commit(candidate):
		army_message.text = "継続戦線の保存に失敗しました。"
		return
	combat = pending
	combat.set_data(data)
	diorama.consume(events)
	_refresh_army_runtime()

func _update_battle_view()->void:
	if not diorama:
		return
	if world:
		world.visible = mode in [Mode.COUNTDOWN, Mode.TRAINING] or (mode == Mode.PAUSED and mode_before_pause in [Mode.COUNTDOWN, Mode.TRAINING])
	if target_root:
		target_root.visible = not training_measurement or mode == Mode.TRAINING or (mode == Mode.PAUSED and mode_before_pause == Mode.TRAINING)
	diorama.set_active(mode == Mode.ARMY and app_focused)
	if mode == Mode.ARMY:
		diorama.show_state(combat.snapshot())
	if replay_diorama:
		replay_diorama.set_active(mode == Mode.RESULT and app_focused)

func _play_battle_events(events:Array)->void:
	if not bool(data.settings.get("effects_enabled", true)):
		return
	for event in events:
		if str(event.type) == "ally_shot":
			_play_shot_sound()
			if bool(event.hit):
				_play_hit_sound(0, bool(event.critical))
			break

func _refresh_goals()->void:
	pass

func _refresh_goal_hud()->void:
	goal_hud.hide()
	goal_notification.hide()

func _update_growth_feedback(_delta:float)->void:
	pass

func _start_training()->void:
	if bool(data.get("migration_failed", false)) or (updater and updater.is_applying()):
		return
	training_measurement = selected_measurement
	measurement_settings_changed = false
	measurement_shooting = false
	measurement_frame_elapsed = 0.0
	measurement_frame_usec = Time.get_ticks_usec()
	last_target_sample = -1.0
	measured_final = {}
	measurement = V2Measurement.new()
	measurement_seed = int(Time.get_ticks_usec())
	measurement_rng.seed = measurement_seed
	spawn_serial = 0
	quadrant_counts = [0, 0, 0, 0]
	target_ids.clear()
	next_auto_shot = -1.0
	next_burst_shot = -1.0
	burst_serial = 0
	burst_bullet = 0
	var free_difficulty := selected_difficulty
	if training_measurement:
		measurement.begin(selected_weapon, data.settings, measurement_seed)
	super._start_training()
	selected_difficulty = free_difficulty
	if training_measurement:
		measurement.record.record_id = session_id
		training_difficulty = 1
		shooting_metrics.setting_key = ShootingMetrics.setting_key(training_weapon, 1, data.settings)
		training_duration = 60
		time_left = 60.0
		data.selected_difficulty = free_difficulty
	_stop_replay()
	_update_battle_view()

func _retry_training()->void:
	if mode != Mode.RESULT:
		return
	selected_measurement = training_measurement
	selected_weapon = training_weapon
	_start_training()

func _spawn_targets()->void:
	super._spawn_targets()
	if not training_measurement:
		return
	player.position = Vector3(0, 1.6, 0)
	var radius := float(V2Rules.MEASUREMENT_CONDITIONS.radius)
	for target in targets:
		var mesh := target.get_child(0) as MeshInstance3D
		mesh.mesh = mesh.mesh.duplicate()
		mesh.mesh.radius = radius
		mesh.mesh.height = radius * 2.0
		var ring := target.get_child(1) as MeshInstance3D
		ring.mesh = ring.mesh.duplicate()
		ring.mesh.inner_radius = radius * 0.48
		ring.mesh.outer_radius = radius * 0.62
		var collision := target.get_child(2) as CollisionShape3D
		collision.shape = SphereShape3D.new()
		collision.shape.radius = radius
		var marker := target.get_node("CenterMark") as MeshInstance3D
		marker.mesh = marker.mesh.duplicate()
		marker.mesh.radius = radius * 0.12
		marker.mesh.height = radius * 0.24
	if training_weapon == 1:
		targets[0].position = _auto_position(0.0)
		target_ids = ["moving-0"]
		measurement.target_event(0.0, "spawn", "moving-0", {"position":targets[0].position, "radius":radius, "moving":true})
	measurement.pose(0.0, camera.global_position, Vector3(camera.rotation.x, player.rotation.y, 0))

func _relocate_target(index:int)->void:
	if not training_measurement:
		super._relocate_target(index)
		return
	if index >= targets.size():
		return
	while target_ids.size() <= index:
		target_ids.append("")
	if not target_ids[index].is_empty():
		measurement.target_event(training_elapsed, "kill", target_ids[index])
	var rules:Dictionary = V2Rules.MEASUREMENT_CONDITIONS
	var initial := target_ids[index].is_empty()
	var previous := targets[index].position
	var near := floori((spawn_serial + 1) * float(rules.near_fraction)) > floori(spawn_serial * float(rules.near_fraction))
	var candidate := Vector3.ZERO
	var best := Vector3.ZERO
	var best_penalty := INF
	var selected_quadrant := 0
	for attempt in 160:
		candidate = Vector3(measurement_rng.randf_range(-float(rules.range), float(rules.range)), measurement_rng.randf_range(0.9, 3.9), float(rules.distance_z))
		var quadrant := (0 if candidate.x < 0.0 else 1) + (0 if candidate.y < 2.4 else 2)
		var distance := candidate.distance_to(previous)
		var minimum := float(rules.near_min if near else rules.far_min)
		var maximum := float(rules.near_max if near else rules.far_max)
		var penalty := 0.0 if initial else maxf(0.0, minimum - distance) + maxf(0.0, distance - maximum)
		for other in targets.size():
			if other != index:
				penalty += maxf(0.0, 1.6 - candidate.distance_to(targets[other].position))
		penalty = penalty * 100000.0 + float(quadrant_counts[quadrant]) + measurement_rng.randf() * 0.2
		if penalty < best_penalty:
			best = candidate
			best_penalty = penalty
			selected_quadrant = quadrant
	quadrant_counts[selected_quadrant] += 1
	targets[index].position = best
	target_progress[index] = 0
	target_precisions[index] = 0.0
	target_spawn_times[index] = training_elapsed
	target_ids[index] = "target-%d" % spawn_serial
	spawn_serial += 1
	measurement.target_event(training_elapsed, "spawn", target_ids[index], {"position":best, "radius":rules.radius})

func _auto_position(phase:float)->Vector3:
	if not training_measurement:
		return super._auto_position(phase)
	var rules:Dictionary = V2Rules.MEASUREMENT_CONDITIONS
	return Vector3(sin(phase) * float(rules.range), 2.45 + sin(phase * 0.63) * 1.15, float(rules.distance_z))

func _update_targets(delta:float)->void:
	if not training_measurement:
		super._update_targets(delta)
		return
	if training_weapon == 1 and not targets.is_empty():
		target_phase += delta * float(V2Rules.MEASUREMENT_CONDITIONS.speed)
		targets[0].position = _auto_position(target_phase)
		if training_elapsed - last_target_sample >= 1.0 / 30.0 - 0.000001:
			measurement.target_event(training_elapsed, "move", target_ids[0] if not target_ids.is_empty() else "moving-0", {"position":targets[0].position, "radius":V2Rules.MEASUREMENT_CONDITIONS.radius})
			last_target_sample = training_elapsed
	for target in targets:
		target.get_node("CenterMark").position = (camera.global_position - target.global_position).normalized() * float(V2Rules.MEASUREMENT_CONDITIONS.radius) * 1.015

func _ray_hit()->Dictionary:
	if not training_measurement:
		return super._ray_hit()
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var radius := float(V2Rules.MEASUREMENT_CONDITIONS.radius)
	var closest := INF
	var result:Dictionary = {}
	# Measurement targets have known unobstructed bounds. Their current centers
	# are authoritative, not the previous physics tick's StaticBody transforms.
	for index in targets.size():
		var offset := targets[index].global_position - origin
		var projection := offset.dot(direction)
		var perpendicular_sq := maxf(0.0, offset.length_squared() - projection * projection)
		if perpendicular_sq > radius * radius or projection <= 0.0:
			continue
		var distance := projection - sqrt(maxf(0.0, radius * radius - perpendicular_sq))
		if distance < 0.0 or distance >= closest:
			continue
		closest = distance
		var q := Balance.center_quality(origin, direction, targets[index].global_position, radius)
		result = {"index":index, "q":q, "precision":pow(q, 1.5), "end":origin + direction * distance}
	return result

func _fire_shot()->void:
	if not training_measurement:
		super._fire_shot()
		return
	if mode != Mode.TRAINING or training_elapsed < 0.0 or training_elapsed >= 60.0 or exit_holding:
		return
	var hit := _ray_hit()
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var endpoint:Vector3 = hit.get("end", origin + direction * 20.0)
	var id := target_ids[int(hit.index)] if not hit.is_empty() else ""
	if training_weapon == 1:
		measurement.target_event(training_elapsed, "move", "moving-0", {"position":targets[0].position, "radius":V2Rules.MEASUREMENT_CONDITIONS.radius})
	measurement.shot(training_elapsed, not hit.is_empty(), float(hit.get("q", 0.0)), id, origin, direction, endpoint, burst_serial if training_weapon == 2 else -1, burst_bullet)
	super._fire_shot()

func _unhandled_input(event:InputEvent)->void:
	if training_measurement and mode == Mode.TRAINING:
		var event_time := measurement_frame_elapsed + clampf(float(Time.get_ticks_usec() - measurement_frame_usec) / 1000000.0, 0.0, V2Rules.MAX_FRAME_DELTA)
		if event.is_action_pressed("shoot") or event.is_action_released("shoot"):
			_accept_measurement_shoot(event.is_action_pressed("shoot"), event_time)
			get_viewport().set_input_as_handled()
			return
		_consume_measurement_until(maxf(training_elapsed, minf(60.0, event_time)))
		if training_elapsed >= 60.0:
			_finish_training(true)
			return
	super._unhandled_input(event)

func _accept_measurement_shoot(pressed:bool, event_time:float)->void:
	_consume_measurement_until(maxf(training_elapsed, minf(60.0, event_time)))
	if training_elapsed >= 60.0:
		_finish_training(true)
		return
	if not pressed:
		measurement_shooting = false
		next_auto_shot = -1.0
		mouse_blocked = false
		return
	if mouse_blocked or exit_holding:
		return
	if training_weapon == 0:
		_fire_shot()
	elif training_weapon == 1:
		if not measurement_shooting:
			measurement_shooting = true
			_fire_shot()
			next_auto_shot = training_elapsed + float(V2Rules.MEASUREMENT_CONDITIONS.auto_interval)
	elif burst_remaining == 0:
		burst_remaining = 3
		burst_bullet = 0
		burst_serial += 1
		next_burst_shot = training_elapsed
		_fire_shot()
		burst_remaining -= 1
		burst_bullet += 1
		next_burst_shot += float(V2Rules.MEASUREMENT_CONDITIONS.burst_interval)

func _physics_process(delta:float)->void:
	if training_measurement:
		player.velocity = Vector3.ZERO
	else:
		super._physics_process(delta)

func _process(delta:float)->void:
	if not training_measurement or mode not in [Mode.COUNTDOWN, Mode.TRAINING]:
		super._process(delta)
	else:
		_process_measurement(delta)
	_process_result_preview(delta)
	_update_battle_view()

func _process_measurement(delta:float)->void:
	if not app_focused or delta <= 0.0 or delta > V2Rules.MAX_FRAME_DELTA:
		measurement_frame_elapsed = training_elapsed
		measurement_frame_usec = Time.get_ticks_usec()
		return
	_process_battle(delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	hit_sound_cooldown = maxf(0.0, hit_sound_cooldown - delta)
	hit_label.modulate.a = clampf(hit_flash * 5.0, 0.0, 1.0)
	if mode == Mode.COUNTDOWN:
		countdown -= delta
		countdown_label.text = "開始まで %d" % maxi(1, ceili(countdown))
		if countdown <= 0.0:
			mode = Mode.TRAINING
			countdown_label.text = ""
			mouse_blocked = Input.is_action_pressed("shoot")
			measurement_frame_elapsed = 0.0
			measurement_frame_usec = Time.get_ticks_usec()
		return
	var endpoint := minf(60.0, maxf(training_elapsed, measurement_frame_elapsed + delta))
	if exit_holding:
		exit_hold += delta
		exit_ring.value = exit_hold
		exit_ring.show()
		exit_hint.show()
		if exit_hold >= 0.8:
			_finish_training(false)
			return
	_consume_measurement_until(endpoint)
	measurement_frame_elapsed = training_elapsed
	measurement_frame_usec = Time.get_ticks_usec()
	point_display_timer = maxf(0.0, point_display_timer - delta)
	measurement.pose(minf(training_elapsed, 59.999999), camera.global_position, Vector3(camera.rotation.x, player.rotation.y, 0))
	_update_hud()
	checkpoint_timer += delta
	if endpoint >= 60.0:
		_finish_training(true)
	elif checkpoint_timer >= 15.0:
		_checkpoint_training()

func _consume_measurement_until(endpoint:float)->void:
	if training_weapon == 1 and measurement_shooting and not mouse_blocked and not exit_holding:
		if next_auto_shot < training_elapsed - 0.000001:
			next_auto_shot = training_elapsed
		while next_auto_shot < endpoint - 0.000000001 and next_auto_shot < 60.0:
			_measurement_advance_time(next_auto_shot)
			_fire_shot()
			next_auto_shot += float(V2Rules.MEASUREMENT_CONDITIONS.auto_interval)
	else:
		next_auto_shot = -1.0
	if training_weapon == 2 and burst_remaining > 0 and not exit_holding:
		while burst_remaining > 0 and next_burst_shot < endpoint - 0.000000001 and next_burst_shot < 60.0:
			_measurement_advance_time(maxf(training_elapsed, next_burst_shot))
			_fire_shot()
			burst_remaining -= 1
			burst_bullet += 1
			next_burst_shot += float(V2Rules.MEASUREMENT_CONDITIONS.burst_interval)
	_measurement_advance_time(endpoint)

func _measurement_advance_time(next_time:float)->void:
	var step := maxf(0.0, next_time - training_elapsed)
	if step == 0.0:
		return
	training_elapsed = next_time
	_update_targets(step)
	if training_weapon == 1 and measurement_shooting and not mouse_blocked and not exit_holding:
		active_seconds += step
		var before := _training_result()
		var hit := _ray_hit()
		stats.fire_time = float(stats.fire_time) + step
		ShootingMetrics.tracking(shooting_metrics, float(hit.get("q", 0.0)), step)
		if not hit.is_empty():
			stats.track_time = float(stats.track_time) + step
			stats.base_points = float(stats.base_points) + 100.0 * step
			stats.center_bonus = float(stats.center_bonus) + 100.0 * step * float(hit.precision)
			auto_streak_time += step
			stats.streak_bonus = float(stats.streak_bonus) + (5.0 * step if auto_streak_time > 1.0 else 0.0)
			_add_point_feedback(before, point_display_timer <= 0.0)
		else:
			auto_streak_time = maxf(0.0, auto_streak_time - step * 2.0)
	else:
		active_seconds += minf(activity_window, step)
		activity_window = maxf(0.0, activity_window - step)

func _update_hud()->void:
	var result := _training_result()
	timer_label.text = "測定 残り %.1f秒" % maxf(0.0, 60.0 - training_elapsed) if training_measurement else "自由練習 経過 " + Balance.clock_text(training_elapsed)
	stat_label.text = "今回獲得 %d クレジット" % int(result.score)
	credit_hud.text = ("時間の追従率 %.1f%%" if training_weapon == 1 else "命中率 %.1f%%") % (float(result.accuracy) * 100.0)
	if save_warning:
		credit_hud.text += " ／ 保存再試行中"
	goal_hud.hide()
	goal_notification.hide()

func _session_record()->Dictionary:
	var record := super._session_record()
	record.duration = 60 if training_measurement else 0
	if training_measurement:
		record.measurement = measured_final.duplicate(true) if not measured_final.is_empty() else measurement.snapshot(training_elapsed)
	return record

func _checkpoint_training()->bool:
	checkpoint_timer = 0.0
	if not _training_session_open() or training_elapsed <= 0.0:
		return not bool(data.get("migration_failed", false))
	var candidate := data.duplicate(true)
	V2Ledger.checkpoint(candidate, _session_record())
	return _commit(candidate)

func _finish_training(full_time:bool)->void:
	if reward_committed:
		return
	if training_measurement and measured_final.is_empty():
		measured_final = measurement.completed(training_elapsed, not full_time, measurement_settings_changed)
	var record := _completed_record()
	var candidate := data.duplicate(true)
	V2Ledger.finish(candidate, record, "終了", measured_final)
	_reset_exit_hold()
	burst_remaining = 0
	Input.action_release("shoot")
	mouse_blocked = true
	audio_player.stop()
	hit_audio_player.stop()
	if not _commit(candidate):
		mode_before_pause = Mode.TRAINING
		mode = Mode.PAUSED
		pause_panel.show()
		pause_menu.show()
		settings_page.hide()
		pause_warning.text = "終了保存に失敗しました。『訓練を終了』で再試行できます。成果はまだ確定していません。"
		pause_warning.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		crosshair.hide()
		return
	reward_committed = true
	training_in_army = false
	condition_panel.hide()
	last_result_record = record.duplicate(true)
	candidate_record = measured_final.duplicate(true)
	mode = Mode.RESULT
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	prep_panel.hide()
	army_panel.hide()
	hud.hide()
	pause_panel.hide()
	result_panel.show()
	_clear_targets()
	_present_result()
	_sync_navigation()

func _completed_record()->Dictionary:
	var record := _session_record()
	record.status = "終了"
	record.metrics.complete = true
	if training_measurement:
		record.metrics.setting_key = "measurement-v%d|" % V2Rules.MEASUREMENT_VERSION + str(record.metrics.setting_key)
		record.metrics.settings_changed = measurement_settings_changed
	record.metrics.comparison_reason = ShootingMetrics.reason(record)
	record.metrics.comparison_eligible = str(record.metrics.comparison_reason).is_empty()
	var history:Array = []
	for previous in data.training_history:
		if previous.has("measurement") == training_measurement:
			history.append(previous)
	record.shooting_comparison = ShootingMetrics.comparison(record, history)
	return record

func _present_result()->void:
	trial_running = false
	var profile := V2Profiles.from_record(candidate_record)
	var measured := not candidate_record.is_empty()
	result_title.text = "60秒測定の結果" if measured else "自由練習の結果"
	result_detail.text = "%s ／ %s" % [V2Rules.WEAPON_NAMES[int(last_result_record.get("weapon", 0))], str(last_result_record.get("started", ""))]
	result_points.text = "今回獲得 %d クレジット" % int(last_result_record.get("credits", 0))
	result_wallet.text = "所持 %s ／ 累計 %s" % [BigUInt.format(str(data.credits)), BigUInt.format(str(data.lifetime_credits))]
	result_values.visible = measured
	result_review.visible = not measured
	if not measured:
		result_review.set_review(ShootingMetrics.presentation(last_result_record))
		result_flavor.text = "自由練習の成果を保存しました。この記録から兵士は作りません。"
		result_comparison.text = ""
	elif profile.is_empty():
		result_values.text = "プロフィール作成なし"
		result_comparison.text = str(candidate_record.get("invalid_reason", "60秒完了と実発射1発以上が必要です。"))
		result_flavor.text = "獲得済みクレジットは保存済み。測定完了回数には加算していません。"
	else:
		var weapon := int(profile.weapon)
		var current := V2Profiles.current(data, weapon)
		result_values.text = "RPM %.0f\n基準命中率 %.1f%%\n命中時クリティカル %.1f%%" % [profile.rpm, float(profile.p) * 100.0, float(profile.c) * 100.0]
		result_comparison.text = "現在採用 → この記録\nRPM %.0f → %.0f ／ 命中 %.1f → %.1f%%\nクリティカル %.1f → %.1f%%\n間隔のばらつき %.3f → %.3f秒" % [current.rpm, profile.rpm, float(current.p) * 100.0, float(profile.p) * 100.0, float(current.c) * 100.0, float(profile.c) * 100.0, current.get("interval_sd", 0), profile.interval_sd]
		result_flavor.text = str(profile.flavor)
		if int(profile.hit_count) == 0:
			result_flavor.text += " ／ この記録は命中ゼロ。命中率・クリティカル率は0です。"
		if candidate_record.get("settings", {}) != data.settings:
			result_comparison.text += "\n設定が異なります。純粋な技能向上とは断定できません。"
	var already_adopted:bool = not profile.is_empty() and str(V2Profiles.current(data, int(profile.weapon)).record_id) == str(profile.record_id)
	adopt_button.disabled = profile.is_empty() or already_adopted
	adopt_button.text = "この記録を採用して保存" if not profile.is_empty() and not V2Profiles.unlocked(data, int(profile.weapon)) else "この記録を採用（次の戦闘から反映）"
	result_message.text = ""
	if not profile.is_empty() and not V2Profiles.unlocked(data, int(profile.weapon)):
		result_message.text = "出撃解放は累計 %s クレジット。今はプロフィールだけ保存できます。" % V2Rules.UNLOCK_CREDITS[int(profile.weapon)]
	replay_button.disabled = not measured or candidate_record.get("shots", []).is_empty()
	skip_replay_button.disabled = replay_button.disabled
	trial_button.disabled = profile.is_empty()
	if measured and not candidate_record.get("shots", []).is_empty():
		_restart_replay()
	else:
		replay_label.text = "自由練習 — 記録の再現対象ではありません" if not measured else "実発射がないため再現なし"
		replay_diorama.set_preview(int(last_result_record.get("weapon", 0)), false)
	_update_battle_view()

func _open_history_record(record:Dictionary)->void:
	last_result_record = record.duplicate(true)
	candidate_record = record.get("measurement", {}).duplicate(true)
	training_measurement = not candidate_record.is_empty()
	training_weapon = int(record.weapon)
	training_difficulty = int(record.difficulty)
	reward_committed = true
	mode = Mode.RESULT
	records_view.hide()
	result_panel.show()
	_present_result()
	_sync_navigation()

func _adopt_result()->void:
	if mode != Mode.RESULT:
		return
	var candidate := data.duplicate(true)
	if not V2Profiles.adopt(candidate, candidate_record):
		result_message.text = "この記録はすでに採用中です。" if not V2Profiles.from_record(candidate_record).is_empty() else "有効な60秒測定ではありません。"
		return
	if _commit(candidate):
		result_message.text = "採用を保存しました。次の区間・再挑戦から反映します。報酬や完了回数は増えません。"
		adopt_button.disabled = true
	else:
		result_message.text = "保存に失敗したため採用していません。元の兵士を保持しています。"

func _open_v2_result_details()->void:
	if mode != Mode.RESULT:
		return
	info_title.text = "測定の詳細・変換条件" if not candidate_record.is_empty() else "自由練習の詳細"
	var profile := V2Profiles.from_record(candidate_record)
	info_review.visible = candidate_record.is_empty()
	info_text.text = _profile_detail(profile) if not profile.is_empty() else str(candidate_record.get("invalid_reason", "自由練習は従来の採点・技能指標を維持します。"))
	if not candidate_record.is_empty():
		info_text.text += "\n\n測定ルールv%d ／ seed %s\n条件 %s\n設定 %s\n命中弾だけのQです。外れ込みの中心評価とは別の値です。" % [candidate_record.measurement_version, candidate_record.seed, str(candidate_record.conditions), str(candidate_record.settings)]
	else:
		info_review.set_review(ShootingMetrics.presentation(last_result_record), true)
	info_panel.show()
	_sync_navigation()

func _restart_replay()->void:
	if candidate_record.is_empty():
		return
	trial_running = false
	var visual_record := candidate_record.duplicate(true)
	visual_record.armor = bool(data.armor[int(candidate_record.weapon)])
	replay.start(visual_record)
	replay_diorama.set_preview(int(candidate_record.weapon), bool(data.armor[int(candidate_record.weapon)]))
	replay_label.text = "記録の再現 %.1f〜%.1f秒（他の部分は省略・等速）" % [replay.start_time, replay.end_time]

func _skip_replay()->void:
	replay.playing = false
	trial_running = false
	replay_label.text = "再現をスキップしました。採用・再測定はいつでも操作できます。"

func _stop_replay()->void:
	replay.playing = false
	trial_running = false
	if replay_diorama:
		replay_diorama.set_active(false)

func _process_result_preview(delta:float)->void:
	if mode != Mode.RESULT or not app_focused or info_panel.visible or delta > 0.25:
		return
	if trial_running:
		replay_diorama.set_effects_enabled(bool(data.settings.get("effects_enabled", true)))
		var events := trial.advance(delta)
		trial_elapsed += delta
		replay_diorama.consume(events)
		_play_battle_events(events)
		replay_diorama.show_state(trial.snapshot())
		if trial_elapsed >= 8.0:
			var summary := {"shots":0, "hits":0, "criticals":0}
			for actor in trial.snapshot().allies:
				for key in summary:
					summary[key] += int(actor[key])
			trial_results.append(summary)
			if trial_phase == 0:
				trial_phase = 1
				_begin_trial_phase()
			else:
				trial_running = false
				replay_label.text = "兵士の試射完了 — 同じ相手・seed。短期の参考であり真の強さの判定ではありません。"
				result_message.text = "8秒の試射：現在 %d発/%d命中 → 候補 %d発/%d命中（通貨・測定回数・戦線に影響なし）" % [trial_results[0].shots, trial_results[0].hits, trial_results[1].shots, trial_results[1].hits]
	elif replay.playing:
		replay_diorama.set_effects_enabled(bool(data.settings.get("effects_enabled", true)))
		var events := replay.advance(delta)
		replay_diorama.show_replay(replay.record, replay.time, replay.targets, replay.pose_state)
		replay_diorama.consume_replay(events)
		if bool(data.settings.get("effects_enabled", true)):
			for event in events:
				if str(event.get("type", "")) == "shot":
					_play_shot_sound()
					if bool(event.hit):
						_play_hit_sound(0, float(event.q) >= 0.8)
					break

func _start_trial()->void:
	if V2Profiles.from_record(candidate_record).is_empty():
		return
	replay.playing = false
	trial_results.clear()
	trial_phase = 0
	trial_running = true
	_begin_trial_phase()

func _begin_trial_phase()->void:
	trial_data = V2Save.defaults()
	var weapon := int(candidate_record.weapon)
	trial_data.lifetime_credits = "3000"
	trial_data.deployed = [false, false, false]
	trial_data.deployed[weapon] = true
	trial_data.armor = data.armor.duplicate()
	trial_data.protection = data.protection.duplicate()
	trial_data.profiles[weapon] = data.profiles[weapon].duplicate(true)
	if trial_phase == 1:
		V2Profiles.adopt(trial_data, candidate_record)
	trial.configure(trial_data, 20261025)
	replay_diorama.reset_timeline()
	replay_diorama.show_state(trial.snapshot())
	trial_elapsed = 0.0
	replay_label.text = "兵士の試射 — %s ／ 8秒、同じ相手・固定seed" % ("現在採用" if trial_phase == 0 else "候補記録")

func _draft_settings()->Dictionary:
	var draft := super._draft_settings()
	draft.effects_enabled = effects_check.button_pressed if effects_check else true
	return draft

func _sync_settings_controls(source:Dictionary)->void:
	if effects_check:
		effects_check.set_pressed_no_signal(bool(source.get("effects_enabled", true)))
	super._sync_settings_controls(source)

func _apply_settings_draft()->void:
	var draft := V2Save.validate_settings(_draft_settings())
	var restart_measurement:bool = _training_session_open() and training_measurement and draft != data.settings
	var candidate := data.duplicate(true)
	candidate.settings = draft
	if not _commit(candidate):
		settings_dirty = true
		return
	settings_snapshot = data.settings.duplicate(true)
	settings_dirty = false
	_apply_settings()
	if restart_measurement:
		measurement_settings_changed = true
		_finish_training(false)
		if reward_committed:
			selected_measurement = true
			_start_training()

func _reset_settings_draft()->void:
	_sync_settings_controls(V2Save.SETTING_DEFAULTS)
	settings_dirty = true

func _apply_update()->void:
	if not updater or not updater.ready_to_apply or _training_session_open():
		return
	if not _save_current():
		_update_status("保存に失敗したため更新を中止しました")
		return
	updater.apply_update()

func _refresh_condition_picker()->void:
	if not condition_measure:
		return
	condition_difficulty.disabled = condition_measure.button_pressed
	condition_description.text = "60秒・位置固定・共通条件。変更確定時は新しい測定になります。" if condition_measure.button_pressed else TrainingCatalog.difficulty_text(condition_weapon.selected, condition_difficulty.selected)

func _open_condition_picker()->void:
	super._open_condition_picker()
	condition_measure.set_pressed_no_signal(training_measurement)
	_refresh_condition_picker()

func _confirm_condition_picker()->void:
	if not condition_panel.visible or mode != Mode.PAUSED:
		return
	var weapon := condition_weapon.selected
	var difficulty := condition_difficulty.selected
	var measured := condition_measure.button_pressed
	if weapon == training_weapon and measured == training_measurement and (measured or difficulty == training_difficulty):
		_cancel_condition_picker()
		return
	if training_measurement and measured_final.is_empty():
		var pending := V2Measurement.new()
		pending.record = measurement.record.duplicate(true)
		measured_final = pending.completed(training_elapsed, true, true)
	var record := _completed_record()
	var candidate := data.duplicate(true)
	V2Ledger.finish(candidate, record, "終了", measured_final)
	if not _commit(candidate):
		measured_final = {}
		condition_warning.text = "保存に失敗し、条件は変更していません。再試行できます。"
		return
	reward_committed = true
	condition_panel.hide()
	selected_weapon = weapon
	selected_difficulty = difficulty
	selected_measurement = measured
	_start_training()

func _resume_pause()->void:
	if training_measurement and not measured_final.is_empty() and not reward_committed:
		pause_warning.text = "測定を終了保存中です。『訓練を終了』で保存を再試行してください。"
		pause_warning.show()
		return
	measurement_shooting = false
	next_auto_shot = -1.0
	measurement_frame_elapsed = training_elapsed
	measurement_frame_usec = Time.get_ticks_usec()
	super._resume_pause()

func _open_pause()->void:
	measurement_shooting = false
	next_auto_shot = -1.0
	super._open_pause()

func _visit_army()->void:
	battle_summary_before = int(data.front)
	super._visit_army()
	_update_battle_view()

func _resume_from_army()->void:
	super._resume_from_army()
	if int(data.front) > battle_summary_before:
		hit_label.text = "部隊は %d 区間前進しました" % (int(data.front) - battle_summary_before)
		hit_flash = 1.2

func _add_point_feedback(before:Dictionary, display:bool)->void:
	super._add_point_feedback(before, display)
	hit_label.text = hit_label.text.replace(" P", " クレジット")
