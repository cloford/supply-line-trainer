extends SceneTree

func _init()->void:
	var legacy:Dictionary={"version":3,"credits":"1058669827372285402","recruit":1011,"gear":5,"depot":3,"front":4291,"enemy_hp":1.0e280,"unlocked":[true,true,true],"bests_v2":{"v2_0_0_30":2877},"settings":{"sensitivity":1.25,"sensitivity_game":1,"dpi":800.0,"fov":93.0,"crosshair_color":"000000","crosshair_size":17.0,"crosshair_shape":2,"crosshair_outline":false,"volume":0.66},"last_save":1}
	var f:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE)
	if f==null:push_error("legacy fixture write failed");quit(1);return
	f.store_string(JSON.stringify(legacy));f=null
	var loaded:=SaveManager.load_data()
	if str(loaded.credits)!="0" or int(loaded.recruit)!=0 or int(loaded.gear)!=0 or int(loaded.front)!=0 or loaded.unlocked!=[true,false,false] or not loaded.commander_owned.is_empty() or int(loaded.bests_v2.get("v2_0_0_30",0))!=2877 or float(loaded.settings.sensitivity)!=1.25 or int(loaded.settings.sensitivity_game)!=1 or not FileAccess.file_exists(SaveManager.GROWTH_RESET_BACKUP):
		push_error("growth reset migration mismatch");quit(1);return
	loaded.credits="123";loaded.recruit=2;loaded.settings.shot_sound=2;loaded.settings.hit_pitch_combo=false;SaveManager.save_data(loaded)
	var second:=SaveManager.load_data()
	if str(second.credits)!="123" or int(second.recruit)!=2 or int(second.settings.shot_sound)!=2 or bool(second.settings.hit_pitch_combo):
		push_error("migration repeated or sound settings lost");quit(1);return
	f=FileAccess.open(SaveManager.PATH,FileAccess.WRITE);f.store_string("{broken");f=null
	var recovered:=SaveManager.load_data()
	if str(recovered.credits)!="0" or str(recovered.settings.crosshair_color)!="66e8ff":
		push_error("corrupt save fallback failed");quit(1);return
	print("SAVE_TEST_OK: one-time growth reset, backup, settings and v2 records retained, sound persistence")
	quit(0)
