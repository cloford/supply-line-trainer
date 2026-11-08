extends SceneTree

var game
var failures:Array[String] = []
var checks := 0

func check(value:bool, message:String)->void:
	checks += 1
	if not value:
		failures.append(message)

func _init()->void:
	call_deferred("_run")

func start(weapon:int)->void:
	game.data = V2Save.defaults()
	game.data.progression.preserved_weapons = [0, 1, 2]
	game.data.completed_measurement_ids = ["fixture-measurement-access"]
	game.data.settings.shot_sound = 3
	game.data.settings.hit_sound = 3
	game._show_prep()
	game.selected_measurement = true
	game.selected_weapon = weapon
	game._start_training()
	game._presentation_drawn_for_test()
	game.mode = game.Mode.TRAINING
	game.mouse_blocked = false
	game.training_elapsed = 0.0
	game.measurement_frame_elapsed = 0.0

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.is_test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.completed_measurement_ids = ["fixture-measurement-access"]
	game.selected_measurement = true
	game._start_training()
	game._presentation_drawn_for_test()
	check(game.mode == game.Mode.COUNTDOWN and not game.target_root.visible, "measurement target exposed before active clock")
	for tick in 31:
		game._process(0.1)
		if game.mode == game.Mode.TRAINING:
			break
	check(game.target_root.visible and game.training_elapsed == 0.0, "target/input/clock start not synchronized")
	# Current transforms, no wait for physics: AR center and HG immediate relocation.
	start(1)
	game._measurement_advance_time(0.4)
	game.camera.look_at(game.targets[0].global_position)
	check(not game._ray_hit().is_empty() and game._ray_hit().q > 0.999, "AR current-center ray stale")
	start(0)
	game.training_elapsed = 0.1
	game.camera.look_at(game.targets[0].global_position)
	game._fire_shot()
	game._fire_shot()
	check(game.measurement.record.hit_count == 1 and game.measurement.record.shots.size() == 2, "HG old collider still hit after relocation")
	# Press and release occur on the input clock, not only at rendered frames.
	for fps in [30, 60, 120]:
		start(1)
		game._accept_measurement_shoot(true, 0.002)
		game._accept_measurement_shoot(false, 0.006)
		game._process(1.0 / fps)
		check(game.measurement.record.shot_count == 1 and is_equal_approx(game.measurement.record.shots[0].time, 0.002), "same-frame AR tap lost or backdated at fps " + str(fps))
		check(is_equal_approx(game.training_elapsed, 1.0 / fps), "input flush double-counted frame delta")
		start(1)
		game._accept_measurement_shoot(true, 0.002)
		for frame in range(fps):
			game._process(1.0 / fps)
		game._accept_measurement_shoot(false, 1.002)
		var times:Array = []
		for shot in game.measurement.record.shots:
			times.append(snappedf(float(shot.time), 0.000001))
		var expected := [0.002,0.102,0.202,0.302,0.402,0.502,0.602,0.702,0.802,0.902]
		var equal := times.size() == expected.size()
		for index in mini(times.size(), expected.size()):
			equal = equal and is_equal_approx(float(times[index]), float(expected[index]))
		check(equal, "held AR timeline/release boundary differs at fps %d: %s" % [fps, str(times)])
	start(2)
	game._accept_measurement_shoot(true, 59.9)
	game._consume_measurement_until(60.0)
	check(game.measurement.record.shot_count == 2, "burst terminal input was rounded back")
	# No input at/after 60 can be backdated to a prior frame.
	start(0)
	game._accept_measurement_shoot(true, 60.001)
	check(game.mode == game.Mode.RESULT and game.candidate_record.shot_count == 0, "post-end input included")
	# Replay target generations and old combat sections remain bounded.
	var view := V2Diorama.new()
	root.add_child(view)
	for generation in 80:
		view.show_replay({"weapon":0,"armor":true}, generation * 0.01, {"t-%d" % generation:{"position":[0,2,-11],"radius":0.42}}, {})
	check(view._replay_targets.size() == 1 and view._replay_model.armor_enabled, "target generations exhausted cache or armor lost")
	for section in 80:
		view.show_state({"status":"fighting","time":section,"allies":[],"enemies":[{"id":"e-%d" % section,"kind":"light","alive":true}]})
	check(view._models.size() == 1 and view._effects.size() <= 24, "old combat models accumulated")
	for section in [12,13,50,10000]:
		check(V2Rules.enemy_group(section).size() <= V2Diorama.MAX_ENEMIES, "invisible enemies in continuation")
	view.queue_free()
	# Settings suppress visual events, and each trial phase resets deduplication.
	start(0)
	game._finish_training(false)
	game.data.settings.effects_enabled = false
	game._show_army()
	game.combat.configure(game.data)
	game.diorama.show_state(game.combat.snapshot())
	game._process_battle(0.1)
	check(game.diorama._effects.is_empty(), "effects suppression ignored")
	var recorder := V2Measurement.new()
	recorder.begin(0, game.data.settings, 1, "boundary-trial")
	for second in 60:
		recorder.shot(second, true, 1.0, "t", Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD)
	game.candidate_record = recorder.completed(60.0)
	game.data.settings.effects_enabled = true
	game.mode = game.Mode.RESULT
	game._start_trial()
	game._process_result_preview(0.1)
	var first_count:int = game.replay_diorama._effects.size()
	game.trial_phase = 1
	game._begin_trial_phase()
	game._process_result_preview(0.1)
	check(first_count > 0 and game.replay_diorama._effects.size() > 0, "trial candidate effects treated as duplicates")
	# Full runtime and persistent state are unchanged on retry/continue save failure.
	game._show_army()
	game.combat.state.status = "retreat"
	game._sync_combat_save()
	game.is_test_mode = false
	V2Save.test_fail_step = "temp"
	var before:Dictionary = game.data.duplicate(true)
	var runtime:Dictionary = game.combat.snapshot()
	await game._retry_battle()
	check(game.data == before and game.combat.snapshot() == runtime, "failed retry changed runtime/data")
	game.combat.state.status = "complete"
	game.combat.state.section = 12
	game._sync_combat_save()
	before = game.data.duplicate(true)
	runtime = game.combat.snapshot()
	await game._continue_battle()
	check(game.data == before and game.combat.snapshot() == runtime, "failed continuation changed runtime/data")
	game.is_test_mode = true
	V2Save.test_fail_step = ""
	# A failed close keeps the live process and offers retry instead of quitting.
	start(0)
	game._accept_measurement_shoot(true, 1.0)
	game.is_test_mode = false
	V2Save.test_fail_step = "temp"
	await game._notification(game.NOTIFICATION_WM_CLOSE_REQUEST)
	check(not game.reward_committed and game.mode == game.Mode.PAUSED and game.pause_warning.visible, "failed close discarded retry state")
	V2Save.test_fail_step = ""
	game.is_test_mode = true
	await _session_controls()
	game.queue_free()
	for frame in 3:
		await process_frame
	if failures.is_empty():
		print("V2_BOUNDARY_OK checks=", checks, " input clock, analytic rays, render lifecycle, trial, suppression and atomic transitions")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _session_controls()->void:
	game.data = V2Save.defaults()
	Progression.apply_record(game.data,{"weapon":0,"progress_kills":1500})
	game._show_prep()
	game.selected_weapon = 0
	game.selected_measurement = false
	game._start_training()
	game.mode = game.Mode.TRAINING
	game.training_elapsed = 1.25
	var original_id:String = game.session_id
	var original_pose:Transform3D = game.targets[0].transform
	game.tab_held = true
	game._open_tab()
	game._process(0.2)
	check(game.data.tab_guide_seen, "first valid Tab open acknowledges hint before any hit")
	check(game.interaction == game.Interaction.TAB and game.mode == game.Mode.PAUSED and game.training_elapsed == 1.25 and game.targets[0].transform == original_pose,"Tab immediately freezes clock and target")
	game._close_tab()
	check(game.mode == game.Mode.TRAINING and game.session_id == original_id and game.data.training_history.is_empty(),"opening Tab alone retains original session")
	game.tab_held = true
	game._open_tab()
	await game._tab_choose_weapon(1)
	check(game.mode == game.Mode.PAUSED and game.training_weapon == 1 and game.session_id != original_id and game.data.training_history.size() == 1,"Tab switch settles once into separate record")
	var switched_id:String = game.session_id
	await game._tab_choose_weapon(1)
	check(game.session_id == switched_id and game.data.training_history.size() == 1,"same weapon click does not settle twice")
	game._close_tab()
	check(game.mode == game.Mode.TRAINING and game.data.selected_weapon == 1,"Tab release switches without countdown and remembers weapon")
	game.training_elapsed = 0.75
	game.tab_held = true
	game._open_tab()
	game._open_target_editor()
	game._target_draft_changed(0.93)
	await game._apply_target_edit()
	check(game.data.training_history.size() == 2 and is_equal_approx(game.training_risk,0.93) and game._session_record().scoring_version == TargetScoring.VERSION,"curve edit separates score conditions")
	check(is_equal_approx(game.target_preview.center_points(),game._preview_target_points(1.0,0.93)),"editor shares actual weapon curve")
	game._close_tab()
	game.tab_held = true
	game._open_tab()
	await game._tab_start_measurement()
	game._close_tab()
	check(game.training_measurement and game.training_difficulty == 1,"measurement starts fixed conditions through unlocked Tab entry")
	game.training_elapsed = 0.5
	game.measurement.shot(0.2,true,1.0,"fixture",Vector3.ZERO,Vector3.FORWARD,Vector3.FORWARD)
	game.tab_held = true
	game._open_tab()
	await game._tab_choose_weapon(0)
	var interrupted:Dictionary = game.data.training_history[0].measurement
	check(interrupted.interrupted and not interrupted.valid and game.data.measurement_counts[1] == 0,"measurement weapon switch is interrupted and cannot make soldier")
	game._close_tab()
	game.tab_held = true
	game._open_tab()
	await game._tab_stop()
	game.tab_held = false
	game._close_tab()
	check(game.mode == game.Mode.RESULT and game.reward_committed and game.interaction == game.Interaction.NONE,"Tab stop cannot restart on release")
	game.selected_measurement = true
	game._show_prep()
	check(not game.selected_measurement and not game.weapon_buttons[0].is_visible_in_tree(),"preparation defaults to free practice and hides weapon selection")
	var history_count:int = game.data.training_history.size()
	var saved_risk:float = game.data.target_risk
	game._open_main_target_editor()
	game.target_slider.value = 0.12
	game._cancel_target_edit()
	check(game.mode == game.Mode.PREP and game.data.target_risk == saved_risk, "main editor cancel discards the draft")
	game._open_main_target_editor()
	game.target_slider.value = 0.31
	await game._apply_target_edit()
	check(game.mode == game.Mode.PREP and not game.target_editor.visible and is_equal_approx(game.data.target_risk, 0.31) and game.data.training_history.size() == history_count, "main editor apply saves without starting or splitting a session")
	game.selected_weapon = 0
	game._start_training()
	game.mode = game.Mode.TRAINING
	game._open_pause()
	game._open_reset_tools()
	game._request_reset_confirmation()
	check(game.reset_confirm.find_child("CancelReset",true,false).has_focus(),"reset confirmation defaults to Cancel")
	game.data.settings.sensitivity = 8.0
	await game._reset_all_data()
	check(game.data.credits == "0" and Progression.total(game.data) == 0 and game.data.settings.sensitivity == V2Save.SETTING_DEFAULTS.sensitivity and game.selected_weapon == 0 and not game.data.guidance_credited,"reset clears progress and personal settings in memory")
	check(game.intro_session and game.iris_intro.waiting and game.mode == game.Mode.COUNTDOWN,"reset returns to new-play guidance")
	check(not game.data.tab_guide_seen, "reset re-arms the Tab hint")
