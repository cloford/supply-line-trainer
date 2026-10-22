extends SceneTree

var failures:Array[String]=[]
var game
var output:=""
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:call_deferred("_run")
func snap(name:String)->void:
	for frame in 3:await process_frame
	var bounds:=Rect2(Vector2.ZERO,Vector2(root.size))
	for button in game.ui.find_children("*","Button",true,false):
		if button.is_visible_in_tree():check(bounds.encloses(button.get_global_rect()),"button outside viewport: "+name+" / "+button.text)
	for control in [game.condition_card,game.pause_card,game.army_panel,game.purchase_effect_view]:
		if control.is_visible_in_tree():check(bounds.encloses(control.get_global_rect()),"panel clipped: "+name)
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name+".png"))
func freeze()->Dictionary:
	var positions:Array=[]
	for target in game.targets:positions.append(target.position)
	return {"id":game.session_id,"elapsed":game.training_elapsed,"active":game.active_seconds,"phase":game.target_phase,"stats":game.stats.duplicate(true),"metrics":game.shooting_metrics.duplicate(true),"positions":positions,"progress":game.target_progress.duplicate(),"spawns":game.target_spawn_times.duplicate(),"precisions":game.target_precisions.duplicate(),"player":game.player.transform,"camera":game.camera.transform,"streak":game.streak,"last_success":game.last_success_time,"auto_streak":game.auto_streak_time,"activity_window":game.activity_window,"cooldown":game.fire_cooldown}
