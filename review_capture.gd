extends SceneTree

var output:=""

func _init()->void:call_deferred("_run")

func snap(name:String)->void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func _run()->void:
	root.size=Vector2i(1280,720)
	output=ProjectSettings.globalize_path("res://captures/review")
	DirAccess.make_dir_recursive_absolute(output)
	var main=load("res://main.tscn").instantiate();main.is_test_mode=true;root.add_child(main)
	await process_frame;await process_frame
	main.data.settings.shot_sound=3;main.data.settings.hit_sound=3
	main._select_duration(0);main._refresh_prep()
	await snap("preparation")
	main._start_training();main.countdown=0.0
	await process_frame;await physics_frame
	main.camera.look_at(main.targets[0].global_position);main._fire_shot()
	main.training_elapsed=65.0;main.active_seconds=18.0;main._update_hud()
	await snap("unlimited")
	main._finish_training(false)
	await snap("result")
	for index in 9:
		TrainingLedger.finish(main.data,{"id":"capture_%d"%index,"started":"2026-10-21 13:%02d:00"%index,"weapon":index%3,"difficulty":index%3,"duration":0 if index%3==0 else 60,"elapsed":85.0+index,"active":24.0,"score":1340+index*20,"credits":100+index,"scoring_version":3},"終了")
	main._show_records()
	await snap("records")
	root.size=Vector2i(1024,768)
	await snap("records_1024")
	main._show_prep()
	await snap("preparation_1024")
	root.size=Vector2i(1280,720)
	main.data.recruit=8;main.data.gear=3;main._show_army()
	main.data.enemy_hp=Balance.front_hp(int(main.data.front))*0.45;main._refresh_army_runtime()
	await snap("army")
	main._advance_front();main._refresh_army_runtime()
	await create_timer(0.4).timeout
	await snap("advance")
	main.queue_free()
	for _frame in 5:await process_frame
	print("REVIEW_CAPTURE_OK: ",output)
	quit(0)
