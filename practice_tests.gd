extends SceneTree

var failures:Array[String]=[]

func check(condition:bool,message:String)->void:
	if not condition:failures.append(message)

func _init()->void:call_deferred("_run")

func fixture(id:String,elapsed:float,credits:int)->Dictionary:
	return {"id":id,"started":"2026-10-21 12:00:00","weapon":0,"difficulty":0,"duration":0,"elapsed":elapsed,"active":elapsed*0.5,"score":credits*10,"credits":credits,"scoring_version":3}

func _run()->void:
	# The sphere surface is always one radius away: test the actual ray-distance fix.
	check(is_equal_approx(Balance.center_precision(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-10),1),1.0),"center ray not full precision")
	check(Balance.center_precision(Vector3.ZERO,Vector3.FORWARD,Vector3(0.9,0,-10),1)<0.04,"edge ray too precise")
	check(is_equal_approx(Balance.center_precision(Vector3.ZERO,Vector3.FORWARD,Vector3(0.45,0,-10),0.5),Balance.center_precision(Vector3.ZERO,Vector3.FORWARD,Vector3(0.9,0,-10),1)),"precision depends on target radius")
	for weapon in 3:
		var blank:Dictionary={}
		check(Balance.score_and_reward(weapon,0,blank,0,0,36000).supply==0,"idle gained credits")
		var edge:Dictionary={"base_points":1000.0,"center_bonus":0.0}
		var center:Dictionary={"base_points":1000.0,"center_bonus":1000.0}
		var a:=Balance.score_and_reward(weapon,0,edge,0,60,60)
		var b:=Balance.score_and_reward(weapon,0,center,0,60,60)
		check(b.score==a.score*2 and b.supply>a.supply*1.9,"center reward difference insufficient")
		check(Balance.score_and_reward(weapon,0,center,0,0,3600).supply==b.supply,"elapsed mode changed earnings")
		check(Balance.score_and_reward(weapon,0,{"base_points":1000,"center_bonus":90000,"speed_bonus":10000,"streak_bonus":10000},0,60,60).score==2200,"bonus exceeded cap")
	var data:=SaveManager.defaults()
	TrainingLedger.checkpoint(data,fixture("session",15,30))
	TrainingLedger.checkpoint(data,fixture("session",15,30))
	check(data.credits=="30" and data.practice_totals.sessions==1 and data.practice_totals.elapsed==15.0,"checkpoint duplicated")
	TrainingLedger.checkpoint(data,fixture("session",45,70))
	check(SaveManager.save_data(data),"checkpoint save failed")
	var restored:=SaveManager.load_data()
	check(TrainingLedger.recover(restored),"crash checkpoint not recovered")
	check(restored.credits=="70" and restored.practice_totals.elapsed==45.0 and restored.practice_totals.active==22.5 and restored.practice_totals.sessions==1,"recovery duplicated totals or credits")
	check(restored.training_history.size()==1 and restored.training_history[0].status=="中断復元","recovery history missing")
	check(not TrainingLedger.recover(restored),"second recovery re-applied")
	TrainingLedger.finish(restored,fixture("session",45,70),"終了")
	check(restored.credits=="70" and restored.training_history.size()==1,"repeated finish duplicated")
	TrainingLedger.finish(restored,fixture("zero",0,0),"終了")
	check(restored.practice_totals.sessions==1,"countdown exit counted as practice")
	for index in 205:TrainingLedger.finish(restored,fixture("history_%d"%index,1,1),"終了")
	check(restored.training_history.size()==200 and restored.practice_totals.sessions==206 and restored.practice_totals.elapsed==250.0,"history trimming lost cumulative totals")
	# Version 4 saves receive additive fields, without another growth reset.
	var old:=SaveManager.defaults();old.erase("training_schema");old.erase("bests_v3");old.erase("practice_totals");old.erase("training_history");old.erase("active_training")
	old.credits="1234";old.recruit=8;old.front=5;old.enemy_hp=100.0;old.unlocked=[true,true,false];old.bests_v2={"v2_0_0_60":500}
	var file:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);file.store_string(JSON.stringify(old));file=null
	var migrated:=SaveManager.load_data()
	check(migrated.credits=="1234" and migrated.recruit==8 and migrated.front==5 and migrated.bests_v2.v2_0_0_60==500 and migrated.bests_v3.is_empty(),"v4 progress or old records lost")
	check(FileAccess.file_exists("user://save_before_training_v3.json"),"v4 upgrade backup missing")
	check(Balance.eta_text(70,1.0,true)=="約1分10秒" and Balance.eta_text(70,1.0,false)=="停止中" and Balance.eta_text(70,0,true)=="計算中","ETA states wrong")
	var main=load("res://main.tscn").instantiate();main.is_test_mode=true;root.add_child(main)
	await process_frame;await process_frame
	main.set_process(false);main.set_physics_process(false)
	main.data.settings.shot_sound=3;main.data.settings.hit_sound=3
	main._select_duration(0);main._start_training();main.mode=main.Mode.TRAINING;main.mouse_blocked=false
	await physics_frame;await physics_frame
	main.camera.look_at(main.targets[0].global_position)
	var hit:Dictionary=main._ray_hit()
	check(not hit.is_empty() and float(hit.get("precision",0))>0.99,"physics ray center precision incorrect")
	main._fire_shot();main._update_hud()
	check(float(main.stats.center_bonus)>44.0 and int(main._training_result().supply)>0,"center hit not rewarded")
	main._process(3601.0)
	check(main.mode==main.Mode.TRAINING and main.training_elapsed>3600 and main.timer_label.text.contains("01:00:"),"unlimited stopped at time limit")
	var before_elapsed:float=main.training_elapsed;var before_active:float=main.active_seconds
	main._open_pause();main._process(10)
	check(main.training_elapsed==before_elapsed and main.active_seconds==before_active,"pause entered practice time")
	var expected:int=main._training_result().supply
	check(main.credit_hud.text.contains(str(expected)),"HUD estimate disagrees")
	main._end_early();var earned:=str(main.data.credits);main._finish_training(false)
	check(earned==str(main.data.credits) and main.data.practice_totals.sessions==1,"unlimited exit duplicated credits or session")
	check(main.data.bests_v3.is_empty() and main.result_detail.text.contains("練習記録"),"unlimited compared timed bests")
	main._show_records();await process_frame;await process_frame
	check(main.records_view.visible and main.records_view.rows.get_child_count()==1,"records screen missing")
	main.records_view.closed.emit();check(main.mode==main.Mode.PREP,"records back route wrong")
	main._select_duration(30);main._start_training();main.mode=main.Mode.TRAINING
	main.stats.base_points=1000.0;main.training_elapsed=29.95;main.time_left=0.05
	main._process(0.1)
	check(main.mode==main.Mode.RESULT and is_equal_approx(main.training_elapsed,30.0) and not main.data.bests_v3.is_empty(),"timed finish overshot or best not stored")
	main._show_army();main.data.enemy_hp=Balance.front_hp(int(main.data.front))*0.5;main._refresh_army_runtime()
	check(main.battle_view.defeated==2,"enemy count not tied to damage")
	var eta_before:String=main.eta_label.text
	main.data.recruit+=10;main._refresh_prep()
	check(main.eta_label.text!=eta_before,"ETA did not change after upgrade")
	main._advance_front();main._refresh_army_runtime()
	check(main.battle_view.march==0.0 and not main.battle_view.fallen.is_empty(),"breakthrough animation missing")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size=dimensions;main._show_records();await process_frame;await process_frame
		check(main.records_view.rows.get_global_rect().end.y<=root.size.y-60,"record list overflow")
	var tracking_scores:Array[int]=[]
	main.data.unlocked[1]=true;main.selected_weapon=1;main.selected_duration=60
	for frequency in [60,120]:
		main._start_training();main.mode=main.Mode.TRAINING;main.mouse_blocked=false
		Input.action_press("shoot")
		for _frame in frequency:
			main._update_targets(1.0/frequency)
			await physics_frame
			main.camera.look_at(main.targets[0].global_position)
			main._process_weapon(1.0/frequency)
		tracking_scores.append(int(main._training_result().score))
		Input.action_release("shoot");main.training_elapsed=1.0;main._finish_training(false)
	check(absi(tracking_scores[0]-tracking_scores[1])<=1 and tracking_scores[0]>=199,"tracking reward depends on update frequency")
	main.audio_player.stop();main.hit_audio_player.stop();main.queue_free()
	for _frame in 5:await process_frame
	if failures.is_empty():print("PRACTICE_TEST_OK: center physics, no idle earnings, checkpoint/recovery, migration, unlimited/timed, history, ETA and battle");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
