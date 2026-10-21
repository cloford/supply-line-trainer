extends SceneTree

var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:call_deferred("_run")
func _run()->void:
	var game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.data.settings.shot_sound=3;game.data.settings.hit_sound=3;game.data.unlocked=[true,true,true]
	for weapon in 3:
		game.selected_weapon=weapon;game._start_training();game.mode=game.Mode.TRAINING;game.mouse_blocked=false
		await physics_frame;await physics_frame
		game.camera.look_at(game.targets[0].global_position);game._update_targets(0)
		await physics_frame
		check(not game._ray_hit().is_empty(),"physics ray did not hit weapon %d"%weapon)
		if weapon==1:
			Input.action_press("shoot")
			for frame in 120:game._process_weapon(1.0/120)
			Input.action_release("shoot")
		else:game._fire_shot()
		var result:Dictionary=game._training_result()
		check(result.score>0 and result.score==result.supply,"weapon %d did not earn points"%weapon)
		game.training_elapsed=2;game.active_seconds=1
		var start:String=game.data.credits
		game._checkpoint_training();game._finish_training(false);game._finish_training(false)
		check(str(game.data.credits)==BigUInt.add(start,str(result.score)),"weapon %d duplicate settlement"%weapon)
	game.queue_free()
	for frame in 5:await process_frame
	if failures.is_empty():print("TRAINING_TEST_OK: three physical shooting rays, actual scoring and single settlement");quit(0)
	else:
		for failure in failures:push_error(failure)
		quit(1)