func _run()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":quit(1);return
	output=OS.get_environment("SLT_CAPTURE_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720);root.content_scale_size=root.size
	# Milestones: exact cumulative prices, old goal preservation, funding and crossing.
	var data:=SaveManager.defaults();var legacy:Dictionary=data.upgrade_goal.duplicate(true)
	GrowthGoal.ensure(data);check(data.upgrade_goal==legacy,"old one-purchase goal changed")
	for kind in 2:
		for target in (GrowthGoal.RECRUIT_LEVELS if kind==0 else [2,5,8]):
			data=SaveManager.defaults();data.credits="1000000"
			var total:="0"
			for level in target:total=BigUInt.add(total,GrowthGoal.price(data,kind));data[GrowthGoal.KEYS[kind]]+=1
			data[GrowthGoal.KEYS[kind]]=0
			check(GrowthGoal.total_cost(data,kind,target)==total,"milestone cost differs from repeated real purchase")
	data=SaveManager.defaults();GrowthGoal.choose_milestone(data,0);data.upgrade_goal.level=6
	var cost:=GrowthGoal.goal_cost(data);data.credits=BigUInt.subtract(cost,"1")
	check(GrowthGoal.missing(data,data.credits)=="1","total vs shortage wrong")
	data.credits=cost;check(GrowthGoal.poll(data,cost) and not GrowthGoal.poll(data,cost),"funding notice repeated")
	var retained:Dictionary=data.upgrade_goal.duplicate(true);data.credits="1000000"
	var other:=GrowthGoal.transaction(data,1,5);check(other.upgrade_goal==retained,"other purchase changed goal")
	var crossed:=GrowthGoal.transaction(data,0,10)
	check(GrowthGoal.achieved(crossed) and crossed.upgrade_goal.level==6 and crossed.upgrade_goal.achieved_notified,"bulk crossing replaced target or lost achievement")
	check(SaveManager.save_data(crossed),"milestone save failed")
	var loaded:=SaveManager.load_data();check(int(loaded.upgrade_goal.kind)==int(crossed.upgrade_goal.kind) and int(loaded.upgrade_goal.level)==int(crossed.upgrade_goal.level) and str(loaded.upgrade_goal.mode)==str(crossed.upgrade_goal.mode) and loaded.upgrade_goal.achieved_notified and loaded.credits==crossed.credits,"milestone restart changed target/balance")
	check(ArmyAppearance.tier(8)==3 and ArmyAppearance.next_level(5)==8,"post-Lv5 appearance absent")
	check(ArmyAppearance.formation_rows(6)<ArmyAppearance.formation_rows(10) and ArmyAppearance.formation_rows(18)<ArmyAppearance.formation_rows(30),"early formation milestones not distinct")
	# Actual game, live targets and shared ledger; isolate OS focus and injected input.
	game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.set_process_unhandled_input(false)
	game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
	game.data.settings.shot_sound=3;game.data.settings.hit_sound=3;game.data.settings.auto_update=false
	for weapon in 3:
		game._show_prep();game.selected_weapon=weapon;game._start_training();game._process(3.1)
		game.training_elapsed=12.5;game.stats.base_points=8000.0;game.stats.shots=20;game.stats.hits=12
		game.streak=4;game.last_success_time=12;game.auto_streak_time=2.3;game.player.position.x=1.2;game.player.rotation.y=0.3;game.camera.rotation.x=-0.1
		game._update_targets(0.25);game._open_pause()
		var frozen:=freeze();var sessions:int=game.data.practice_totals.sessions;var history:int=game.data.training_history.size()
		var earned:int=game._session_record().credits
		game._visit_army();check(game.mode==game.Mode.ARMY and game.training_in_army,"pause to army failed")
		var balance:String=game.data.credits;var hp:float=game.data.enemy_hp
		game._process(20.0)
		check(freeze()==frozen,"army time contaminated training state/metrics")
		check(game.data.front>0 or game.data.enemy_hp!=hp,"army battle stopped")
		check(game.data.credits==balance and game.data.training_history.size()==history and game.data.practice_totals.sessions==sessions,"army visit paid twice or closed record")
		game.purchase_lock=false;game.purchase_batch=1;game._buy_upgrade(0)
		var purchased_balance:String=game.data.credits;var recruit:int=game.data.recruit
		check(purchased_balance==BigUInt.subtract(balance,"70") if recruit==1 else purchased_balance!=balance,"purchase not spent")
		game._resume_from_army();game._resume_from_army()
		check(game.mode==game.Mode.TRAINING and freeze()==frozen,"direct resume reset training")
		check(game.mouse_blocked and not game.exit_holding and game.burst_remaining==0 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"resume unsafe input")
		check(game.data.credits==purchased_balance and game.data.recruit==recruit,"resume rolled back purchase")
		game._open_pause();game._visit_army();check(game.data.credits==purchased_balance,"second visit recredited cumulative points")
		game._resume_from_army();game._finish_training(false);game._finish_training(false)
		check(game.data.credits==purchased_balance and game.data.training_history.size()==history+1,"final settlement duplicated funds/history")
		check(str(game.data.training_history[0].id)==frozen.id and earned>0,"same record not retained")
	# Changing conditions cancels/no-op without closing; confirm closes exactly once.
	game._show_prep();game._start_training();game._process(3.1);game.training_elapsed=15;game.stats.base_points=3000
	game._open_pause();var original:=freeze();var history:int=game.data.training_history.size()
	game._open_condition_picker();game._cancel_condition_picker();check(freeze()==original and game.mode==game.Mode.TRAINING,"cancel changed session")
	game._open_pause();game._open_condition_picker();game._confirm_condition_picker();check(freeze()==original and game.data.training_history.size()==history,"same conditions finalized session")
	game._open_pause();game._open_condition_picker();game.condition_weapon.select((game.training_weapon+1)%3)
	game._confirm_condition_picker();var new_id:String=game.session_id;game._confirm_condition_picker()
	check(new_id!=original.id and game.session_id==new_id and game.mode==game.Mode.COUNTDOWN,"conditions did not create exactly one fresh session")
	check(game.data.training_history.size()==history+1 and game.data.training_history[0].id==original.id,"conditions duplicated/missed old history")
	check(original.id not in game.data.training_history[0].shooting_comparison.get("ids",[]),"self included in comparison")
	# Force real save failure with a directory at the temporary-file path.
	game._process(3.1);game.training_elapsed=12;game.stats.base_points=2000;game._open_pause()
	game.is_test_mode=false
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.TEMP))
	var unchanged:Dictionary=game.data.duplicate(true);var failed_id:String=game.session_id
	game._visit_army();check(game.mode==game.Mode.PAUSED and not game.training_in_army and game.data==unchanged and game.pause_warning.visible,"failed checkpoint allowed spend or changed data")
	game._open_condition_picker();game.condition_difficulty.select((game.training_difficulty+1)%3);game._confirm_condition_picker()
	check(game.condition_panel.visible and game.session_id==failed_id and game.data==unchanged,"failed condition save closed old session")
	game._cancel_condition_picker();check(game.mode==game.Mode.TRAINING,"failed save cannot resume")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.TEMP))
	# A saved active training with purchases recovers only its checkpoint, once.
	game._open_pause();game._visit_army();game.purchase_lock=false;game._buy_upgrade(1)
	var disk:=SaveManager.load_data();var disk_balance:String=disk.credits;var disk_gear:int=disk.gear
	check(not disk.active_training.is_empty(),"army checkpoint missing on disk")
	check(TrainingLedger.recover(disk) and not TrainingLedger.recover(disk) and disk.credits==disk_balance and disk.gear==disk_gear,"crash recovery changed purchase or duplicated points")
	check(SaveManager.save_data(disk) and SaveManager.load_data().credits==disk_balance,"recovered state not durable")
	game.is_test_mode=true;game._finish_from_army()
	# Replay real physical rays with/without an army interruption. Scoring clocks
	# are training-relative, including response/streak windows and tracking phase.
	for weapon in 3:
		var expected:Dictionary={}
		for interrupted in [false,true]:
			game.data=SaveManager.defaults();game.data.settings.shot_sound=3;game.data.settings.hit_sound=3
			game._show_prep();game.selected_weapon=weapon;seed(1900+weapon);game._start_training();game._process(3.1)
			for index in 8:
				game._process(0.3)
				game.camera.look_at(game.targets[0].global_position)
				if index==5:game.camera.rotation.y+=1.2
				await physics_frame;await physics_frame
				if index==3 and interrupted:
					game._open_pause();game._visit_army();game._process(45.0);game._resume_from_army()
				seed(19000+index)
				if weapon==1:
					Input.action_press("shoot");game.mouse_blocked=false;game._process_weapon(0.3);Input.action_release("shoot")
				else:game._fire_shot()
			var facts:Dictionary={"stats":game.stats.duplicate(true),"points":game._training_result(),"q_sum":game.shooting_metrics.q_sum,"q_time":game.shooting_metrics.q_time,"phase":game.target_phase,"elapsed":game.training_elapsed,"streak":game.streak}
			if not interrupted:expected=facts
			else:
				for key in facts:check(facts[key]==expected[key],"real ray changed after army pause, weapon %d / %s: %s != %s"%[weapon,key,str(facts[key]),str(expected[key])])
			game._finish_training(false)
	# Draw initial, early, medium and late states after animation has ended.
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;root.content_scale_size=dimensions
		for stage in [0,1,3,6,11,24,100000]:
			game._show_prep();game.data=SaveManager.defaults();game.data.credits="123456789012345678901234567890";game.data.recruit=stage;game.data.gear=mini(8,stage)
			game._show_army();game._set_growth_candidate(1 if stage>=3 else 0);game._refresh_prep();game.battle_view._process(2.0)
			check(game.battle_view.visible_soldiers(Balance.soldier_count(stage))<=48 and game.battle_view.background_soldiers(Balance.soldier_count(stage))<=72,"unbounded representatives")
			await snap("army-%d-%dx%d"%[stage,dimensions.x,dimensions.y])
			if stage in [0,24]:
				game.data.credits="0" if stage==0 else "1000";game._refresh_prep()
				await snap("showcase-%d-%dx%d"%[stage,dimensions.x,dimensions.y])
		game.data=SaveManager.defaults();game.data.credits="100000";game._show_prep();game._start_training();game._process(3.1);game.training_elapsed=12
		game._open_pause();await snap("pause-%dx%d"%[dimensions.x,dimensions.y]);game._open_condition_picker();await snap("conditions-%dx%d"%[dimensions.x,dimensions.y]);game._cancel_condition_picker()
		game._open_pause();game._visit_army();game.purchase_lock=false;game._buy_upgrade(0);await snap("army-live-purchase-%dx%d"%[dimensions.x,dimensions.y])
		game.data.recruit=0;game.data.gear=7;GrowthGoal.choose_milestone(game.data,1);game._refresh_prep();game.purchase_lock=false;game._buy_upgrade(1)
		await snap("milestone-achieved-%dx%d"%[dimensions.x,dimensions.y])
		check(GrowthGoal.achieved(game.data) and game.purchase_message.visible,"achievement message missing")
		game._on_focus_lost();var frozen:=freeze();var hp:float=game.data.enemy_hp;game._process(20);check(freeze()==frozen and game.data.enemy_hp==hp,"focus loss progressed battle/training")
		game.app_focused=true;game._resume_from_army();game._finish_training(false)
	game.queue_free();for frame in 5:await process_frame
	if failures.is_empty():print("CONTINUITY_OK: exact milestones, legacy/save/reload, 3 weapon roundtrips, settlement, conditions, failure rollback, recovery and rendered layouts");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
