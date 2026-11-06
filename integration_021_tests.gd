extends SceneTree

var game
var failures:Array[String] = []
var checks := 0
var output := ""

func _initialize()->void:
	call_deferred("_run")

func check(value:bool, message:String)->void:
	checks += 1
	if not value:
		failures.append(message)

func frames(count:int = 3)->void:
	for frame in count:
		await process_frame

func capture(name:String)->void:
	game._update_progress_ui()
	await frames()
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	for control in game.ui.find_children("*", "Button", true, false):
		if control.is_visible_in_tree():
			check(bounds.encloses(control.get_global_rect()), "button outside: " + name + " / " + control.text)
	for panel in [game.progression_view._roster_panel, game.progression_view._notification_panel, game.progression_view._achievements_panel]:
		if panel.is_visible_in_tree():
			check(bounds.encloses(panel.get_global_rect()), "progression panel outside: " + name + " " + str(panel.get_global_rect()))
	if game.progression_view._roster_panel.is_visible_in_tree():
		for label in game.progression_view._roster_list.find_children("*", "Label", true, false):
			if label.is_visible_in_tree() and not label.text.is_empty():
				check(label.size.x >= 80.0 and label.size.y >= 10.0, "weapon text collapsed: " + name + " / " + label.text)
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func begin(weapon:int, measured:bool = false)->void:
	game._show_prep()
	game.selected_weapon = weapon
	game.selected_measurement = measured
	game._request_start()
	for frame in 31:
		game._process(0.1)
		if game.mode == game.Mode.TRAINING:
			break
	game.mouse_blocked = false
	check(game.mode == game.Mode.TRAINING and game.training_weapon == weapon, "mode start failed: " + str(weapon))
	game.training_elapsed = 0.2
	game.measurement_frame_elapsed = 0.2

func aim(index:int = 0)->void:
	game.camera.look_at(game.targets[index].global_position)
	await physics_frame
	await physics_frame

