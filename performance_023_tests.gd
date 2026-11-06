extends SceneTree

# 同じ外部計測コードを公開0.22 PCK / 現ソースへ適用する。ユーザー保存は開かない。
var game

func _initialize()->void:
	call_deferred("run")

func run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1" or not OS.get_user_data_dir().contains(".test-appdata"):
		quit(2)
		return
	var probe := load(get_script().resource_path.get_base_dir().path_join("profile_game_023.gd"))
	game = load("res://main.tscn").instantiate()
	game.set_script(probe)
	game.is_test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	if game.updater:
		game.updater.queue_free()
		game.updater = null
	var valid_measurements := OS.get_environment("SLT_PROFILE_VALID") == "1"
	for history_size in ([100] if valid_measurements else [0,100]):
		game.is_test_mode = true
		game.data = V2Save.defaults()
		game._show_prep()
		game.selected_weapon = 0
		game._start_training()
		game.mode = game.Mode.TRAINING
		game.training_elapsed = 0.2
		game.mouse_blocked = false
		# 60秒測定相当の重い履歴100件。個人保存に由来しないfixture。
		var entry:Dictionary = game._session_record()
		entry["fixture_samples"] = []
		for sample in 600:
			entry.fixture_samples.append({"time":sample * 0.1,"position":[1.0,2.0,3.0],"rotation":[0.1,0.2,0.3]})
		for index in history_size:
			var row := entry.duplicate(true)
			row.id = "history-%d" % index
			if valid_measurements:
				row.erase("fixture_samples")
				var collector := V2Measurement.new()
				collector.begin(index % 3,game.data.settings,index,row.id)
				for sample in 600:
					collector.shot(sample * 0.1,sample % 3 != 0,0.8,"target",Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-11))
					collector.pose(sample * 0.1,Vector3.ZERO,Vector3.ZERO)
					collector.target_event(sample * 0.1,"spawn","target",{"position":Vector3(1,2,-11)})
				row.weapon = index % 3
				row.duration = 60
				row.elapsed = 60.0
				row.measurement = collector.completed(60.0)
				assert(bool(row.measurement.valid))
				if index < 6:
					var profile := {"record":row.measurement.duplicate(true),"profile":V2Profiles.from_record(row.measurement)}
					game.data["profiles" if index < 3 else "previous_profiles"][index % 3] = profile
			game.data.training_history.append(row)
		game.is_test_mode = false
		assert(V2Save.save_data(game.data))
		print("PROFILE023_FIXTURE ",JSON.stringify({"history":history_size,"kind":"valid_measurement" if valid_measurements else "synthetic_payload","profiles":6 if valid_measurements else 0}))
		if game.get("save_worker") != null:
			var cache_started := Time.get_ticks_usec()
			game.save_worker.configure(game.data)
			print("PROFILE023_CACHE ",JSON.stringify({"history":history_size,"cache_setup_us":Time.get_ticks_usec()-cache_started}))
		var events := ["miss","kill1","ordinary_hit"] if valid_measurements else ["miss","kill1","kill2","kill3","kill4","kill5","kill6","kill7","kill8","kill9","kill10","ordinary_hit"]
		for event in events:
			game.fire_cooldown = 0.0
			game.hit_sound_cooldown = 0.0
			game.camera.look_at(game.targets[0].global_position)
			if event == "miss":game.camera.rotation.y += 1.5
			if event == "ordinary_hit":
				game.training_weapon = 2
				game.target_progress[0] = 0
			await physics_frame
			game.timings.clear()
			game.profile_enabled = true
			var started := Time.get_ticks_usec()
			game._fire_shot()
			game._process(0.016)
			game.timings["event_frame_us"] = Time.get_ticks_usec() - started
			game.profile_enabled = false
			if game.get("save_worker") != null:
				game.timings["snapshot_us"] = game.save_worker.last_snapshot_us
			print("PROFILE023 ",JSON.stringify({"history":history_size,"event":event,"us":game.timings.duplicate(),"mode":game.mode,"paused":paused,"time_scale":Engine.time_scale,"focus":game.app_focused,"mouse":Input.mouse_mode,"total":Progression.total(game.data)}))
			var next_started := Time.get_ticks_usec()
			await process_frame
			var next_wait := Time.get_ticks_usec() - next_started
			game.timings.clear()
			game.profile_enabled = true
			game._process(0.016)
			game.profile_enabled = false
			print("PROFILE023_NEXT ",JSON.stringify({"history":history_size,"event":event,"frame_wait_us":next_wait,"us":game.timings.duplicate()}))
		if game.get("save_worker") != null:
			game.save_worker.finish()
			print("PROFILE023_WORKER ",JSON.stringify({"history":history_size,"last_worker_us":game.save_worker.last_write_us,"writes":game.save_worker.writes,"requests":game.save_worker.requests}))
		var json_started := Time.get_ticks_usec()
		var payload := JSON.stringify(V2Measurement.json_value(game.data))
		print("PROFILE023_JSON ",JSON.stringify({"history":history_size,"json_us":Time.get_ticks_usec()-json_started,"characters":payload.length()}))
		var started := Time.get_ticks_usec()
		V2Save.save_data(game.data)
		print("PROFILE023_SAVE ",JSON.stringify({"history":history_size,"full_save_us":Time.get_ticks_usec()-started}))
	game.queue_free()
	await process_frame
	quit()
