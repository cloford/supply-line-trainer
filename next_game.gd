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

func _ready()->void:
	super._ready()
	feedback_url = "https://github.com/cloford/supply-line-trainer/discussions/9"
	DisplayServer.window_set_title("Supply Line Trainer " + SupplyLineUpdater.current_version())
	_update_progress_ui()

func _build_ui()->void:
	super._build_ui()
	var prep_actions := HBoxContainer.new()
	start_button.get_parent().add_child(prep_actions)
	start_button.get_parent().move_child(prep_actions, start_button.get_index() + 1)
	V2Interface.button(prep_actions, "武器一覧", _open_roster)
	V2Interface.button(prep_actions, "実績一覧", _open_achievements)
	V2Interface.button(pause_menu, "武器一覧・次の練習を選ぶ", _open_roster)
	V2Interface.button(pause_menu, "実績一覧", _open_achievements)
	progression_view = ProgressionView.new()
	ui.add_child(progression_view)
	progression_view.theme = TrainerTheme.create()
	progression_view.weapon_selected.connect(_choose_roster_weapon)
	progression_view.closed.connect(_close_progress_overlay)
	extra_result = V2Interface.label(replay_diorama.get_parent(), "", 18)
	extra_result.custom_minimum_size = Vector2(400, 180)
	replay_diorama.get_parent().move_child(extra_result, replay_diorama.get_index() + 1)
	extra_result.hide()

func _commit(candidate:Dictionary)->bool:
	var okay := super._commit(candidate)
	if okay:
		progress_dirty = true
	return okay

func _save_current()->bool:
	var okay := super._save_current()
	if okay:
		progress_dirty = true
	return okay

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
	measure_button.disabled = selected_weapon >= 3
	var rows := Progression.weapon_rows(data)
	for weapon in 5:
		var row:Dictionary = {}
		for item in rows:
			if int(item.id) == weapon:
				row = item
		weapon_buttons[weapon].visible = not row.is_empty() and (weapon == 0 or Progression.list_visible(data))
		var unlocked := Progression.unlocked(data, weapon)
		weapon_buttons[weapon].disabled = not unlocked
		weapon_buttons[weapon].text = (("✓ " if weapon == selected_weapon else "") + TrainingCatalog.NAMES[weapon] + "\n" + TrainingCatalog.TITLES[weapon]) if unlocked else "???\n累計 %d 達成で解放" % int(row.get("threshold", 0))
		weapon_buttons[weapon].set_pressed_no_signal(weapon == selected_weapon)
	for difficulty in 3:
		difficulty_buttons[difficulty].set_pressed_no_signal(difficulty == selected_difficulty)
	difficulty_row.visible = not selected_measurement and selected_weapon < 3
	training_kind_info.text = "60秒の有効な測定から兵士を作ります。途中終了は進行達成に含めません。" if selected_measurement else "自由練習の撃破・有効追従1秒で達成を積み、次の武器へ。"
	if selected_weapon >= 3:
		training_kind_info.text += " この練習は兵士に採用できません。"
	difficulty_info.text = "測定は従来の固定条件・位置固定。視点操作は自由です。" if selected_measurement else TrainingCatalog.difficulty_text(selected_weapon, selected_difficulty)
	start_button.text = "60秒測定を開始" if selected_measurement else "自由練習を開始"
	start_button.disabled = bool(data.get("migration_failed", false))
	condition_label.visible = start_button.disabled or save_warning
	condition_label.text = str(data.get("migration_error", "保存に失敗しました。保存先を確認して再試行してください。"))
	prep_goal.text = "撃破・追従達成 %d ／ %s" % [Progression.total(data), "5達成で右側の武器一覧が登場" if not Progression.list_visible(data) else "武器一覧で次の条件を確認できます"]
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
	if value and selected_weapon >= 3:
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
	if progress_dirty or progress_retry_clock >= 1.0:
		progress_dirty = false
		progress_retry_clock = 0.0
		progression_view.refresh(_progress_model())
		var pending := Progression.pending_notifications(data)
		if not pending.is_empty():
			var candidate := data.duplicate(true)
			for achievement in pending:
				Progression.mark_seen(candidate, str(achievement.id))
			if _commit(candidate):
				for achievement in pending:
					progression_view.enqueue_notification(achievement)
			progress_retry_clock = 0.0
		if Progression.list_visible(data) and not bool(data.progression.get("list_seen", false)):
			var candidate := data.duplicate(true)
			Progression.mark_list_seen(candidate)
			if _commit(candidate):
				progression_view.set_context(true, false, true)
				progression_view.play_roster_intro()
			progress_retry_clock = 0.0
	var training := mode in [Mode.TRAINING, Mode.COUNTDOWN]
	var context := [training, roster_open, roster_open or (training and Progression.list_visible(data))]
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

