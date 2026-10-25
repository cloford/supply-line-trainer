extends SceneTree

func _initialize()->void:
	call_deferred("_run")

func measure(game, army:bool)->Dictionary:
	if army:
		game._show_army()
	else:
		game._show_prep()
		game.selected_measurement = true
		game._start_training()
		for tick in 31:
			game._process(0.1)
			if game.mode == game.Mode.TRAINING:
				break
	for frame in 20:
		await process_frame
	var samples:Array[float] = []
	for frame in 90:
		var before := Time.get_ticks_usec()
		game._process(1.0 / 60.0)
		await process_frame
		samples.append(float(Time.get_ticks_usec() - before) / 1000.0)
	samples.sort()
	return {"median_ms":samples[45], "p95_ms":samples[85], "diorama_active":game.diorama.is_processing(), "viewport_mode":game.diorama.world_view.render_target_update_mode}

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	game.is_test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.lifetime_credits = "3000"
	game.combat.configure(game.data, 2)
	game.data.settings.shot_sound = 3
	game.data.settings.hit_sound = 3
	var training:Dictionary = await measure(game, false)
	game._open_pause()
	game._visit_army()
	var army:Dictionary = await measure(game, true)
	if training.diorama_active or int(training.viewport_mode) != SubViewport.UPDATE_DISABLED:
		push_error("hidden diorama still renders during measurement")
		quit(1)
		return
	print("V2_PERFORMANCE: training=", JSON.stringify(training), " army=", JSON.stringify(army), "; frame wait included, GPU/OS scheduling not input-latency measurement")
	game.queue_free()
	await process_frame
	quit(0)
