extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":quit(1);return
	var old:=SaveManager.defaults();old.erase("scoring_capture_schema");old.credits="12345678901234567890";old.credit_fraction=0.375
	old.training_history=[{"id":"finished-old","score":90,"scoring_version":4,"shooting_comparison":{"count":1,"ids":["prior"]}}]
	old.active_training={"id":"pending-old","elapsed":15.0,"active":10.0,"duration":0,"credits":7,"point_fraction":0.375,"scoring_version":4}
	var raw:=JSON.stringify(old);var file:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);file.store_string(raw);file.close()
	if "--backup-failure" in OS.get_cmdline_user_args():DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveManager.REWARD_BACKUP))
	var data:=SaveManager.load_data()
	if "--backup-failure" in OS.get_cmdline_user_args():
		check(data.get("migration_failed",false) and not SaveManager.save_data(data) and FileAccess.get_file_as_string(SaveManager.PATH)==raw,"backup failure modified original")
	else:
		check(FileAccess.get_file_as_string(SaveManager.REWARD_BACKUP)==raw,"backup missing or differs")
		check(data.credits==old.credits and data.credit_fraction==old.credit_fraction and not data.training_history[0].has("scoring_raw"),"old points changed or raw guessed")
		check(TrainingLedger.recover(data) and not TrainingLedger.recover(data),"old pending recovery not idempotent")
		check(data.credits==old.credits and data.training_history[0].status=="中断復元" and data.training_history[1].score==90,"old checkpoint recalculated or reawarded")
		check(data.training_history[1].shooting_comparison.ids==["prior"],"historical baseline lost")
		check(SaveManager.save_data(data),"save failed")
		var reloaded:=SaveManager.load_data()
		check(reloaded.scoring_capture_schema==1 and reloaded.credits==old.credits and not TrainingLedger.recover(reloaded),"repeated migration/recovery")
		check(FileAccess.get_file_as_string(SaveManager.REWARD_BACKUP)==raw,"backup overwritten")
	if failures.is_empty():print("REWARD_SAVE_OK: old values/history/comparison/pending retained, no guessed raw, no reaward, once backup/failure");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
