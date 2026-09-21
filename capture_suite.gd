extends SceneTree

func _init()->void:
	call_deferred("_run")

func snap(path:String)->void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _run()->void:
	root.size=Vector2i(1280,720)
	var output:=ProjectSettings.globalize_path("res://captures")
	DirAccess.make_dir_recursive_absolute(output)
	var main=load("res://main.tscn").instantiate()
	main.is_test_mode=true
	root.add_child(main)
	await process_frame
	main._start_training(); main.countdown=0.0
	await process_frame
	await snap(output.path_join("crosshair.png"))
	main.crosshair.set_appearance("000000",10)
	await snap(output.path_join("crosshair_black.png"))
	main.crosshair.set_appearance("66e8ff",10)
	main._open_pause()
	main._open_settings_page()
	await snap(output.path_join("settings.png"))
	main._cancel_settings_changes()
	main._settings_back()
	main._pause_to_army()
	await snap(output.path_join("army_initial.png"))
	main.data.recruit=43; main.data.gear=5; main.data.depot=3; main.data.front=22; main.data.enemy_hp=Balance.front_hp(22); main.data.credits="1000000000000000000"; main._refresh_prep()
	await process_frame
	await snap(output.path_join("army_advanced.png"))
	print("CAPTURE_OK: ",output)
	quit(0)
