extends SceneTree

var failures:Array[String] = []
var checks := 0
func _init()->void:call_deferred("_run")
func check(ok:bool,message:String)->void:
	checks += 1
	if not ok:failures.append(message)

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":quit(2);return
	# 定義を複製せず、中心/端・配点上限・全域連続性を共有関数の外から確認する。
	for risk in [0.0,0.25,0.5,0.75,1.0]:
		var previous := -1.0
		for index in 1001:
			var actual := TargetScoring.reward_factor(float(index)/1000.0,risk)
			check(actual >= previous and actual > 0.0 and (previous < 0.0 or actual-previous < 0.04),"curve monotone/continuous/positive")
			previous = actual
		if risk > 0.0:
			check(TargetScoring.reward_factor(0.0,risk) < TargetScoring.reward_factor(0.0,risk-0.25),"risk lowers edge")
			check(TargetScoring.reward_factor(1.0,risk) > TargetScoring.reward_factor(1.0,risk-0.25),"risk raises center")
	var average:Array = []
	for risk in [0.0,0.5,1.0]:
		var sum := 0.0
		for index in 1000:
			var radial := sqrt((float(index)+0.5)/1000.0)
			sum += TargetScoring.reward_factor(1.0-radial,risk)/1000.0
		average.append(sum)
	check(average[0] > average[1] and average[1] > average[2],"uniform-area aim has real risk")
	print("CURVE_COMPARISON ",JSON.stringify({"uniform_area":average,"center":[TargetScoring.reward_factor(1,0),TargetScoring.reward_factor(1,0.5),TargetScoring.reward_factor(1,1)]}))
	for weapon in 3:
		for other in [0.0,0.2,0.8]:
			var old_stats := {"base_points":100.0,"center_bonus":100.0,"speed_bonus":other*50.0,"streak_bonus":other*50.0}
			var old := Balance.score_and_reward(weapon,0,old_stats,0,0,1.0)
			var changed := old_stats.duplicate()
			changed.center_bonus = 100.0*(TargetScoring.reward_factor(1.0)-1.0)
			var current := TargetScoring.score(weapon,0,changed,0.0)
			var ratio := float(current.exact_points)/float(old.exact_points)
			check(ratio >= 1.99 and ratio <= 2.11,"default center total about twice including capped speed/streak")
			check(current.base+current.center+current.speed+current.streak == current.score and current.score == current.supply,"rounded score conserved")
	var game = load("res://main.tscn").instantiate()
	game.is_test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.progression.preserved_weapons = [0,1,2]
	game.data.completed_measurement_ids = ["existing-measurement-access"]
	Progression.apply_record(game.data,{"weapon":0,"progress_kills":1500})
	game.data.settings.shot_sound = 3
	game.data.settings.hit_sound = 3
	for weapon in 5:
		game._show_prep()
		game.selected_weapon = weapon
		game.selected_measurement = false
		game._start_training()
		game.mode = game.Mode.TRAINING
		game.mouse_blocked = false
		game.training_elapsed = 0.5
		game.camera.look_at(game.targets[0].global_position)
		var before:Dictionary = game._training_result()
		if weapon == 1:
			Input.action_press("shoot")
			game._process_weapon(0.2)
			Input.action_release("shoot")
		elif weapon == 4:
			var projectile := TrainingExtras.launch(Vector3.ZERO,Vector3.FORWARD,0)
			projectile["generation"] = game.grenade_generation
			game.stats.shots = 1
			game._explode(projectile,{"position":game.targets[0].global_position,"direct_index":0})
		else:game._fire_shot()
		var after:Dictionary = game._training_result()
		check(after.score > before.score and game.credit_feedback_amount == after.score-before.score,"actual feedback conserved weapon "+str(weapon))
		check(game.hit_flash == 1.8,"feedback doubled weapon "+str(weapon))
		game.stats.base_points += 20.0
		game._add_point_feedback(after,false)
		check(game.credit_feedback_amount == game._training_result().score-before.score,"continuous feedback aggregates exact award")
		if weapon != 4:
			check(game._session_record().scoring_version == TargetScoring.VERSION,"new scoring record version")
			check(is_equal_approx(game._preview_target_points(1.0,game.training_risk),game._preview_target_points(0.0,game.training_risk)*TargetScoring.reward_factor(1.0)/TargetScoring.reward_factor(0.0)),"preview same curve")
		await game._finish_training(false)
	# 測定は自由練習の編集値によらず、旧固定配点/生のqで動く。
	for risk in [0.0,1.0]:
		game.data.target_risk = risk
		game.selected_weapon = 0
		game.selected_measurement = true
		game._start_training()
		game.mode = game.Mode.TRAINING
		game.training_elapsed = 0.2
		game.mouse_blocked = false
		game.camera.look_at(game.targets[0].global_position)
		game._fire_shot()
		var expected := Balance.score_and_reward(0,1,game.stats,0,0,game.training_elapsed,game.session_fraction)
		check(game.training_measurement and game._training_result() == expected and game._ray_hit().get("precision",0.0) <= 1.0,"measurement fixed scoring and precision")
		check(game._session_record().scoring_version == Balance.SCORING_VERSION and game.measurement.record.shot_count == 1,"measurement facts/version preserved")
		await game._finish_training(false)
	game.queue_free()
	for frame in 3:await process_frame
	if failures.is_empty():print("SCORING_REGRESSION_OK checks=",checks," curve, center totals, actual five-mode feedback, fixed measurement");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
