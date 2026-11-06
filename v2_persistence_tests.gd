extends SceneTree

# 配布PCKの通常保存経路を別プロセス間で確認する。入力と時計は自動駆動。
var game
var failed := false

func _initialize()->void:
	call_deferred("_run")

func check(value:bool, message:String)->void:
	if not value:
		failed = true
		push_error(message)

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1" or not OS.get_user_data_dir().contains("slt2-native-pack"):
		push_error("isolated native APPDATA required")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	check(not game.is_test_mode, "native test must use production save path")
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.app_focused = true
	if game.updater:
		game.updater.queue_free()
		game.updater = null
	if OS.get_environment("SLT_NATIVE_PHASE") == "reload":
		for weapon in 3:
			check(int(game.data.measurement_counts[weapon]) == 1, "native restart lost completions")
		check(game.data.training_history.size() == 5, "native restart lost five-mode history")
		check(Progression.total(game.data) >= 1503 and Progression.unlocked(game.data,4), "restart lost progression or five-mode unlock")
		check(int(game.data.training_history[0].weapon) == 4 and not game.data.training_history[0].extra.grenade_events.is_empty(), "restart lost grenade impact facts")
		for weapon in 3:
			check(not game.data.profiles[weapon].is_empty(), "native restart lost adoption")
		check(game.data.credits != "0" and game.data.lifetime_credits != "0", "native restart lost earned credits")
		game._show_army()
		check(game.combat.snapshot().allies.size() >= 1, "native restart lost deployment")
		print("V2_PERSISTENCE_RELOAD: counts=", game.data.measurement_counts, " credits=", game.data.credits)
	else:
		check(game.data.measurement_counts == [0, 0, 0], "native test needs fresh isolated save")
		# 既存三武器が利用済みの隔離fixture。新規解放は0.21専用テストで確認。
		game.data.progression.preserved_weapons = [0, 1, 2]
		for weapon in 3:
			game._show_prep()
			game.selected_measurement = true
			game.selected_weapon = weapon
			game._request_start()
			for tick in 31:
				game._process(0.1)
				if game.mode == game.Mode.TRAINING:
					break
			check(game.mode == game.Mode.TRAINING, "native countdown failed")
			game.camera.look_at(game.targets[0].global_position)
			await physics_frame
			game.mouse_blocked = false
			game._accept_measurement_shoot(true, 0.1)
			game._accept_measurement_shoot(false, 0.2)
			for tick in 601:
				if game.mode != game.Mode.TRAINING:
					break
				game._process(0.1)
			check(game.mode == game.Mode.RESULT and game.data.measurement_counts[weapon] == 1, "native 60s completion failed")
			game._adopt_result()
			check(not game.data.profiles[weapon].is_empty(), "native adoption failed")
		# 新二種目は隔離fixtureで解放し、本番保存経路へ実射撃事実を保存する。
		Progression.apply_record(game.data, {"weapon":0,"progress_kills":1500})
		for weapon in [3,4]:
			game._show_prep()
			game.selected_measurement = false
			game.selected_weapon = weapon
			game._request_start()
			for tick in 31:
				game._process(0.1)
				if game.mode == game.Mode.TRAINING:break
			game.mouse_blocked = false
			game.training_elapsed = 0.2
			game.camera.look_at(game.targets[0].global_position if weapon == 3 else Vector3(-1.6,game.camera.global_position.y,-8.0))
			await physics_frame
			game._fire_shot()
			for tick in 35:game._process(0.05)
			game._finish_training(false)
			check(game.adopt_button.disabled, "extra mode offered profile")
		game._show_army()
		check(game.combat.snapshot().allies.size() >= 1, "native deployment absent")
		check(game._save_current(), "native final save failed")
		print("V2_PERSISTENCE_CREATE: counts=", game.data.measurement_counts, " credits=", game.data.credits)
	game.queue_free()
	await process_frame
	print("V2_PERSISTENCE_OK" if not failed else "V2_PERSISTENCE_FAILED")
	quit(1 if failed else 0)
