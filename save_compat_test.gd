extends SceneTree

func _init()->void:
	var legacy:Dictionary={"version":1,"supply":321.0,"recruit":43,"gear":2,"depot":1,"front":12,"enemy_hp":0.0,"unlocked":[true,true,true],"bests":{"0_0":777},"settings":{"sensitivity":1.0,"fov":90.0,"crosshair_color":"000000","crosshair_size":17.0,"volume":0.75},"last_save":1}
	var f:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE)
	if f==null:push_error("legacy fixture write failed");quit(1);return
	f.store_string(JSON.stringify(legacy));f=null
	var loaded:=SaveManager.load_data()
	if str(loaded.credits)!="321" or int(loaded.recruit)!=43 or str(loaded.settings.crosshair_color)!="000000" or float(loaded.settings.crosshair_size)!=17.0 or int(loaded.front)!=12 or float(loaded.enemy_hp)<=0 or int(loaded.legacy_bests.get("0_0",0))!=777 or not FileAccess.file_exists(SaveManager.BACKUP):
		push_error("legacy-compatible load mismatch"); quit(1); return
	f=FileAccess.open(SaveManager.PATH,FileAccess.WRITE); f.store_string("{broken"); f=null
	var recovered:=SaveManager.load_data()
	if str(recovered.credits)!="90" or str(recovered.settings.crosshair_color)!="66e8ff":
		push_error("corrupt save fallback failed"); quit(1); return
	var huge:=SaveManager.defaults();huge.credits="1000000000000000000000000000001";huge.commander_owned=["radio_logistics"];huge.commander_equipped=["radio_logistics","",""];huge.selected_duration=30;huge.settings.crosshair_shape=3;SaveManager.save_data(huge)
	var exact:=SaveManager.load_data()
	if str(exact.credits)!="1000000000000000000000000000001" or str(exact.commander_equipped[0])!="radio_logistics" or int(exact.selected_duration)!=30 or int(exact.settings.crosshair_shape)!=3:
		push_error("huge credit roundtrip mismatch");quit(1);return
	print("SAVE_TEST_OK: version-1 migration, backup, corrupt fallback, exact huge credits")
	quit(0)