func _unhandled_input(event:InputEvent)->void:
	if event.is_action_pressed("pause") and progression_view and (roster_open or progression_view.is_overlay_open()):
		progression_view.close_overlay()
		_close_progress_overlay()
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.TRAINING and not training_measurement and training_weapon >= 3 and event.is_action_pressed("shoot"):
		if not mouse_blocked and not exit_holding:
			_fire_shot()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _resume_pause()->void:
	if pending_weapon >= 0 and pending_weapon != training_weapon:
		if not Progression.unlocked(data, pending_weapon):
			pending_weapon = -1
			return
		condition_weapon.select(pending_weapon)
		condition_difficulty.select(training_difficulty)
		condition_measure.set_pressed_no_signal(training_measurement and pending_weapon < 3)
		condition_panel.show()
		_confirm_condition_picker()
		if mode != Mode.PAUSED:
			pending_weapon = -1
		return
	pending_weapon = -1
	super._resume_pause()

func _refresh_condition_picker()->void:
	if not condition_measure:
		return
	for weapon in condition_weapon.item_count:
		condition_weapon.set_item_disabled(weapon, not Progression.unlocked(data, weapon))
	var extra := condition_weapon.selected >= 3
	if extra:
		condition_measure.set_pressed_no_signal(false)
	condition_measure.disabled = extra
	super._refresh_condition_picker()
	if extra:
		condition_description.text = TrainingCatalog.difficulty_text(condition_weapon.selected, 0)
		condition_difficulty.disabled = true

func _confirm_condition_picker()->void:
	if not Progression.unlocked(data, condition_weapon.selected):
		condition_warning.text = "この練習はまだ解放されていません。"
		return
	if condition_weapon.selected >= 3:
		condition_measure.set_pressed_no_signal(false)
	super._confirm_condition_picker()

func _start_training()->void:
	if not Progression.unlocked(data, selected_weapon):
		return
	if selected_weapon >= 3:
		selected_measurement = false
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
			result = {"index":index, "q":q, "precision":pow(q, 1.5)}
	return result

func _fire_shot()->void:
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

func _process(delta:float)->void:
	progress_retry_clock += minf(delta, 0.25)
	super._process(delta)
	_maybe_progress_checkpoint()
	_update_progress_ui()
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

func _maybe_progress_checkpoint()->void:
	if training_measurement or mode != Mode.TRAINING or training_elapsed <= 0.0 or (save_warning and progress_retry_clock < 1.0):
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
	if training_weapon >= 3:
		record.extra = {"rule_version":1, "grid_switches":grid_switches.duplicate(), "grenade_events":grenade_events.duplicate(true), "in_flight":projectiles.size(), "blast_radius":TrainingExtras.BLAST_RADIUS, "blast_damage":TrainingExtras.BLAST_DAMAGE}
	return record

func _training_result()->Dictionary:
	if training_weapon < 3:
		return super._training_result()
	return Balance.score_and_reward(0 if training_weapon == 3 else 2, training_difficulty, stats if training_weapon == 3 else _grenade_score_stats(), 0, 0, training_elapsed, session_fraction)

func _grenade_score_stats()->Dictionary:
	var values := stats.duplicate(true)
	# 1発あたり最大9クレジット。巻き込み人数を命中弾数にしない。
	values.base_points = float(stats.get("base_points", 0.0)) / float(Balance.POINT_WEIGHTS[2]) / float(Balance.DIFFICULTY[training_difficulty].reward)
	return values

func _update_hud()->void:
	super._update_hud()
	credit_hud.text += " ／ 撃破・追従達成 %d" % Progression.total(data)
	if training_measurement:
		credit_hud.text += "（今回分は有効完了時）"
	elif training_weapon >= 3:
		credit_hud.text += " ／ 自由練習専用"

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
	info_text.text = "ハンドガンから開始。5達成で一覧、累計10／100／500／1,500達成で次の武器を解放します。射撃中は一覧を閲覧し、Escで停止して操作できます。武器を選んだ後の再開で、現在の記録を一度閉じて切り替えます。\n\n達成は標的撃破一体につき一回。アサルトは標的上での有効追従累計1秒につき一回。空撃ち・再現・試射・部隊からは増えません。測定分は60秒の有効完了時だけ反映します。\n\nグリッドとグレネードは自由練習専用。兵士は従来どおりHG・AR・BR各1枠の計3人。部隊加入は累計クレジット、FPSの練習解放は達成回数で別の条件です。\n\n0.21への番号変更で既存の育成・クレジット・個人設定はリセットしません。"
	info_panel.show()
	_sync_navigation()
