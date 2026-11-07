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
	for icon in game.ui.find_children("*", "Control", true, false):
		if icon is WeaponIcon and icon.is_visible_in_tree() and icon.get_parent() is Button:
			check(icon.get_parent().get_global_rect().encloses(icon.get_global_rect()), "button icon outside: " + name)
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
	if measured:game.data.completed_measurement_ids = ["fixture-measurement-access"]
	game._show_prep()
	game.selected_weapon = weapon
	game.selected_measurement = measured
	game._request_start()
	game._presentation_drawn_for_test()
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
	game._begin_boot()
	var fov:float = game.camera.fov
	check(game.mode == game.Mode.COUNTDOWN and game.intro_session and game.iris_intro.waiting and not game.prep_panel.visible,"boot did not enter dark training directly")
	check(game.targets[0].position == Vector3(0,1.7,-5),"boot target was not static/centered")
	game._process(0.1)
	check(game.training_elapsed == 0.0 and game.iris_intro.waiting,"boot advanced before first drawing")
	game._fire_shot()
	check(game.stats.shots == 0 and Progression.total(game.data) == 0,"intro shot counted")
	await capture("iris-wait-1280x720")
	game._open_pause()
	game._process(0.1)
	check(not game.iris_intro.visible and game.pause_panel.visible,"iris hid pause menu")
	await capture("iris-pause-1280x720")
	game._resume_pause()
	game._presentation_drawn_for_test()
	game._process(0.1)
	check(game.iris_intro.waiting,"resuming bypassed valid guidance hit")
	check(game._guidance_shot(),"valid guidance hit did not open")
	check(Progression.total(game.data) == 1 and game.stats.shots == 0,"guidance lifetime award and exclusion")
	var elapsed:float = game.iris_intro.elapsed
	game.app_focused = false
	game._process(0.1)
	check(game.iris_intro.elapsed == elapsed,"unfocused iris advanced")
	game.app_focused = true
	for tick in 8:game._process(0.1)
	check(not game.intro_session and game.mode == game.Mode.COUNTDOWN and game.countdown == 3.0,"intro did not lead to fresh countdown")
	game._presentation_drawn_for_test()
	game._process(0.1)
	var boot_anchor:Vector2 = game.camera.unproject_position(game.targets[0].global_position)
	for number in [3,2,1]:
		check(game.crosshair.is_visible_in_tree() and game.targets[0].is_visible_in_tree(),"countdown hid target/crosshair")
		check(game.camera.unproject_position(game.targets[0].global_position).is_equal_approx(boot_anchor),"countdown moved target projection")
		check(ceili(game.countdown-0.000001) == number,"countdown number missing")
		await capture("countdown-%d-1280x720" % number)
		for tick in 10:game._process(0.1)
	check(game.mode == game.Mode.TRAINING and game.training_elapsed == 0.0 and game.stats.shots == 0,"countdown counted shooting or elapsed")
	game.training_elapsed = 0.2
	game.mouse_blocked = false
	for kill in 9:
		await aim()
		game._fire_shot()
		game._process(0.1)
		check(Progression.total(game.data) == kill + 2, "actual HG kill not once")
		if kill == 0:
			check(game.data.progression.achievements.has("first_kill"),"first kill missing achievement")
			game.progression_view._process(0.4)
			await capture("02-first-achievement")
		if kill == 3:
			check(Progression.list_visible(game.data) and game.data.progression.list_seen, "5 did not show/save roster intro")
			game.progression_view._process(0.4)
			await capture("03-five-achievements")
		if kill == 7:
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
	await frames()
	var select_button:Button = game.progression_view._weapon_widgets[1].button
	check(select_button.mouse_filter == Control.MOUSE_FILTER_STOP, "roster selection stayed mouse transparent")
	var click := InputEventMouseButton.new()
	click.position = select_button.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click,true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click,true)
	await frames()
	check(game.pending_weapon == 1, "GUI roster select did not receive mouse input")
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
	game.save_worker.configure(game.data)
	V2Save.test_fail_step = "temp"
	game._fire_shot()
	check(Progression.total(game.data) == Progression.total(protected)+1 and game.mode == game.Mode.TRAINING, "memory progression waited for disk")
	game._process(0.016)
	var writes_in_frame:int = game.save_worker.writes
	for duplicate_request in 3:game._request_progress_save()
	game._process(0.016)
	check(game.save_worker.writes == writes_in_frame, "same-frame save requests dispatched twice")
	game.save_worker.finish()
	game._process(0.016)
	check(game.save_warning and Progression.total(game.data) == Progression.total(protected)+1, "failed async save lost live progression")
	V2Save.test_fail_step = ""
	game.save_worker.retry_after = 0.0
	await frames(1)
	game._process(0.016)
	game.save_worker.finish()
	game._process(0.016)
	check(Progression.total(game.data) == Progression.total(protected) + 1, "retry lost or duplicated kill")
	for retry in 5:
		if not game.save_worker.pending():break
		await frames(1)
		game._process(0.016)
		game.save_worker.finish()
	check(not game.save_worker.pending(), "failed async save did not retry: %d/%d %s" % [game.save_worker.durable,game.save_worker.requested,game.save_worker.error])
	await aim()
	game._fire_shot()
	game._process(0.016)
	var before_poll := Progression.total(game.data)
	await aim()
	game._fire_shot()
	game.save_worker.finish()
	game._process(0.016)
	check(Progression.total(game.data) == before_poll+1, "stale async snapshot rolled back live kill")
	game._open_pause()
	check(game.pause_panel.visible and game.mode == game.Mode.PAUSED, "pause did not appear immediately")
	check(game.save_worker.pending(), "request was incorrectly treated as durable")
	# 本番commit経路:保存完了まで購入候補を残高/能力へ反映せず、描画を継続する。
	game.save_worker.finish()
	game.data.credits = "5000"
	game.data.lifetime_credits = "5000"
	game._visit_army()
	game.selected_soldier = 0
	var balance:String = game.data.credits
	var level:int = game.data.protection[0]
	game._purchase_protection()
	check(game.durable_busy and game.busy_panel.visible,"durable purchase had no processing UI")
	check(game.data.credits == balance and game.data.protection[0] == level,"uncommitted purchase changed live data")
	var drawn_frames := 0
	while game.durable_busy:
		await process_frame
		drawn_frames += 1
	check(drawn_frames >= 2 and game.data.protection[0] == level+1,"purchase froze rendering or did not commit")
	balance = game.data.credits
	level = game.data.protection[0]
	V2Save.test_fail_step = "temp"
	await game._purchase_protection()
	check(game.data.credits == balance and game.data.protection[0] == level,"failed purchase changed data")
	V2Save.test_fail_step = ""
	await game._purchase_protection()
	check(game.data.protection[0] == level+1,"purchase retry failed")
	game._resume_from_army()
	check(game.mode == game.Mode.TRAINING,"army did not restore same practice")
	game._open_pause()
	game._open_condition_picker()
	game.condition_weapon.select(1)
	game.condition_measure.set_pressed_no_signal(false)
	game._confirm_condition_picker()
	check(game.durable_busy and game.training_weapon == 0,"condition changed before durable save")
	while game.durable_busy:await process_frame
	check(game.training_weapon == 1 and game.mode == game.Mode.COUNTDOWN,"condition did not start new countdown")
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
	# 再起動も有効命中待ち。後日の誘導は進行を追加しない。
	for dimensions in [Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		var retained:int = game.data.training_history.size()
		var retained_progress:int = Progression.total(game.data)
		var remembered_weapon:int = game.data.selected_weapon
		game._begin_boot()
		check(game.iris_intro.waiting and game.training_weapon == remembered_weapon and not game.training_measurement and not game.prep_panel.visible,"repeat boot lost selected weapon")
		check(game.data.training_history.size() == retained and Progression.unlocked(game.data,4),"boot reset records/unlocks")
		await capture("iris-wait-%dx%d" % [dimensions.x,dimensions.y])
		game._presentation_drawn_for_test()
		game._process(0.1)
		check(game._guidance_shot() and Progression.total(game.data) == retained_progress,"repeat guidance reacquired progress")
		game._process(0.2)
		await capture("iris-open-mid-%dx%d" % [dimensions.x,dimensions.y])
		for tick in 7:game._process(0.1)
		game._presentation_drawn_for_test()
		game._process(0.1)
		for number in [3,2,1]:
			check(game.crosshair.is_visible_in_tree() and game.targets[0].is_visible_in_tree(),"alternate countdown hid target/crosshair")
			await capture("countdown-%d-%dx%d" % [number,dimensions.x,dimensions.y])
			for tick in 10:game._process(0.1)
		check(game.mode == game.Mode.TRAINING and not game.iris_intro.is_active(),"boot left black overlay")
		await capture("iris-done-%dx%d" % [dimensions.x,dimensions.y])
		game._finish_training(false)
	# freshには確認操作を挟まず、真の移行/復旧と失敗だけ専用説明へ進む。
	game.data = V2Save.defaults()
	game.data.legacy_backup = "user://fixture-preserved-v1.json"
	game._begin_boot()
	check(game.boot_notice and game.busy_panel.visible and not game.prep_panel.visible,"legacy migration bypassed safety explanation")
	await game._boot_retry_action()
	check(game.data.v2_notice_seen and game.intro_session and game.mode == game.Mode.COUNTDOWN,"migration acknowledgement did not lead directly to HG")
	game.data = V2Save.defaults()
	game.data.recovery_notice = "直前の確定保存から復旧しました。"
	game._begin_boot()
	check(game.boot_notice and not game.prep_panel.visible,"recovery bypassed explanation")
	await game._boot_retry_action()
	check(not game.data.has("recovery_notice") and game.intro_session,"recovery explanation repeated after acknowledgement")
	game.data = V2Save._failure("fixture 保存を読み込めません")
	game._begin_boot()
	check(game.boot_error and game.boot_retry.visible and not game.prep_panel.visible,"failed load exposed prep or hid retry")
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	game._unhandled_input(escape)
	check(game.boot_error and not game.prep_panel.visible,"Esc ignored save failure and entered prep")
	game.queue_free()
	await frames()
	await create_timer(0.15).timeout
	if failures.is_empty():
		print("INTEGRATION_021_OK checks=", checks, " five actual modes, progression boundaries, switching, pause, save retry and layouts")
		quit(0)
	else:
		for failure in failures:push_error(failure)
		quit(1)