func grant_all()->void:
	# 隔離fixture。解放境界自体はprogression_testsと冒頭の実射線で確認。
	Progression.apply_record(game.data, {"weapon":0,"progress_kills":1500})
	for achievement in Progression.pending_notifications(game.data):
		Progression.mark_seen(game.data, achievement.id)
	Progression.mark_list_seen(game.data)
	game.progress_dirty = true

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		quit(2)
		return
	output = OS.get_environment("SLT_CAPTURE_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	game = load("res://main.tscn").instantiate()
	game.is_test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.settings.shot_sound = 3
	game.data.settings.hit_sound = 3
	check(Progression.total(game.data) == 0 and Progression.unlocked(game.data,0) and not Progression.unlocked(game.data,1), "new game locks wrong")
	check(game.slot_buttons.size() == 3 and game.data.profiles.size() == 3, "army slots expanded")
	await capture("01-first-preparation")
	game._select_weapon(1)
	check(game.selected_weapon == 0, "locked selection allowed")
	begin(0)
	var fov:float = game.camera.fov
	for kill in 10:
		await aim()
		game._fire_shot()
		game._process(0.1)
		check(Progression.total(game.data) == kill + 1, "actual HG kill not once")
		if kill == 0:
			check(game.data.progression.achievements.has("first_kill"), "first kill missing achievement")
			game.progression_view._process(0.4)
			await capture("02-first-achievement")
		if kill == 4:
			check(Progression.list_visible(game.data) and game.data.progression.list_seen, "5 did not show/save roster intro")
			game.progression_view._process(0.4)
			await capture("03-five-achievements")
		if kill == 8:
			check(not Progression.unlocked(game.data,1), "9 unlocked AR")
	check(Progression.unlocked(game.data,1) and not Progression.unlocked(game.data,2), "10 boundary wrong")
	check(game.training_weapon == 0 and game.camera.fov == fov and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "unlock changed weapon/FOV/capture")
	for control in game.progression_view._roster_panel.find_children("*", "Control", true, false):
		check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "FPS roster intercepted mouse input")
	await capture("04-ten-unlocked")
	var before := Progression.total(game.data)
	game.camera.rotation.y += 1.2
	await physics_frame
	game._fire_shot()
	check(Progression.total(game.data) == before, "miss counted")
	game._open_pause()
	var saved_time:float = game.training_elapsed
	var saved_stats:Dictionary = game.stats.duplicate(true)
	game._open_roster()
	check(game.mode == game.Mode.PAUSED and game.roster_open, "paused roster failed")
	game._choose_roster_weapon(1)
	check(game.training_weapon == 0 and game.mode == game.Mode.PAUSED, "selection changed active weapon before resume")
	game._resume_pause()
	check(game.mode == game.Mode.COUNTDOWN and game.training_weapon == 1 and game.mouse_blocked, "resume switch failed")
	check(game.data.training_history.size() == 1 and game.data.training_history[0].metrics.shots == saved_stats.shots and float(game.data.training_history[0].elapsed) == saved_time, "switch lost/doubled old record")
	for frame in 31:
		game._process(0.1)
		if game.mode == game.Mode.TRAINING:break
	var initial:Vector3 = game.targets[0].position
	game._update_targets(0.0)
	check(game.targets[0].position == initial, "AR initial target jumped")
	game._finish_training(false)
	begin(1)
	await aim()
	await capture("05-auto-practice")
	game.training_elapsed = 1.0
	Input.action_press("shoot")
	game._process_weapon(0.4)
	Input.action_release("shoot")
	game._finish_training(false)
	check(Progression.total(game.data) == before, "AR fractional progress counted early")
	begin(1)
	await aim()
	game.training_elapsed = 1.0
	Input.action_press("shoot")
	game._process_weapon(0.6)
	Input.action_release("shoot")
	game._finish_training(false)
	check(Progression.total(game.data) == before + 1, "AR fraction not carried across sessions")
	var progress_before := Progression.total(game.data)
	begin(0,true)
	await aim()
	game._fire_shot()
	game._finish_training(false)
	check(Progression.total(game.data) == progress_before and game.adopt_button.disabled, "partial measurement progressed")
	grant_all()
	begin(2)
	await capture("05-burst-practice")
	game._finish_training(false)
	begin(3)
	check(not game.training_measurement and game.targets.size() == 1, "grid is not one target/free only")
	var cells:Array = [game.grid_previous]
	for index in 8:
		await aim()
		game.fire_cooldown = 0.0
		var previous:int = game.grid_previous
		game._fire_shot()
		check(game.grid_previous != previous, "grid repeated cell")
		cells.append(game.grid_previous)
	check(cells.duplicate().size() == 9 and game.stats.kills == 8 and game.stats.shots == 8, "grid facts wrong")
	var unique := {}
	for cell in cells:unique[cell] = true
	check(unique.size() == 9, "grid bag was biased before full cycle")
	await capture("06-grid-practice")
	game._finish_training(false)
	check(game.adopt_button.disabled and not game.result_review.visible, "grid offered soldier profile")
	await capture("07-grid-result")
	begin(4)
	game.camera.look_at(Vector3(-1.6, game.camera.global_position.y, -8.0))
	await capture("08-grenade-guide")
	var grenade_before := Progression.total(game.data)
	game._fire_shot()
	check(game.stats.shots == 1 and game.projectiles.size() == 1, "grenade did not fire real projectile")
	var position:Vector3 = game.projectiles[0].position
	game._open_pause()
	game._process(0.2)
	check(game.projectiles[0].position == position, "paused grenade moved")
	game._resume_pause()
	var impact_captured := false
	for frame in 45:
		game._process(0.05)
		if not impact_captured and not game.grenade_events.is_empty():
			impact_captured = true
			await capture("09-grenade-impact")
	check(game.stats.shots == 1 and game.stats.hits <= 1 and game.stats.kills >= 2, "grenade hits/kills mistaken or blast missed")
	check(game.grenade_events.size() == 1 and game.projectiles.is_empty(), "explosion repeated")
	check(Progression.total(game.data) == grenade_before + int(game.stats.kills), "grenade progress double counted")
	check(int(game._training_result().score) <= 10, "grenade per-shot credit cap failed")
	await capture("09-grenade-aftermath")
	game._finish_training(false)
	check(game.adopt_button.disabled, "GL offered profile")
	await capture("10-grenade-result")
	# 本番保存失敗→累計射撃事実を保持して再試行（実データでない）。
	begin(0)
	await aim()
	var protected:Dictionary = game.data.duplicate(true)
	game.is_test_mode = false
	V2Save.test_fail_step = "temp"
	game._fire_shot()
	check(game.data == protected and game.save_warning, "failed progression save changed state")
	V2Save.test_fail_step = ""
	for frame in 5:game._process(0.25)
	check(Progression.total(game.data) == Progression.total(protected) + 1, "retry lost or duplicated kill")
	game.is_test_mode = true
	game._finish_training(false)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		game._show_prep()
		await capture("prep-%dx%d" % [dimensions.x,dimensions.y])
		game._open_achievements()
		await capture("achievements-%dx%d" % [dimensions.x,dimensions.y])
		game.progression_view.close_overlay()
		begin(0)
		game._open_pause()
		game._open_roster()
		await capture("roster-%dx%d" % [dimensions.x,dimensions.y])
		game.progression_view.close_overlay()
		game._open_settings_page()
		await capture("settings-%dx%d" % [dimensions.x,dimensions.y])
		game._settings_back()
		game._finish_training(false)
	game.queue_free()
	await frames()
	if failures.is_empty():
		print("INTEGRATION_021_OK checks=", checks, " five actual modes, progression boundaries, switching, pause, save retry and layouts")
		quit(0)
	else:
		for failure in failures:push_error(failure)
		quit(1)
