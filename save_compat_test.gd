extends SceneTree

func _init()->void:
	var legacy:Dictionary=SaveManager.defaults()
	legacy.supply=321.0; legacy.recruit=3; legacy.gear=2; legacy.depot=1; legacy.settings.crosshair_color="000000"; legacy.settings.crosshair_size=17.0
	if not SaveManager.save_data(legacy):
		push_error("save failed"); quit(1); return
	var loaded:=SaveManager.load_data()
	if int(loaded.supply)!=321 or int(loaded.recruit)!=3 or str(loaded.settings.crosshair_color)!="000000" or float(loaded.settings.crosshair_size)!=17.0:
		push_error("legacy-compatible load mismatch"); quit(1); return
	var f:=FileAccess.open(SaveManager.PATH,FileAccess.WRITE); f.store_string("{broken"); f=null
	var recovered:=SaveManager.load_data()
	if int(recovered.supply)!=90 or str(recovered.settings.crosshair_color)!="66e8ff":
		push_error("corrupt save fallback failed"); quit(1); return
	print("SAVE_TEST_OK: version-1 fields, dark crosshair, corrupt fallback")
	quit(0)
