extends SceneTree

var game
var output:String
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:call_deferred("_run")
func snap(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(image.get_width()==root.size.x and image.get_height()==root.size.y,"client size mismatch "+name)
	image.save_png(output.path_join(name+".png"))
func _run()->void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	output=OS.get_environment("SLT_CAPTURE_OUTPUT")
	if output.is_empty():output=ProjectSettings.globalize_path("res://captures/v15")
	DirAccess.make_dir_recursive_absolute(output)
	game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	await process_frame;await process_frame
	await snap("01-preparation")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(game.update_buttons[0].get_global_rect()),"prep update button clipped")
	game._start_training();game._process(3.1)
	for shot in 30:
		game.camera.look_at(game.targets[0].global_position)
		await physics_frame;await physics_frame
		game._fire_shot();game._process(0.2)
		if shot==1:await snap("02-goal-progress")
		if GrowthGoal.missing(game.data,game._goal_balance())=="0":break
	check(game.mode==game.Mode.TRAINING and game.goal_notice_timer>0,"goal funding interrupted training or notification absent")
	await snap("03-goal-funded")
	var balance:String=game._goal_balance();game._checkpoint_training()
	check(game._goal_balance()==balance,"checkpoint moved affordability")
	var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true
	game._unhandled_input(right);game._process(0.81)
	check(game.mode==game.Mode.RESULT and game.data.credits==balance,"hold settlement differed")
	await snap("04-result")
	game._army_from_goal();check(game.purchase_batch==1,"goal entry kept bulk purchase")
	await snap("05-before-recruit")
	game._buy_upgrade(0);check(game.data.recruit==1,"target purchase failed")
	await snap("06-recruit-000")
	await create_timer(0.35).timeout;await snap("07-recruit-350")
	check(not game.battle_view.recruit_joins.is_empty() and float(game.battle_view.recruit_joins[0].age)>0,"recruit animation did not advance")
	await create_timer(0.7).timeout;await snap("08-recruit-1050")
	check(game.battle_view.recruit_joins.is_empty(),"recruit animation did not complete")
	game._show_prep();await snap("09-next-goal")
	game.data.credits="100000";game.data.gear=1;GrowthGoal.ensure(game.data);game._show_army()
	await snap("10-before-gear")
	game._buy_upgrade(1);await snap("11-gear-000")
	await create_timer(0.3).timeout;await snap("12-gear-300")
	await create_timer(0.5).timeout;await snap("13-gear-800")
	check(game.battle_view.gear_update_age>=game.battle_view.GEAR_UPDATE_DURATION,"gear update did not complete")
	for level in [0,1,2,4,5,9]:
		game.data.gear=level;GrowthGoal.ensure(game.data);game._refresh_prep();await snap("gear-level-%d"%level)
	for level in [0,9,10,11,30,250,250000]:
		game.data.recruit=level;GrowthGoal.ensure(game.data);game._refresh_prep();await snap("troops-%d"%Balance.soldier_count(level))
		check(game.battle_view.visible_soldiers(Balance.soldier_count(level))<=48 and game.battle_view.background_soldiers(Balance.soldier_count(level))<=72,"unbounded drawing")
	game.data.recruit=10;game.data.gear=4;GrowthGoal.ensure(game.data);game._refresh_prep()
	game._buy_upgrade(0);await snap("cap-recruit-000")
	await create_timer(0.4).timeout;await snap("cap-recruit-400")
	await create_timer(0.7).timeout;await snap("cap-recruit-1100")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;root.content_scale_size=dimensions
		await process_frame;await process_frame
		game._show_prep();await snap("preparation-%dx%d"%[dimensions.x,dimensions.y])
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(game.update_buttons[0].get_global_rect()),"update controls outside client")
		game._show_army();await snap("army-%dx%d"%[dimensions.x,dimensions.y])
		var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
		check(bounds.encloses(game.upgrade_buttons[1].get_global_rect()),"purchase button outside client")
	game.queue_free();for frame in 4:await process_frame
	if failures.is_empty():print("GROWTH_EXPERIENCE_OK: actual shooting, goal funding, checkpoint, hold end, purchase, animation, next goal and render captures");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
