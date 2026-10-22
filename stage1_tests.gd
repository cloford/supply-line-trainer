extends SceneTree
var game
var failures:Array[String]=[]
var output:String
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:call_deferred("_run")
func snap(name:String)->void:
	await process_frame;await process_frame
	var bounds:=Rect2(Vector2.ZERO,Vector2(root.size))
	if game.hud.visible:
		check(game.crosshair.get_global_rect().get_center().is_equal_approx(game.get_viewport().get_visible_rect().get_center()),"aim not at 3D viewport center")
		if game.exit_ring.visible:check(bounds.encloses(game.exit_ring.get_global_rect()) and bounds.encloses(game.exit_hint.get_global_rect()),"hold affordance clipped")
	for panel in [game.navigation,game.result_card,game.pause_card,game.info_card]:
		if panel.is_visible_in_tree():check(bounds.encloses(panel.get_global_rect()),"panel clipped "+name)
	for button in game.ui.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not game.info_panel.visible and not game.settings_page.is_visible_in_tree():check(bounds.encloses(button.get_global_rect()),"button clipped "+name+" "+button.text)
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();check(image.get_size()==root.size,"rendered client dimensions differ");image.save_png(output.path_join(name+".png"))
func _run()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":quit(1);return
	output=OS.get_environment("SLT_CAPTURE_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720);root.content_scale_size=root.size
	game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.settings.shot_sound=3;game.data.settings.hit_sound=3
	await snap("01-new-preparation")
	check(game.intro_card.visible,"new data did not get optional guide")
	game.data.unlocked=[false,false,false];var legacy_flags:Array=game.data.unlocked.duplicate()
	for weapon in 3:
		game._show_prep();game._select_weapon(weapon);game._request_start();var id:String=game.session_id;game._request_start()
		check(game.training_weapon==weapon and game.session_id==id,"all training or duplicate start guard failed")
		check(not game.navigation.visible and game.battle_hud==null and game.battle_progress==null and not game.goal_hud.visible,"HUD army information remains")
		game._process(3.1);check(game.mode==game.Mode.TRAINING,"countdown did not enter training")
		game.training_elapsed=12;game.stats.base_points=100;game.stats.shots=10
		game._finish_training(false)
	check(game.data.unlocked==legacy_flags,"legacy unlock data was erased")
	game._open_result_details();var credits:String=game.data.credits;game._close_info();game._finish_training(false)
	check(game.data.credits==credits,"details caused another settlement")
	game._retry_training();var retry_id:String=game.session_id;game._retry_training();check(game.session_id==retry_id,"double retry started twice")
	check(game.stats.shots==0 and game.hit_label.text.is_empty() and game.goal_notice_timer==0,"retry kept score/notice")
	var hp:float=game.data.enemy_hp;game._process(3.1);game._process(0.25);check(game.data.enemy_hp!=hp,"HUD removal stopped battle")
	game._on_focus_lost();var elapsed:float=game.training_elapsed;game._process(2);check(game.training_elapsed==elapsed and game.mouse_blocked,"focus pause did not freeze/block")
	game.app_focused=true;game._resume_pause();game._show_prep()
	for index in 3:
		game._navigate(index);var original_mode:int=game.mode;var esc:=InputEventKey.new();esc.physical_keycode=KEY_ESCAPE;esc.pressed=true;game._unhandled_input(esc);check(game.mode==original_mode,"Esc navigated outside training");game._open_settings_from_screen();game.sensitivity_edit.text="2.5";game._settings_changed();game._settings_back()
		check(game.discard_confirm.visible and game.mode==game.Mode.PAUSED,"dirty settings did not require discard")
		game._confirm_discard();check(game.mode==original_mode and game.navigation.visible,"settings returned to wrong screen")
	game._show_prep();game.is_test_mode=false;game._select_weapon(2);game._select_difficulty(1);game._dismiss_intro();game.is_test_mode=true
	var loaded:=SaveManager.load_data();check(loaded.selected_weapon==2 and loaded.selected_difficulty==1 and loaded.help_seen,"selection/guide not saved")
	check(loaded.unlocked==legacy_flags and loaded.training_history.size()==game.data.training_history.size(),"preferences altered existing history")
	game._show_prep();game._request_start();game._process(3.1);game.training_elapsed=11;game.stats.base_points=400;game.stats.shots=11;game._finish_training(false)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=dimensions;root.content_scale_size=dimensions
		check(root.size==dimensions,"requested resolution was clamped")
		await snap("result-%dx%d"%[dimensions.x,dimensions.y]);game._open_result_details();await snap("details-%dx%d"%[dimensions.x,dimensions.y]);game._close_info()
		game._show_prep();await snap("preparation-%dx%d"%[dimensions.x,dimensions.y]);game._show_army();await snap("army-%dx%d"%[dimensions.x,dimensions.y]);game._show_records();await snap("records-%dx%d"%[dimensions.x,dimensions.y])
		game._show_prep();game._open_help();await snap("help-%dx%d"%[dimensions.x,dimensions.y]);game._close_info()
		game._request_start();await snap("countdown-%dx%d"%[dimensions.x,dimensions.y]);game._process(3.1);await snap("hud-%dx%d"%[dimensions.x,dimensions.y]);game._open_pause();await snap("pause-%dx%d"%[dimensions.x,dimensions.y]);game._open_settings_page();game._select_settings_tab(1);await snap("settings-%dx%d"%[dimensions.x,dimensions.y]);game._cancel_settings_changes();game._settings_back();game._resume_pause();game.training_elapsed=12;game._finish_training(false)
	game._retry_training();game._process(3.1);var hold:=InputEventMouseButton.new();hold.button_index=MOUSE_BUTTON_RIGHT;hold.pressed=true;game._unhandled_input(hold);game._process(0.4);await snap("hold-exit");hold.pressed=false;game._unhandled_input(hold);game._open_pause();game._end_early()
	game._show_prep();game._update_status("更新の通信に失敗しました");check(not game.start_button.disabled,"update failure blocked training")
	game.data.migration_failed=true;game._refresh_prep();game._request_start();check(game.mode==game.Mode.PREP and game.start_button.disabled and game.condition_label.visible,"save failure protection was hidden or bypassed");game.data.erase("migration_failed");game._refresh_prep()
	root.size=Vector2i(1280,720);root.content_scale_size=root.size;game.data.settings.score_details=true;game._show_records();await snap("records-detail-setting")
	game._show_prep();game._request_start();game._process(3.1);game.training_elapsed=12;game._finish_training(false)
	game.result_points.text="今回の獲得 9223372036854775807 P";game.result_wallet.text="所持ポイント 123456789012345678901234567890 P";await snap("boundary-large-points")
	# 通知無効でも達成済み状態を保存し、再表示や設定変更で通知を再発火しない。
	game._show_prep();var old_data:Dictionary=game.data;game.data=SaveManager.defaults();game.selected_weapon=0;game._start_training();game._process(3.1)
	game.data.settings.goal_notifications=false;game.stats.base_points=1000.0;game._refresh_goal_hud()
	check(game.data.upgrade_goal.notified and not game.goal_notification.visible,"disabled goal notice lost funding state")
	check(SaveManager.save_data(game.data),"goal state save failed");var notice_data:=SaveManager.load_data();check(notice_data.upgrade_goal.notified,"notice state not restored")
	game.data.settings.goal_notifications=true;game._refresh_goal_hud();check(game.goal_notice_timer==0,"enabling notices repeated consumed goal")
	game.data=old_data
	game.queue_free();for frame in 5:await process_frame
	notice_data.selected_weapon=2;notice_data.selected_difficulty=1;check(SaveManager.save_data(notice_data),"restart fixture save failed")
	var restarted=load("res://main.tscn").instantiate();root.add_child(restarted);restarted.set_process(false);restarted.set_physics_process(false)
	check(restarted.selected_weapon==2 and restarted.selected_difficulty==1 and restarted.mode==restarted.Mode.PREP and restarted.targets.is_empty(),"startup did not restore selection safely")
	restarted.queue_free();for frame in 5:await process_frame
	if failures.is_empty():print("STAGE1_OK: unlocks, selection save, guide, navigation/settings return, HUD battle, duplicate guards, settlement and layouts");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
