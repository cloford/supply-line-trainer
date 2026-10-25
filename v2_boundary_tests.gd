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
	game.data.settings.shot_sound = 3
	game.data.settings.hit_sound = 3
	game._show_prep()
	game.selected_measurement = true
	game.selected_weapon = weapon
	game._start_training()
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
	game.selected_measurement = true
	game._start_training()
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
	game._retry_battle()
	check(game.data == before and game.combat.snapshot() == runtime, "failed retry changed runtime/data")
	game.combat.state.status = "complete"
	game.combat.state.section = 12
	game._sync_combat_save()
	before = game.data.duplicate(true)
	runtime = game.combat.snapshot()
	game._continue_battle()
	check(game.data == before and game.combat.snapshot() == runtime, "failed continuation changed runtime/data")
	game.is_test_mode = true
	V2Save.test_fail_step = ""
	# A failed close keeps the live process and offers retry instead of quitting.
	start(0)
	game._accept_measurement_shoot(true, 1.0)
	game.is_test_mode = false
	V2Save.test_fail_step = "temp"
	game._notification(game.NOTIFICATION_WM_CLOSE_REQUEST)
	check(not game.reward_committed and game.mode == game.Mode.PAUSED and game.pause_warning.visible, "failed close discarded retry state")
	V2Save.test_fail_step = ""
	game.is_test_mode = true
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
