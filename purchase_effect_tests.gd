extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:call_deferred("_run")
func _run()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":quit(1);return
	var data:=SaveManager.defaults();data.credits="100000"
	var original:=data.duplicate(true)
	for multiplier in [1.0,1.75]:
		data.legacy_army_multiplier=multiplier
		for kind in 2:
			for batch in [1,5,10]:
				var before:=data.duplicate(true)
				var preview:=PurchaseEffect.preview(data,kind,batch)
				var purchased:=GrowthGoal.transaction(data,kind,batch)
				var actual:=PurchaseEffect.compare(data,purchased,kind,batch)
				check(preview==actual,"preview differs from transaction state")
				check(data==before,"preview changed game data")
				check(is_equal_approx(actual.d0,Balance.army_power(data)*0.18) and is_equal_approx(actual.d1,Balance.army_power(purchased)*0.18),"DPS differs from prechange real battle")
				check(is_equal_approx(actual.t0,float(data.enemy_hp)/actual.d0) and is_equal_approx(actual.saved_seconds,actual.t0-actual.t1),"same H time calculation")
				check(is_equal_approx(actual.reduction,1-actual.d0/actual.d1),"reduction was DPS percentage")
	data=original.duplicate(true)
	var known:=PurchaseEffect.preview(data,0,1)
	check(is_equal_approx(known.reduction,0.4) and is_equal_approx(known.t0,70.0/1.08) and is_equal_approx(known.t1,70.0/1.8),"known initial example")
	data.enemy_hp=0.01;var tiny:=PurchaseEffect.preview(data,0,1)
	check(PurchaseEffect.presentation(tiny,0).timing.contains("1秒未満"),"subsecond difference exaggerated")
	for h in [0.0,-1.0,NAN,INF]:
		data.enemy_hp=h;var invalid:=PurchaseEffect.preview(data,0,1)
		check(not invalid.valid and PurchaseEffect.presentation(invalid,0).timing.is_empty(),"invalid HP time shown")
	data.enemy_hp=70
	for multiplier in [0.0,-1.0,NAN,INF]:
		data.legacy_army_multiplier=multiplier;check(not PurchaseEffect.preview(data,0,1).valid,"invalid DPS time shown")
	var game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game._show_army();game.data=original.duplicate(true);game.data.enemy_hp=31.25;game._refresh_prep()
	var preview:=PurchaseEffect.preview(game.data,0,1);var hp:float=game.data.enemy_hp
	game._buy_upgrade(0);var effect:Dictionary=game.last_purchase_effect.duplicate(true)
	check(effect==preview and effect.hp==hp and game.data.enemy_hp==hp,"purchase compared different enemy/time")
	check(game.purchase_effect_view.visible and game.purchase_effect_timer==PurchaseEffect.DURATION,"success notification missing")
	game._buy_upgrade(0);check(game.last_purchase_effect==effect,"duplicate click replayed comparison")
	game._process_battle(0.1);check(game.last_purchase_effect==effect,"live ETA overwrote saved snapshot")
	game.data.front+=1;game._update_battle_view()
	check(not game.purchase_effect_view._timing_label.visible,"new front reused old seconds")
	game._update_growth_feedback(2.7);check(not game.purchase_effect_view.visible and game.last_purchase_effect.is_empty(),"notification did not expire")
	await create_timer(0.25).timeout;game._buy_upgrade(1)
	check(game.last_purchase_effect.kind==1,"latest purchase did not replace earlier notification")
	game._show_prep();game._show_army();check(not game.purchase_effect_view.visible,"reopening replayed purchase")
	await create_timer(0.25).timeout
	game.data.credits="0";game._buy_upgrade(0);check(game.last_purchase_effect.is_empty(),"insufficient funds success notification")
	await create_timer(0.25).timeout
	game.data.credits="100000";game.is_test_mode=false;var before:Dictionary=game.data.duplicate(true)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.TEMP));game._buy_upgrade(0)
	check(game.data==before and game.last_purchase_effect.is_empty() and game.purchase_message.visible,"failed save success or hidden error")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.TEMP));game.is_test_mode=true
	# 表示の有無でDPSや進行は変わらない。
	game.data=before.duplicate(true);game._process_battle(0.2);var visible_hp:float=game.data.enemy_hp
	game.data=before.duplicate(true);game.purchase_effect_view.hide();game._process_battle(0.2);check(game.data.enemy_hp==visible_hp,"comparison visibility changed progression")
	game.queue_free();for frame in 4:await process_frame
	if failures.is_empty():print("PURCHASE_EFFECT_OK: same H, real DPS, batches, legacy multiplier, invalid values, successful transactions only, expiry/front/visibility");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
