extends SceneTree

var game
var failures:Array[String]=[]
var output:String
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func equivalent(a:Variant,b:Variant)->bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:return absf(float(a)-float(b))<=maxf(0.000000001,absf(float(a))*0.000000000001)
	if typeof(a)==TYPE_DICTIONARY and typeof(b)==TYPE_DICTIONARY:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]):return false
		return true
	if typeof(a)==TYPE_ARRAY and typeof(b)==TYPE_ARRAY:
		if a.size()!=b.size():return false
		for index in a.size():
			if not equivalent(a[index],b[index]):return false
		return true
	return a==b
func _init()->void:call_deferred("_run")
func snap(name:String)->void:
	await process_frame;await process_frame
	var bounds:=Rect2(Vector2.ZERO,Vector2(root.size))
	if game.mode==game.Mode.RESULT:
		check(bounds.encloses(game.result_card.get_global_rect()),"result clipped "+name)
		for control in game.result_card.find_children("*","Control",true,false):
			if control.is_visible_in_tree():check(bounds.encloses(control.get_global_rect()),"result child clipped "+str(control.name)+" "+name)
	if game.mode==game.Mode.RECORDS:
		for button in game.records_view.find_children("*","Button",true,false):
			if button.is_visible_in_tree():check(bounds.encloses(button.get_global_rect()),"record button clipped "+name)
	if game.mode==game.Mode.ARMY:
		for button in game.army_panel.find_children("*","Button",true,false):
			if button.is_visible_in_tree():check(bounds.encloses(button.get_global_rect()),"army button clipped "+name)
		if game.purchase_effect_view.visible:check(bounds.encloses(game.purchase_effect_view.get_global_rect()),"purchase comparison clipped "+name)
	if "--no-capture" not in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name+".png"))
func shoot_session()->void:
	game._process(3.1)
	for shot in 12:
		game._process(1.0)
		game.camera.look_at(game.targets[0].global_position)
		await physics_frame;await physics_frame
		game._fire_shot()
	game._finish_training(false)
