extends SceneTree

var failures:Array[String]=[]
func check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
func inside(inner:Rect2,outer:Rect2)->bool:
	return inner.position.x>=outer.position.x-1 and inner.position.y>=outer.position.y-1 and inner.end.x<=outer.end.x+1 and inner.end.y<=outer.end.y+1
func _init()->void:call_deferred("_run")

func _run()->void:
	var main=load("res://main.tscn").instantiate();main.is_test_mode=true;root.add_child(main);await process_frame;await process_frame
	var esc:=InputEventKey.new();esc.physical_keycode=KEY_ESCAPE;esc.pressed=true
	main._unhandled_input(esc);check(main.mode==main.Mode.PREP,"Esc changed prep screen")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size=dimensions;await process_frame;await process_frame
		main._show_army();await process_frame
		check(main.army_panel.find_children("*","ScrollContainer",true,false).is_empty(),"army screen contains scroll %s"%dimensions)
		main._unhandled_input(esc);check(main.mode==main.Mode.ARMY,"Esc changed army screen")
		main._show_prep();main._start_training();main._open_pause();await process_frame
		check(inside(main.pause_card.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dimensions))),"pause outside %s"%dimensions)
		main._close_pause();main._show_prep()
	main._select_duration(30);main._start_training();check(main.training_duration==30 and is_equal_approx(main.time_left,30.0),"duration mismatch")
	main.stats.base_points=999;main.streak=8;main._start_training();check(float(main.stats.base_points)==0 and main.streak==0,"retry not reset")
	main.mode=main.Mode.TRAINING;var time_before:float=main.time_left;var hp_before:float=float(main.data.enemy_hp);var target_before:Vector3=main.targets[0].position;main.stats.base_points=120.0
	main._unhandled_input(esc);check(main.mode==main.Mode.PAUSED,"Esc did not pause training");main._process(1.0);check(is_equal_approx(main.time_left,time_before) and is_equal_approx(float(main.data.enemy_hp),hp_before) and main.targets[0].position.is_equal_approx(target_before) and float(main.stats.base_points)==120.0,"pause advanced state")
	main._open_settings_page();main._unhandled_input(esc);check(main.mode==main.Mode.PAUSED and main.pause_menu.visible and not main.settings_page.visible,"Esc did not return settings to pause menu")
	main._unhandled_input(esc);check(main.mode==main.Mode.TRAINING,"Esc did not resume same training");check(main.mouse_blocked,"resume did not block held shot")
	main._show_prep();main._open_settings_from_screen();check(main.mode==main.Mode.PAUSED and main.settings_standalone and not main.pause_menu.visible,"standalone settings showed pause menu");main._settings_back();check(main.mode==main.Mode.PREP,"standalone settings did not return to prep")
	main._show_army();var credits_before:=str(main.data.credits);main._process_battle(5.0);check(str(main.data.credits)==credits_before,"passive battle credits remain");main.data.enemy_hp=0;main._advance_front();check(str(main.data.credits)==credits_before,"front reward credits remain")
	main.data.credits="10000";var item:Dictionary=Balance.COMMANDER_ITEMS[0];main._commander_item_pressed(item);var power:=Balance.combat_power(int(main.data.recruit),int(main.data.gear),main.data.commander_equipped);main._refresh_prep();main._refresh_prep();check(is_equal_approx(power,Balance.combat_power(int(main.data.recruit),int(main.data.gear),main.data.commander_equipped)),"equipment effect duplicated")
	main._show_prep();main._open_settings_from_screen();var applied_sens:float=float(main.data.settings.sensitivity);main.sensitivity_edit.text="2.345";main._settings_changed();check(main.settings_dirty,"settings not dirty");main._cancel_settings_changes();check(is_equal_approx(float(main.sensitivity_edit.text),applied_sens),"settings cancel mismatch")
	var score_before:Dictionary=main.stats.duplicate(true);var preview_credits:=str(main.data.credits)
	for sound_index in 4:
		main.shot_sound_option.select(sound_index);main.hit_sound_option.select(sound_index);main._preview_shot_sound();main._preview_hit_sound()
		if sound_index<3:check(main.audio_player.stream!=null and main.hit_audio_player.stream!=null,"sound preview missing %d"%sound_index)
	check(main.stats==score_before and str(main.data.credits)==preview_credits,"sound preview changed game state")
	main.shot_sound_option.select(2);main.hit_sound_option.select(2);main.hit_pitch_check.button_pressed=true;main._settings_changed();main._apply_settings_draft();check(bool(main.data.settings.hit_pitch_combo) and int(main.data.settings.shot_sound)==2 and main._hit_pitch(100)<=1.2,"sound settings or pitch cap mismatch")
	main._settings_back();main._start_training();check(is_equal_approx(main.hit_sound_cooldown,0.0),"new training did not reset sound pitch state")
	main.training_weapon=1;main.training_difficulty=1;main.target_phase=0;main._spawn_targets();var auto_start:Vector3=main.targets[0].position;main._update_targets(0.0);check(auto_start.is_equal_approx(main.targets[0].position),"auto target jumped")
	main.data.credits="0";main.data.bests_v2={};main.training_weapon=0;main.training_duration=60;main.training_elapsed=15.0;main.stats={"shots":10,"hits":8,"kills":8,"track_time":0.0,"fire_time":0.0,"base_points":360.0,"center_bonus":60.0,"speed_bonus":20.0,"streak_bonus":10.0};main.reward_committed=false;main._finish_training(false);var early:=str(main.data.credits);main._finish_training(false);check(BigUInt.compare(early,"0")>0 and str(main.data.credits)==early and main.data.bests_v2.is_empty(),"early reward mismatch")
	main._unhandled_input(esc);check(main.mode==main.Mode.RESULT,"Esc changed result screen")
	if failures.is_empty():
		print("UI_TEST_OK: Esc states, pause freeze, no passive credits, no army scroll, audio settings and previews")
		main.audio_player.stop();main.hit_audio_player.stop();main.audio_player.stream=null;main.hit_audio_player.stream=null;main.queue_free()
		for _frame in 5:await process_frame
		quit(0);return
	for failure in failures:push_error(failure)
	quit(1)
