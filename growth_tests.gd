extends SceneTree

var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:call_deferred("_run")
func record(id:String,points:int)->Dictionary:
	return {"id":id,"credits":points,"score":points,"elapsed":20.0,"active":10.0,"duration":0,"point_fraction":0.375,"scoring_version":4}
func _run()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":push_error("isolated APPDATA and SLT_TEST_DATA=1 required");quit(1);return
	if "--growth-backup-failure" in OS.get_cmdline_user_args():
		var original_data:=SaveManager.defaults();original_data.erase("growth_schema")
		var raw:=JSON.stringify(original_data);var file:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);file.store_string(raw);file.close()
		DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.GROWTH_BACKUP))
		var failed:=SaveManager.load_data()
		check(bool(failed.get("migration_failed",false)) and not SaveManager.save_data(failed),"growth backup failure allowed save")
		check(FileAccess.get_file_as_string(SaveManager.PATH)==raw,"growth backup failure changed original")
		if failures.is_empty():print("GROWTH_BACKUP_FAILURE_OK: original retained and writes blocked");quit(0)
		else:quit(1)
		return
	var cases:=[[],["radio_assault"],["radio_assault","tablet_tactical","supply_front"],["radio_assault","radio_assault","unknown"],["tablet_tactical","supply_front"]]
	for owned in cases:
		var old:=SaveManager.defaults();old.erase("growth_schema");old.erase("legacy_army_multiplier")
		old.credits="12345678901234567890";old.credit_fraction=0.375;old.recruit=9;old.gear=2;old.front=8;old.enemy_hp=991.0
		old.commander_owned=owned;old.commander_equipped=["radio_assault","",""] if not owned.is_empty() else ["","",""]
		old.practice_totals.elapsed=20.0;old.practice_totals.sessions=1;old.active_training=record("pending",7)
		var before_power:=Balance.combat_power(old.recruit,old.gear,Balance.commander_multiplier(old.commander_equipped))
		var file:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
		var migrated:=SaveManager.load_data()
		check(FileAccess.file_exists(SaveManager.GROWTH_BACKUP),"migration backup missing")
		var backup_hash:=FileAccess.get_sha256(SaveManager.GROWTH_BACKUP)
		var expected:=1.0
		for item in Balance.LEGACY_COMMANDER_ITEMS:
			if item.id in owned or old.commander_equipped[item.slot]==item.id:expected*=float(item.combat)
		check(is_equal_approx(migrated.legacy_army_multiplier,expected),"owned/valid equipped union was not unique")
		check(Balance.army_power(migrated)>=before_power-0.00001,"migration reduced combat power")
		for key in ["credits","credit_fraction","recruit","gear","front","enemy_hp","unlocked","training_history","settings"]:check(migrated[key]==old[key],"migration changed "+key)
		for key in old.practice_totals:check(is_equal_approx(float(migrated.practice_totals[key]),float(old.practice_totals[key])),"migration changed practice total "+key)
		TrainingLedger.recover(migrated);var credits:String=migrated.credits;var totals:Dictionary=migrated.practice_totals.duplicate(true)
		check(not TrainingLedger.recover(migrated),"pending recovery repeated")
		migrated.growth_migration_notice=false
		SaveManager.save_data(migrated);var again:=SaveManager.load_data()
		check(again.credits==credits and again.practice_totals==totals and is_equal_approx(again.legacy_army_multiplier,expected),"reload duplicated effect/credits/time")
		check(FileAccess.get_sha256(SaveManager.GROWTH_BACKUP)==backup_hash,"migration backup overwritten")
		check(not again.growth_migration_notice,"migration notice repeated")
	var data:=SaveManager.defaults();check(data.legacy_army_multiplier==1.0,"new save got legacy benefit")
	check(data.upgrade_goal.kind==0 and data.upgrade_goal.level==1,"cheapest initial goal")
	data.credits="69";GrowthGoal.choose(data,0);check(GrowthGoal.missing(data,data.credits)=="1","1P short")
	data.credits="70";check(GrowthGoal.missing(data,data.credits)=="0" and GrowthGoal.poll(data,data.credits),"exact required amount")
	data.credits="71";check(GrowthGoal.missing(data,data.credits)=="0" and not GrowthGoal.poll(data,data.credits),"1P excess/duplicate notice")
	data.credits="0";GrowthGoal.choose(data,1);GrowthGoal.choose(data,0);data.credits="70";check(not GrowthGoal.poll(data,data.credits),"switch/funding recross repeated notice")
	data=SaveManager.defaults();var session:=record("live",75);var live:=GrowthGoal.available(data,session)
	TrainingLedger.checkpoint(data,session);check(GrowthGoal.available(data,session)==live,"checkpoint changed goal balance")
	TrainingLedger.finish(data,session,"終了");check(data.credits==live,"ended result differs from HUD affordability")
	var bought:=GrowthGoal.transaction(data,0,1);check(bought.recruit==1 and bought.credits=="5","exact affordable purchase after finish")
	data=SaveManager.defaults();data.credits="10000";GrowthGoal.choose(data,1);var retained:Dictionary=data.upgrade_goal.duplicate(true)
	var unrelated:=GrowthGoal.transaction(data,0,1);check(unrelated.upgrade_goal==retained,"unrelated upgrade changed goal")
	var bulk:=GrowthGoal.transaction(data,1,5);check(bulk.gear==5 and bulk.upgrade_goal!=retained,"bulk crossing did not complete goal")
	data.credits="12345678901234567890";var huge:=GrowthGoal.transaction(data,0,1)
	check(huge.credits=="12345678901234567820" and GrowthGoal.missing(data,data.credits)=="0","large integer precision")
	check(BigUInt.format("100000")=="10.00万" and BigUInt.format("10000000")=="1000.00万","shortened decimal place")
	var display:=BattleView.new();root.add_child(display);display.set_state({"soldiers":6,"gear":0,"front":0,"enemy_hp":70,"enemy_max":70,"running":true})
	display.play_purchase(0,{"soldiers":6,"gear":0},{"soldiers":46,"gear":0})
	check(display.recruit_joins.size()==40,"bulk recruit did not animate all new foreground soldiers")
	for index in 10:display.play_purchase(0,{"soldiers":100+index*4,"gear":0},{"soldiers":104+index*4,"gear":0})
	check(display.reinforcement_wave.size()<=12 and display.reinforcement_serial==40,"rapid purchases missed or leaked reinforcement wave")
	check(display.background_soldiers(10000000)<=72,"background unbounded")
	var preview:=ArmyPreview.new();root.add_child(preview)
	seed(4567);var expected_random:=randi();seed(4567)
	var untouched:=data.duplicate(true);preview.set_comparison(1,{"soldiers":6,"gear":1},{"soldiers":6,"gear":2})
	check(randi()==expected_random and data==untouched and not preview.is_processing(),"preview changed RNG/game state or processes continuously")
	preview.queue_free();display.queue_free()
	var game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game._show_army();game.data=SaveManager.defaults();game.data.credits="10000";game._buy_upgrade(0);game._buy_upgrade(0)
	check(game.data.recruit==1 and game.data.credits=="9930","same-frame double purchase")
	await create_timer(0.05).timeout;game._buy_upgrade(0)
	check(game.data.recruit==1,"cross-frame double click bought twice")
	await create_timer(0.2).timeout
	var original:Dictionary=game.data.duplicate(true);game.is_test_mode=false
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.TEMP));game._buy_upgrade(1)
	check(game.data==original,"failed save committed purchase")
	check(game.purchase_message.is_visible_in_tree(),"purchase rollback message hidden")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.TEMP));game.is_test_mode=true
	await process_frame
	var running_data:=SaveManager.defaults();game.data=running_data.duplicate(true);game.battle_view.show();game._process_battle(1.0);var visible_hp:float=game.data.enemy_hp
	game.data=running_data.duplicate(true);game.battle_view.hide();game._process_battle(1.0)
	check(is_equal_approx(float(game.data.enemy_hp),visible_hp),"visibility changed battle DPS")
	game.queue_free();for frame in 3:await process_frame
	if failures.is_empty():print("GROWTH_TEST_OK: migration union/idempotence, exact goal balances, checkpoints, notifications, purchases and save rollback");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
