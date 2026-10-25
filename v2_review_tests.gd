extends SceneTree

func _init()->void:
	call_deferred("_run")

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		quit(2)
		return
	var d := V2Diorama.new()
	root.add_child(d)
	await process_frame
	d.set_active(false)
	var source := {"weapon":0, "armor":false}
	for index in 13:
		var target := {"target-%d" % index:{"position":[0.0,1.6,-11.0],"radius":0.42}}
		d.show_replay(source,index*0.2,target,{})
	var visible := 0
	for model in d._replay_targets.values():
		visible += 1 if model.visible else 0
	print("REVIEW_REPLAY_TARGETS cached=",d._replay_targets.size()," visible_after_13=",visible)
	for section in 20:
		d.show_state({"time":float(section),"status":"fighting","allies":[],"enemies":[{"id":"enemy-%d-0"%section,"kind":"light","alive":true}]})
	print("REVIEW_COMBAT_MODEL_CACHE cached_after_20_sections=",d._models.size())
	d.queue_free()
	await process_frame
	var game = load("res://main.tscn").instantiate()
	game.is_test_mode = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.data.armor[0] = true
	game.candidate_record = {"weapon":0,"shots":[{"time":0.0}],"events":[],"poses":[]}
	game.mode = game.Mode.RESULT
	game._restart_replay()
	print("REVIEW_ARMOR before_replay=",game.replay_diorama._replay_model.armor_enabled)
	game._process_result_preview(0.1)
	print("REVIEW_ARMOR after_replay=",game.replay_diorama._replay_model.armor_enabled)
	game.data.settings.effects_enabled = false
	game._show_army()
	game.combat.configure(game.data,75)
	game.diorama.show_state(game.combat.snapshot())
	game._process_battle(0.1)
	print("REVIEW_EFFECT_SUPPRESSION disabled_setting_effect_count=",game.diorama._effects.size())
	game._show_prep()
	game.selected_measurement = true
	game.selected_weapon = 1
	game._start_training()
	print("REVIEW_MEASUREMENT_COUNTDOWN target_visible=",game.targets[0].is_visible_in_tree()," mode=",game.mode)
	game.mode = game.Mode.TRAINING
	game.mouse_blocked = false
	game.training_elapsed = 0.0
	await physics_frame
	await physics_frame
	var position:Vector3 = game._auto_position(0.4*float(V2Rules.MEASUREMENT_CONDITIONS.speed))
	game.camera.look_at(position)
	game._measurement_advance_time(0.4)
	print("REVIEW_AR_RAY_AFTER_MOVE hit=",game._ray_hit()," actual_target=",game.targets[0].global_position," aimed_position=",position)
	await physics_frame
	await physics_frame
	print("REVIEW_AR_RAY_AFTER_PHYSICS hit=",game._ray_hit())
	game._finish_training(false)
	game._show_prep()
	game.selected_measurement = true
	game.selected_weapon = 1
	game._start_training()
	game.mode = game.Mode.TRAINING
	game.mouse_blocked = false
	game._accept_measurement_shoot(true,0.002)
	game._accept_measurement_shoot(false,0.006)
	game._process(1.0/30.0)
	print("REVIEW_AR_SAME_FRAME_TAP shots=",game.measurement.record.shot_count)
	game._finish_training(false)
	game._show_prep()
	game.selected_measurement = true
	game.selected_weapon = 1
	game._start_training()
	game.mode = game.Mode.TRAINING
	game.mouse_blocked = false
	game._accept_measurement_shoot(true,0.002)
	game._process(1.0/120.0)
	game._accept_measurement_shoot(false,0.006)
	game._process(3.0/120.0)
	print("REVIEW_AR_CROSS_FRAME_TAP shots=",game.measurement.record.shot_count)
	game._finish_training(false)
	game._show_prep()
	game.selected_measurement = true
	game.selected_weapon = 0
	game._start_training()
	game.mode = game.Mode.TRAINING
	game.mouse_blocked = false
	game.training_elapsed = 0.1
	game.camera.look_at(game.targets[0].global_position)
	await physics_frame
	await physics_frame
	var old_target:Vector3 = game.targets[0].global_position
	game._fire_shot()
	var new_target:Vector3 = game.targets[0].global_position
	game._fire_shot()
	print("REVIEW_HG_IMMEDIATE_SECOND hits=",game.measurement.record.hit_count," q2=",game.measurement.record.shots[-1].q," relocation_distance=",old_target.distance_to(new_target))
	var collector := V2Measurement.new()
	collector.begin(0,{},1,"review-trial")
	for second in 60:
		collector.shot(float(second),true,1.0,"x",Vector3.ZERO,Vector3.FORWARD,Vector3.FORWARD)
	game.candidate_record = collector.completed(60.0)
	game.data.profiles[0] = {}
	game.data.settings.effects_enabled = true
	game.mode = game.Mode.RESULT
	game.info_panel.hide()
	game.replay_diorama._clear_effects()
	game._start_trial()
	game._process_result_preview(0.1)
	var phase0_effects:int = game.replay_diorama._effects.size()
	game.trial_phase = 1
	game._begin_trial_phase()
	game._process_result_preview(0.1)
	print("REVIEW_TRIAL_PHASE_COLLISION current_phase_effects=",phase0_effects," after_candidate_phase_effects=",game.replay_diorama._effects.size()," candidate_shots=",game.trial.state.allies[0].shots)
	game.queue_free()
	await process_frame
	quit(0)
