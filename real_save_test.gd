extends SceneTree

var failures:Array[String]=[]

func check(condition:bool,message:String)->void:
	if not condition:failures.append(message)

func _init()->void:
	var source:=OS.get_environment("SLT_SOURCE_SAVE")
	if OS.get_environment("SLT_TEST_DATA")!="1" or source.is_empty() or ProjectSettings.globalize_path(SaveManager.PATH).replace("\\","/")==source.replace("\\","/"):
		push_error("専用APPDATA・SLT_TEST_DATA=1・読取専用のSLT_SOURCE_SAVEが必要です。");quit(1);return
	var source_hash:=FileAccess.get_sha256(source)
	var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
	var migrated:=SaveManager.load_data()
	check(not migrated.get("migration_failed",false),"migration blocked")
	for key in ["credits","credit_fraction","recruit","gear","front","enemy_hp","unlocked","commander_owned","commander_equipped","practice_totals","bests_v2","bests_v3"]:
		check(migrated[key]==original[key],"migration changed "+key)
	for key in original.settings:
		check(migrated.settings[key]==original.settings[key],"setting changed "+key)
	if int(original.get("scoring_version",3))<4:
		check(migrated.legacy_training_history==original.training_history and migrated.training_history.is_empty(),"history archive differs")
	else:
		check(migrated.training_history==original.training_history and migrated.legacy_training_history==original.legacy_training_history,"current history changed")
	var backup_path:=SaveManager.GROWTH_BACKUP if int(original.get("growth_schema",0))<1 else SaveManager.POINTS_BACKUP
	check(FileAccess.get_sha256(backup_path)==source_hash,"backup hash differs")
	check(SaveManager.save_data(migrated),"second save failed")
	var reloaded:=SaveManager.load_data()
	for key in ["credits","credit_fraction","recruit","gear","front","enemy_hp","unlocked","settings","practice_totals","legacy_training_history","bests_v2","bests_v3"]:
		check(reloaded[key]==migrated[key],"reload changed "+key)
	check(FileAccess.get_sha256(source)==source_hash,"source changed")
	check(FileAccess.get_sha256(backup_path)==source_hash,"backup overwritten")
	if failures.is_empty():
		print("REAL_SAVE_TEST_OK: source_sha256=",source_hash," credits=",reloaded.credits," recruit=",reloaded.recruit," gear=",reloaded.gear," front=",reloaded.front," archived=",reloaded.legacy_training_history.size()," elapsed=",reloaded.practice_totals.elapsed," active=",reloaded.practice_totals.active," sessions=",reloaded.practice_totals.sessions)
		quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