func _run()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":push_error("isolated save required");quit(1);return
	root.size=Vector2i(1280,720);root.content_scale_size=root.size
	output=OS.get_environment("SLT_CAPTURE_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.data.settings.shot_sound=3;game.data.settings.hit_sound=3;game.data.unlocked=[true,true,true]
	game._start_training();await shoot_session()
	check(game.result_review.note_label.text=="今回の記録を次回から比較に使います","first comparison fabricated")
	await snap("01-first-result-1280x720")
	game._retry_training();check(game.shooting_metrics.intention=="指定なし","default retry required selection")
	await shoot_session()
	check(game.data.training_history[0].shooting_comparison.count==1,"second result missing previous baseline")
	await snap("02-compared-result-1280x720")
	var result_before:Dictionary=game._training_result()
	game.intention_option.select(1);game._retry_training()
	check(game.intention_label.visible and game.shooting_metrics.intention=="中心を意識","retry intention missing")
	check(game.training_weapon==0 and game.training_difficulty==0 and game.data.settings.fov==90,"intention changed shooting conditions")
	await snap("03-intention-countdown")
	await shoot_session()
	# ランダム配置と32bit 3D姿勢による中心照準の微小差を許容。端数繰越は比較しない。
	check(absf(float(game._training_result().exact_points)-float(result_before.exact_points))<0.02,"intention affected unrounded scoring for scripted center shots")
	var last:Dictionary=game.data.training_history[0].duplicate(true)
	game._army_from_goal();await snap("05-purchase-before");var previous_recruit:int=game.data.recruit;game._buy_upgrade(0)
	check(game.data.recruit==previous_recruit+1,"result to army purchase failed")
	check(game.purchase_effect_view.visible,"successful purchase comparison missing");await snap("06-purchase-after")
	game._show_prep();game._show_records()
	var row:Button=game.records_view.rows.get_child(0);row.pressed.emit()
	check(game.records_view.detail_view.visible and not game.records_view.listing.visible,"record selection failed")
	await snap("04-record-detail-1280x720")
	check(SaveManager.save_data(game.data),"metrics save failed")
	var loaded:=SaveManager.load_data()
	check(equivalent(loaded.training_history,game.data.training_history),"restart metrics changed")
	check(ShootingMetrics.presentation(loaded.training_history[0])==ShootingMetrics.presentation(last),"restart changed historical comparison")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;root.content_scale_size=dimensions
		game._show_prep();game.result_panel.show();game.prep_panel.hide();game.mode=game.Mode.RESULT
		game.result_review.set_review(ShootingMetrics.presentation(last));await snap("result-%dx%d"%[dimensions.x,dimensions.y])
		game.data.settings.score_details=true;game._finish_training(false)
		game._show_records();game.records_view.rows.get_child(0).pressed.emit();await snap("details-%dx%d"%[dimensions.x,dimensions.y])
		game.records_view.detail_back.pressed.emit();await snap("records-%dx%d"%[dimensions.x,dimensions.y])
		game._show_army();await snap("army-preview-%dx%d"%[dimensions.x,dimensions.y])
		game.last_purchase_effect=PurchaseEffect.preview(game.data,1,1);game.purchase_effect_timer=2.6;game._update_battle_view();await snap("army-effect-layout-%dx%d"%[dimensions.x,dimensions.y])
	# UI表示の境界値は隔離した複製へ注入し、実射撃の試遊結果とは区別する。
	root.size=Vector2i(1280,720);root.content_scale_size=root.size
	for variant in ["short","long","no-shots"]:
		var sample:=last.duplicate(true)
		if variant=="short":sample.metrics.elapsed=1.0;sample.metrics.shots=1;sample.metrics.hits=1;sample.metrics.kills=1;sample.metrics.q_sum=1
		elif variant=="no-shots":
			for key in ["shots","hits","kills","q_sum"]:sample.metrics[key]=0
		else:sample.metrics.elapsed=360000;sample.metrics.shots=1000000;sample.metrics.hits=999999;sample.metrics.kills=999999;sample.metrics.q_sum=999999
		game._show_prep();game.prep_panel.hide();game.result_panel.show();game.mode=game.Mode.RESULT;game.result_review.set_review(ShootingMetrics.presentation(sample));await snap("boundary-"+variant)
	game.data.settings.score_details=true
	game._start_training();await shoot_session();await snap("result-with-point-details")
	# 実レイと発射処理によるバースト途中停止・撃破加点の独立性。
	game.selected_weapon=2;game._start_training();game._process(3.1);game.mouse_blocked=false
	game.camera.look_at(game.targets[0].global_position);await physics_frame;await physics_frame
	game.burst_remaining=3;game.burst_timer=0;game._process_weapon(0.01);game._open_pause();game._process(1)
	check(game.stats.shots==1 and absf(game.shooting_metrics.q_sum-1.0)<0.0001 and game.burst_remaining==0,"cancelled burst counted scheduled bullets")
	game._resume_pause()
	game._fire_shot();game._fire_shot()
	check(game.stats.shots==3 and game.stats.kills==1 and absf(game.shooting_metrics.q_sum-3.0)<0.0003,"kill bonus duplicated q")
	var raw_before:Dictionary=game.shooting_metrics.duplicate(true);var elapsed_before:float=game.training_elapsed
	game._on_focus_lost();game._process(10)
	check(game.shooting_metrics==raw_before and game.training_elapsed==elapsed_before,"focus/pause advanced metrics")
	game.app_focused=true;game._resume_pause();game._open_pause();game._open_settings_page()
	game.fov_spin.value=95;game._apply_settings_draft();game._settings_back();game._resume_pause()
	check(game.shooting_metrics.settings_changed,"applied relevant change not excluded")
	game.data.settings.fov=90;game._apply_settings();check(game.shooting_metrics.settings_changed,"change back cleared exclusion")
	game._process(11);game._finish_training(false)
	check(game.data.training_history[0].metrics.comparison_reason.contains("設定"),"changed settings reason missing")
	game.queue_free();for frame in 4:await process_frame
	if failures.is_empty():print("METRICS_EXPERIENCE_OK: actual rays, retry intentions, comparison, army purchase, records, save reload, burst cancellation, pause/settings and client bounds");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
