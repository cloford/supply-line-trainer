extends SceneTree

var failures:Array[String]=[]

func check(condition:bool,message:String)->void:
	if not condition:failures.append(message)

func _init()->void:
	# セーブを上書きするため、専用のAPPDATA領域でのみ実行する。
	if OS.get_environment("SLT_TEST_DATA")!="1":
		push_error("SLT_TEST_DATA=1 と専用APPDATAを指定してください。");quit(1);return
	var legacy:Dictionary={"version":4,"credits":"1058669827372285402","credit_fraction":0.375,"recruit":1011,"gear":5,"front":4291,"enemy_hp":100.0,"unlocked":[true,true,true],"commander_owned":["radio_assault"],"commander_equipped":["radio_assault","",""],"bests_v2":{"v2_0_0_30":2877},"bests_v3":{"v3_0_0_60":991},"settings":{"sensitivity":1.25,"sensitivity_game":1,"dpi":800.0,"fov":93.0,"crosshair_color":"000000","crosshair_size":17.0,"crosshair_shape":2,"crosshair_outline":false,"volume":0.66},"practice_totals":{"elapsed":30.0,"active":15.0,"sessions":2,"unlimited_elapsed":30.0,"unlimited_active":15.0,"unlimited_sessions":2},"training_history":[{"id":"finished","score":9000,"credits":900,"scoring_version":3}],"active_training":{"id":"old_pending","duration":0,"elapsed":20.0,"active":10.0,"score":5000,"credits":500,"scoring_version":3},"last_save":1}
	var f:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE)
	if f==null:push_error("fixture write failed");quit(1);return
	var original:=JSON.stringify(legacy);f.store_string(original);f=null
	if "--backup-failure" in OS.get_cmdline_user_args():
		# バックアップ先をディレクトリにして、安全にコピー失敗を再現する。
		DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.POINTS_BACKUP))
		var blocked:=SaveManager.load_data()
		check(bool(blocked.get("migration_failed",false)),"backup failure did not block migration")
		check(not SaveManager.save_data(blocked),"write allowed after backup failure")
		check(FileAccess.get_file_as_string(SaveManager.PATH)==original,"original changed after backup failure")
		if failures.is_empty():print("SAVE_BACKUP_FAILURE_TEST_OK: failed backup blocks writes and retains original");quit(0)
		else:
			for message in failures:push_error(message)
			quit(1)
		return
	var loaded:=SaveManager.load_data()
	check(loaded.credits==legacy.credits and loaded.credit_fraction==0.375,"exact currency changed or old pending reawarded")
	check(loaded.recruit==1011 and loaded.gear==5 and loaded.front==4291 and loaded.unlocked==[true,true,true] and loaded.commander_owned==legacy.commander_owned,"legacy growth reset")
	check(loaded.practice_totals.elapsed==30.0 and loaded.practice_totals.sessions==2,"legacy pending duplicated time")
	check(loaded.training_history.is_empty() and loaded.active_training.is_empty() and loaded.legacy_training_history.size()==2,"legacy history/pending not archived")
	check(int(loaded.bests_v2.get("v2_0_0_30",0))==2877 and int(loaded.bests_v3.get("v3_0_0_60",0))==991 and loaded.bests_v4.is_empty(),"old bests lost or mixed")
	check(loaded.settings.sensitivity==1.25 and loaded.settings.auto_update and not loaded.settings.score_details,"settings migration wrong")
	check(loaded.selected_duration==0 and loaded.scoring_version==4 and loaded.training_schema==2,"v1.4 defaults missing")
	check(FileAccess.file_exists(SaveManager.POINTS_BACKUP),"pre-v1.4 backup missing")
	var backup:=FileAccess.get_file_as_string(SaveManager.POINTS_BACKUP)
	check(backup==original,"backup differs from original")
	loaded.settings.auto_update=false;loaded.settings.score_details=true
	check(SaveManager.save_data(loaded),"migrated save failed")
	var second:=SaveManager.load_data()
	check(second.credits==legacy.credits and second.recruit==1011 and second.legacy_training_history.size()==2,"migration repeated")
	check(not second.settings.auto_update and second.settings.score_details,"settings persistence failed")
	check(FileAccess.get_file_as_string(SaveManager.POINTS_BACKUP)==backup,"one-time backup overwritten")
	var new_result:=Balance.score_and_reward(0,0,{"base_points":45.0},0,0,3,float(second.credit_fraction))
	var new_record:Dictionary={"id":"new_pending","duration":0,"elapsed":3.0,"active":1.5,"score":new_result.score,"credits":new_result.supply,"point_fraction":new_result.fraction,"scoring_version":4}
	TrainingLedger.checkpoint(second,new_record)
	check(SaveManager.save_data(second),"v4 checkpoint save failed")
	var after_restart:=SaveManager.load_data()
	check(TrainingLedger.recover(after_restart),"v4 checkpoint not recovered after disk reload")
	check(after_restart.credits==BigUInt.add(legacy.credits,str(new_result.score)) and is_equal_approx(after_restart.credit_fraction,new_result.fraction),"disk reload lost fraction or duplicated points")
	check(after_restart.practice_totals.elapsed==33.0 and after_restart.practice_totals.sessions==3,"disk recovery duplicated totals")
	legacy.version=3
	f=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);f.store_string(JSON.stringify(legacy));f=null
	var oldest:=SaveManager.load_data()
	check(oldest.credits==legacy.credits and oldest.recruit==1011 and oldest.gear==5 and oldest.front==4291,"pre-v4 save reset")
	check(FileAccess.get_file_as_string(SaveManager.POINTS_BACKUP)==backup,"older import overwrote first backup")
	f=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);f.store_string("{broken");f=null
	var corrupt:=SaveManager.load_data()
	check(bool(corrupt.get("migration_failed",false)) and not SaveManager.save_data(corrupt) and FileAccess.get_file_as_string(SaveManager.PATH)=="{broken","corrupt original overwritten")
	if failures.is_empty():print("SAVE_TEST_OK: exact balances, no reset, legacy recovery/archive, one-time backup, settings persistence");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
