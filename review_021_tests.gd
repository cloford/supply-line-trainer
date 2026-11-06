extends SceneTree

var failures:Array[String] = []
var checks := 0
var game

func _init()->void:
	call_deferred("_run")

func check(value:bool, message:String)->void:
	checks += 1
	print("REVIEW_021 ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func begin(weapon:int, measured:bool = false)->void:
	game._show_prep()
	game.selected_weapon = weapon
	game.selected_measurement = measured
	game._start_training()
	game.mode = game.Mode.TRAINING
	game.training_elapsed = 0.2
	game.mouse_blocked = false
	game._update_battle_view()

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		quit(2)
		return
	# JSON数値復元後も既存武器の利用権を維持する。
	var source := V2Save.defaults()
	source.progression.preserved_weapons = [1,2]
	var restored:Dictionary = JSON.parse_string(JSON.stringify(source))
	check(typeof(restored.progression.preserved_weapons[0]) == TYPE_FLOAT, "JSON fixture uses floating-point weapon IDs")
	check(Progression.unlocked(restored,1) and Progression.unlocked(restored,2), "preserved AR and BR survive JSON reload")
	# グリッドは9地点を一巡し、袋の境目も同地点が続かない。
	var bag:Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 78321
	var previous := -1
	var fair := true
	for cycle in 100:
		var visited := {}
		for turn in 9:
			var cell := TrainingExtras.next_cell(bag, previous, rng)
			fair = fair and cell != previous and not visited.has(cell)
			visited[cell] = true
			previous = cell
	check(fair, "grid 100 bags visit nine cells once and avoid consecutive cells")
	var positions:Array[Vector3] = [Vector3(0,1,-3),Vector3(1.8,1,-3),Vector3(2.21,1,-3)]
	check(TrainingExtras.victims(Vector3(0,1,-3),positions,0) == [0,1], "blast radius includes each victim once and excludes outside 2.2m")
	var projectile := TrainingExtras.launch(Vector3(0,1,0), Vector3.FORWARD, 1)
	var impact:Dictionary = {}
	for step in 100:
		impact = TrainingExtras.advance(projectile,0.02,positions,0.62)
		if not impact.is_empty():
			break
	check(not impact.is_empty() and int(impact.get("direct_index",-1)) == 0, "grenade segment collides with first target")
	var floor_shot := {"position":Vector3(0,0.1,0),"velocity":Vector3(0,-16,0),"age":0.0}
	var floor_impact := TrainingExtras.advance(floor_shot,0.02,[],0.62)
	check(not floor_impact.is_empty() and int(floor_impact.direct_index) == -1, "grenade collides with floor")
	var wall_shot := {"position":Vector3(0,1,-11.7),"velocity":Vector3(0,0,-16),"age":0.0}
	var wall_impact := TrainingExtras.advance(wall_shot,0.02,[],0.62)
	check(not wall_impact.is_empty() and int(wall_impact.direct_index) == -1, "grenade collides with back wall")
	var high_wall_shot := {"position":Vector3(0,10,-11.7),"velocity":Vector3(0,0,-16),"age":0.0}
	var high_wall_impact := TrainingExtras.advance(high_wall_shot,0.02,[],0.62)
	check(high_wall_impact.is_empty() and float(high_wall_shot.position.z) < -11.8, "grenade passes above visible back-wall height without collision")
	var sky_shot := TrainingExtras.launch(Vector3(0,1.7,8), Vector3.UP, 900)
	var sky_expiry := TrainingExtras.advance(sky_shot,4.1,[],0.62)
	check(bool(sky_expiry.get("expired",false)) and float(sky_shot.age) >= 4.0 and float(sky_shot.position.y) > 0.1, "four-second airborne lifetime returns expiry instead of impact")
	var predicted := TrainingExtras.predict(Vector3(0,1,0), Vector3.FORWARD, positions, 0.62)
	check(predicted[-1].distance_to(impact.position) < 0.001, "trajectory guide terminates at the same first target as ballistic kernel")
	var outside_floor := {"position":Vector3(0,0.1,-13),"velocity":Vector3(0,-16,0),"age":0.0}
	check(TrainingExtras.advance(outside_floor,0.02,[],0.62).is_empty(), "grenade does not collide with floor outside visible extent")
	var inside_floor := {"position":Vector3(0,0.1,11),"velocity":Vector3(0,-16,0),"age":0.0}
	check(not TrainingExtras.advance(inside_floor,0.02,[],0.62).is_empty(), "grenade collides with visible floor near front edge")
	game = load("res://main.tscn").instantiate()
	game.is_test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.settings.shot_sound = 3
	game.data.settings.hit_sound = 3
	game.data.progression.kills = 1500
	game.data.progression.total = 1500
	Progression._evaluate(game.data,true)
	begin(0)
	await physics_frame
	await physics_frame
	game.camera.look_at(game.targets[0].global_position)
	check(not game._ray_hit().is_empty(), "HG ray hits current visible target")
	game.targets[0].hide()
	check(game._ray_hit().is_empty(), "hidden target is excluded from free-practice ray")
	game.targets[0].show()
	# PhysicsServer同期前の一射目で同じコライダーを再利用しないこと。
	game._fire_shot()
	var first_kills := int(game.stats.kills)
	game.targets[0].global_position = game.camera.global_position - game.camera.global_transform.basis.z * 12.0 + game.camera.global_transform.basis.x * 5.0
	var old_aim_result:Dictionary = game._ray_hit()
	game._fire_shot()
	check(int(game.stats.kills) == first_kills, "HG immediate second click at old location cannot kill relocated target")
	print("REVIEW_021_HG_OLD_AIM ", old_aim_result)
	game._finish_training(false)
	await process_frame
	begin(1)
	await physics_frame
	await physics_frame
	var next_position:Vector3 = game._auto_position(1.0)
	game.targets[0].position = next_position
	game.camera.look_at(next_position)
	check(not game._ray_hit().is_empty(), "AR ray follows current rendered target without physics-frame delay")
	game._open_pause()
	var previous_id:String = game.session_id
	game._choose_roster_weapon(3)
	game._resume_pause()
	var next_id:String = game.session_id
	game._resume_pause()
	check(game.training_weapon == 3 and previous_id != next_id and game.session_id == next_id, "paused selection switches once despite repeated resume")
	check(game.burst_remaining == 0 and not Input.is_action_pressed("shoot") and game.mouse_blocked, "switch clears held shooting and burst state")
	check(game.targets.size() == 1 and not game.training_measurement, "grid starts with one target and free-practice only")
	check(game.data.profiles.size() == 3 and game.slot_buttons.size() == 3, "new modes retain exactly three profile and soldier slots")
	game.mode = game.Mode.TRAINING
	game.training_elapsed = 0.2
	game._finish_training(false)
	await process_frame
	begin(4)
	check(game.targets.size() == 5 and not game.training_measurement, "grenade starts five targets and free-practice only")
	game.stats.shots = 1
	var center:Vector3 = game.targets[0].global_position
	game._explode({"id":0}, {"position":center,"direct_index":0})
	var kills := int(game.stats.kills)
	check(kills >= 2 and int(game.stats.hits) == 1 and int(game.stats.shots) == 1, "one grenade keeps one shot/hit and counts multiple kills")
	game._explode({"id":0}, {"position":center,"direct_index":0})
	check(int(game.stats.kills) == kills and int(game.stats.hits) == 1, "same blast does not damage dead targets twice")
	check(float(game._training_result().exact_points) <= 9.000001, "grenade credit cap stays at nine per credited shot")
	var effects_before:int = game.blast_effects.size()
	var events_before:int = game.grenade_events.size()
	var credit_before:float = game._training_result().exact_points
	var progress_before:int = Progression.total(game.data)
	game.camera.look_at(game.camera.global_position + Vector3(0,10,-0.01))
	game.fire_cooldown = 0.0
	game.mouse_blocked = false
	game._fire_shot()
	game._process_weapon(4.1)
	check(game.projectiles.is_empty() and game.projectile_nodes.is_empty() and game.blast_effects.size() == effects_before, "expired airborne grenade is removed without explosion effect")
	check(int(game.stats.kills) == kills and int(game.stats.hits) == 1 and is_equal_approx(float(game._training_result().exact_points),credit_before) and Progression.total(game.data) == progress_before, "expired airborne grenade gives no damage, hit, reward, or progression")
	check(game.grenade_events.size() == events_before + 1 and bool(game.grenade_events[-1].get("expired",false)) and int(game.grenade_events[-1].killed) == 0, "airborne expiry records exactly one miss event")
	# 通知キューはFPSを停止せず、停止中は時間を消費しない。
	var view:ProgressionView = game.progression_view
	view.set_process(false)
	view.set_context(true,false,true)
	var captured_mouse:int = Input.mouse_mode
	view.set_notifications_active(false)
	view.enqueue_notification({"id":"review-first","title":"最初","description":"テスト"})
	view.enqueue_notification({"id":"review-second","title":"次","description":"テスト"})
	var stopped_time:float = view._notification_time
	view._process(10.0)
	check(view._notification_time == stopped_time and view._active_notification.id == "review-first" and view._notification_queue.size() == 1, "paused achievement queue retains one active notification and time")
	view.set_notifications_active(true)
	view._process(0.31)
	view._process(3.1)
	view._process(0.19)
	check(view._active_notification.id == "review-second" and view._notification_queue.is_empty(), "achievement notifications advance one at a time")
	check(Input.mouse_mode == captured_mouse and view._roster_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "read-only FPS roster and banners preserve mouse capture")
	game.queue_free()
	await process_frame
	print("REVIEW_021_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
