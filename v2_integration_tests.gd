extends SceneTree

var game
var failures:Array[String] = []
var output := ""
var checks := 0

func _init()->void:
	call_deferred("_run")

func check(value:bool, message:String)->void:
	checks += 1
	if not value:
		failures.append(message)

func frames(count:int = 2)->void:
	for frame in count:
		await process_frame

func snap(name:String)->void:
	await frames(3)
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	for button in game.ui.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			check(bounds.encloses(button.get_global_rect()), "button clipped: " + name + " / " + button.text)
	for control in [game.result_card, game.pause_card, game.condition_card]:
		if control.is_visible_in_tree():
			check(bounds.encloses(control.get_global_rect()), "panel clipped: " + name)
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func begin(weapon:int, measured:bool)->void:
	game._show_prep()
	game.selected_weapon = weapon
	game.selected_measurement = measured
	game._request_start()
	for tick in 31:
		game._process(0.1)
		if game.mode == game.Mode.TRAINING:
			break
	check(game.mode == game.Mode.TRAINING, "countdown did not start")

func aim(index:int = 0)->void:
	game.camera.look_at(game.targets[index].global_position)
	await physics_frame
	await physics_frame

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		quit(1)
		return
	output = OS.get_environment("SLT_CAPTURE_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	game = load("res://main.tscn").instantiate()
	game.is_test_mode = true
	root.add_child(game)
	if game.diorama == null or game.result_values == null:
		push_error("v2 interface failed to initialize")
		quit(1)
		return
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.settings.shot_sound = 3
	game.data.settings.hit_sound = 3
	check(V2Save.PATH != SaveManager.PATH and game.data.credits == "0", "v2 did not start fresh")
	check(game.slot_buttons.size() == 3 and V2Profiles.unlocked(game.data, 0) and not V2Profiles.unlocked(game.data, 1), "fixed slots/unlock initial state")
	await snap("preparation")
	# Handgun physical rays: miss leaves target, hit kills, exact event ordering.
	begin(0, true)
	var player_position:Vector3 = game.player.position
	Input.action_press("move_forward")
	game._physics_process(0.2)
	Input.action_release("move_forward")
	check(game.player.position == player_position, "measurement allowed movement")
	await aim()
	game.training_elapsed = 0.2
	game.measurement_frame_elapsed = 0.2
	var first_id:String = game.target_ids[0]
	game._fire_shot()
	check(game.measurement.record.shot_count == 1 and game.measurement.record.hit_count == 1, "HG actual ray not captured")
	var events:Array = game.measurement.record.events
	var shot_index := -1
	for index in events.size():
		if events[index].type == "shot":
			shot_index = index
	check(shot_index >= 0 and str(events[shot_index + 1].type) == "kill" and str(events[shot_index + 2].type) == "spawn", "same-time hit/kill/spawn order")
	check(game.target_ids[0] != first_id, "HG hit did not immediately replace target")
	var retained_id:String = game.target_ids[0]
	game.camera.rotation.y += 1.3
	await physics_frame
	game.training_elapsed = 0.5
	game.measurement_frame_elapsed = 0.5
	game._fire_shot()
	check(game.target_ids[0] == retained_id and game.measurement.record.shot_count == 2, "miss removed target")
	game.training_elapsed = 59.95
	game.measurement_frame_elapsed = 59.95
	game._process(0.1)
	check(game.mode == game.Mode.RESULT and game.data.measurement_counts[0] == 1, "60s completion failed")
	var measured:Dictionary = game.candidate_record.duplicate(true)
	var profile := V2Profiles.from_record(measured)
	check(profile.rpm == 2 and profile.p == 0.5 and profile.c > 0.29, "actual measurement conversion wrong")
	check(game.data.profiles[0].is_empty(), "result auto-adopted")
	var credits:String = game.data.credits
	var lifetime:String = game.data.lifetime_credits
	game._adopt_result()
	game._adopt_result()
	check(not game.data.profiles[0].is_empty() and game.data.credits == credits and game.data.lifetime_credits == lifetime, "adoption duplicated payment")
	await snap("measurement-result")
	# A replay consumes the exact recorded events at several frame rates.
	var expected:Array = []
	for event in measured.events:
		if event.type == "shot" and float(event.time) < 8.0:
			expected.append(event)
	for fps in [30, 60, 120]:
		var player := V2Replay.new()
		player.start(measured)
		for tick in range(fps * 9):
			player.advance(1.0 / fps)
		check(player.emitted == expected, "replay changed recorded facts at fps " + str(fps))
	# AR: actual bullet hit rate is not time-weighted tracking accuracy.
	begin(1, true)
	await aim()
	Input.action_press("shoot")
	game.mouse_blocked = false
	game._accept_measurement_shoot(true, 0.0)
	for tick in 10:
		game._process(0.1)
	Input.action_release("shoot")
	game._accept_measurement_shoot(false, 1.0)
	check(game.measurement.record.shot_count == 10, "AR 0.1s event cadence")
	check(game.measurement.record.shots[0].time == 0.0 and game.stats.fire_time > 0.99, "AR initial bullet/tracking time")
	var before_pause:Dictionary = game.measurement.snapshot(game.training_elapsed)
	var phase:float = game.target_phase
	game._open_pause()
	game._process(10.0)
	check(game.measurement.snapshot(game.training_elapsed) == before_pause and game.target_phase == phase, "pause contaminated AR measurement")
	game._visit_army()
	var id:String = game.session_id
	var count:int = game.data.practice_totals.sessions
	var history_size:int = game.data.training_history.size()
	game._process(0.1)
	check(game.session_id == id and game.data.practice_totals.sessions == count and game.data.training_history.size() == history_size and game.target_phase == phase, "army visit closed/resumed wrong record")
	game._resume_from_army()
	check(game.mouse_blocked and game.mode == game.Mode.TRAINING, "army resume input unsafe")
	game.training_elapsed = 59.95
	game.measurement_frame_elapsed = 59.95
	game._process(0.1)
	check(game.data.measurement_counts[1] == 1 and not game.adopt_button.disabled, "locked AR measurement cannot be adopted")
	game._adopt_result()
	check(not game.data.profiles[1].is_empty() and not V2Profiles.unlocked(game.data, 1), "locked profile adoption changed unlock")
	# Burst events ending at 60: only the two actually emitted bullets exist.
	begin(2, true)
	await aim()
	game.training_elapsed = 59.9
	game.measurement_frame_elapsed = 59.9
	game.burst_remaining = 3
	game.burst_bullet = 0
	game.burst_serial = 7
	game.next_burst_shot = 59.9
	game._process(0.1)
	check(game.mode == game.Mode.RESULT and game.candidate_record.shot_count == 2, "burst terminal partial event count")
	check(game.candidate_record.shots[0].burst_id == 7 and game.candidate_record.shots[1].bullet_index == 1 and game.candidate_record.shots[1].time < 60.0, "burst metadata/boundary wrong")
	# Empty and interrupted measurements do not unlock armor or generate profiles.
	begin(0, true)
	var completions:int = game.data.measurement_counts[0]
	game.training_elapsed = 59.95
	game.measurement_frame_elapsed = 59.95
	game._process(0.1)
	check(game.adopt_button.disabled and game.data.measurement_counts[0] == completions, "empty measurement counted")
	begin(0, true)
	game.training_elapsed = 1.0
	game.measurement_frame_elapsed = 1.0
	await aim()
	game._fire_shot()
	game._finish_training(false)
	check(game.adopt_button.disabled and game.data.measurement_counts[0] == completions, "partial measurement counted")
	# Settings apply ends the old measurement, never mixes conditions.
	begin(0, true)
	game.training_elapsed = 1.0
	game.measurement_frame_elapsed = 1.0
	game._open_pause()
	game._open_settings_page()
	game.sensitivity_edit.text = "1.5"
	game._settings_changed()
	var old_id:String = game.session_id
	game._apply_settings_draft()
	check(game.session_id != old_id and game.mode == game.Mode.COUNTDOWN and game.training_measurement, "settings did not restart measurement")
	check(not game.data.training_history[0].measurement.valid, "mixed settings profile accepted")
	for tick in 31:
		game._process(0.1)
	game._open_pause()
	game._open_condition_picker()
	game.condition_measure.set_pressed_no_signal(false)
	game._confirm_condition_picker()
	check(not game.training_measurement and game.mode == game.Mode.COUNTDOWN, "condition picker did not change mode")
	# Saving an adoption failure leaves current profile + wallet intact.
	game._process(0.1)
	game._finish_training(false)
	game.candidate_record = measured.duplicate(true)
	game.data.profiles[0] = {}
	game.is_test_mode = false
	V2Save.test_fail_step = "temp"
	var protected:Dictionary = game.data.duplicate(true)
	game._adopt_result()
	check(game.data == protected, "failed adopt changed persistent data")
	V2Save.test_fail_step = ""
	game.is_test_mode = true
	# Render all major modes, actual 3D and 3 fixed unlocked soldiers.
	game.data.lifetime_credits = "3000"
	game.data.credits = "4000"
	game.data.armor = [true, true, true]
	game.data.measurement_counts = [3, 3, 3]
	game.combat.configure(game.data, 75)
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		game._show_prep()
		await snap("prep-%dx%d" % [dimensions.x, dimensions.y])
		game._show_army()
		await snap("army-%dx%d" % [dimensions.x, dimensions.y])
		game._select_soldier(1)
		game._open_soldier_details()
		await snap("profile-%dx%d" % [dimensions.x, dimensions.y])
		game._close_info()
		game._show_records()
		await snap("records-%dx%d" % [dimensions.x, dimensions.y])
		game._open_history_record(game.data.training_history.back())
		await snap("result-%dx%d" % [dimensions.x, dimensions.y])
		begin(0, true)
		game._open_pause()
		await snap("pause-%dx%d" % [dimensions.x, dimensions.y])
		game._open_settings_page()
		await snap("settings-%dx%d" % [dimensions.x, dimensions.y])
		game._settings_back()
		game._end_early()
	game.queue_free()
	await frames(4)
	if failures.is_empty():
		print("V2_INTEGRATION_OK checks=", checks, " actual rays, three weapons, 60s boundaries, replay facts, pause/army/settings, adoption/save and layouts")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)
