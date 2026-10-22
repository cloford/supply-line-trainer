extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":quit(1);return
	var old:=SaveManager.defaults();old.erase("selected_weapon");old.erase("selected_difficulty");old.erase("help_seen");old.settings.erase("show_training_goal");old.settings.erase("goal_notifications")
	old.credits="12345678901234567890";old.credit_fraction=0.375;old.front=8;old.enemy_hp=12.5;old.unlocked=[false,false,false]
	old.training_history=[{"id":"old-record","score":345,"scoring_version":4,"shooting_comparison":{"count":1,"ids":["prior"]}}]
	var file:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	var loaded:=SaveManager.load_data()
	check(loaded.selected_weapon==0 and loaded.selected_difficulty==0 and loaded.help_seen,"legacy missing selection/guide unsafe")
	check(not loaded.settings.show_training_goal and loaded.settings.goal_notifications,"missing UI settings not defaulted")
	check(loaded.credits==old.credits and loaded.credit_fraction==old.credit_fraction and loaded.front==8 and loaded.enemy_hp==12.5 and loaded.unlocked==old.unlocked,"old progress/unlock data changed")
	check(loaded.training_history[0].score==345 and loaded.training_history[0].shooting_comparison.ids==["prior"],"old history/comparison lost")
	for id in 3:check(TrainingCatalog.available(id),"catalog locked an existing ID")
	for value in [-1,9,1.5,"2",null]:
		old.selected_weapon=value;old.selected_difficulty=value
		file=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
		loaded=SaveManager.load_data();check(loaded.selected_weapon==0 and loaded.selected_difficulty==0,"invalid selection not defaulted")
	loaded.selected_weapon=2;loaded.selected_difficulty=1;loaded.settings.show_training_goal=true;loaded.settings.goal_notifications=false
	check(SaveManager.save_data(loaded),"selection save failed")
	var again:=SaveManager.load_data();check(again.selected_weapon==2 and again.selected_difficulty==1 and again.settings.show_training_goal and not again.settings.goal_notifications,"selection/UI settings reload failed")
	if failures.is_empty():print("STAGE1_SAVE_OK: legacy/default/invalid selection, guide, all training, settings and unchanged progress/history");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
