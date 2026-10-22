extends SceneTree

var failures:Array[String]=[]
func _init()->void:call_deferred("_run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _run()->void:
	# 固定した改修前コミットの実装をメモリ上だけで実行する。作業ツリーを変更しない。
	var output:Array=[]
	if OS.execute("git",["archive","--format=zip","--output="+ProjectSettings.globalize_path("user://baseline.zip"),"v1.8.0","main.gd"],output)!=0:push_error("baseline unavailable");quit(1);return
	var archive:=ZIPReader.new();archive.open("user://baseline.zip")
	var source:=GDScript.new();source.source_code=archive.read_file("main.gd").get_string_from_utf8();archive.close()
	if source.reload()!=OK:push_error("baseline compile failed");quit(1);return
	var old:=Node.new();old.set_script(source);old.is_test_mode=true;root.add_child(old)
	var current=load("res://main.tscn").instantiate();current.is_test_mode=true;root.add_child(current)
	for game in [old,current]:
		game.set_process(false);game.set_physics_process(false);game.data.settings.shot_sound=3;game.data.settings.hit_sound=3;game.data.unlocked=[true,true,true]
	var expected:Array=[]
	# 同時に3D世界へ重ねないため、片方の標的を消してから次の実装を走らせる。
	for game in [old,current]:
		for weapon in 3:
			game.selected_weapon=weapon;seed(1600+weapon);game._start_training();game._process(3.1)
			for index in 15:
				game.training_elapsed+=0.3
				game.camera.look_at(game.targets[0].global_position)
				if index%5==4:game.camera.rotation.y+=1.2
				await physics_frame;await physics_frame
				seed(16000+index)
				if weapon==1:
					Input.action_press("shoot");game.mouse_blocked=false
					game._process_weapon(0.3);Input.action_release("shoot")
				else:game._fire_shot()
			var actual:Dictionary={"stats":game.stats.duplicate(true),"points":game._training_result(),"q_sum":game.shooting_metrics.q_sum,"q_time":game.shooting_metrics.q_time}
			if game==old:expected.append(actual)
			else:check(actual==expected[weapon],"weapon %d facts/points differ from v1.8.0"%weapon)
			game._finish_training(false)
		game._clear_targets();await process_frame;await physics_frame
	old.queue_free();current.queue_free();for frame in 4:await process_frame
	if failures.is_empty():print("SCORING_REGRESSION_OK: v1.8.0 and current actual ray replay, 3 weapons, raw metrics, misses, center/kill/streak bonuses and carry identical");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
