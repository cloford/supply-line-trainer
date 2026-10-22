extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func done()->void:
	for message in failures:push_error(message)
	quit(0 if failures.is_empty() else 1)

func _init()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":quit(1);return
	var legacy:=SaveManager.defaults();legacy.erase("metrics_schema");legacy.credits="123";legacy.settings.sensitivity=1.234
	legacy.training_history=[{"id":"old","elapsed":10,"score":100}]
	var original:=JSON.stringify(legacy)
	var f:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);f.store_string(original);f=null
	if "--backup-failure" in OS.get_cmdline_user_args():
		DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.METRICS_BACKUP))
		var blocked:=SaveManager.load_data()
		check(blocked.get("migration_failed",false) and not SaveManager.save_data(blocked),"backup failure allowed saving")
		check(FileAccess.get_file_as_string(SaveManager.PATH)==original,"failed backup changed original")
		if failures.is_empty():print("METRICS_BACKUP_FAILURE_OK: original retained and writes blocked")
		done();return
	var loaded:=SaveManager.load_data()
	check(loaded.training_history.size()==1 and loaded.training_history[0].id=="old" and loaded.training_history[0].score==100 and loaded.credits=="123" and is_equal_approx(loaded.settings.sensitivity,1.234),"legacy values changed")
	check(FileAccess.get_file_as_string(SaveManager.METRICS_BACKUP)==original,"backup differs")
	loaded.credits="150";check(SaveManager.save_data(loaded),"save failed");var after:=SaveManager.load_data()
	check(after.metrics_schema==1 and after.credits=="150" and FileAccess.get_file_as_string(SaveManager.METRICS_BACKUP)==original,"second load changed progress/backup")
	var before:=FileAccess.get_file_as_string(SaveManager.PATH)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.TEMP))
	check(not SaveManager.save_data(after) and FileAccess.get_file_as_string(SaveManager.PATH)==before,"failed write changed original")
	if failures.is_empty():print("METRICS_SAVE_OK: legacy retained, one-time backup, reload, write failure retains original")
	done()
