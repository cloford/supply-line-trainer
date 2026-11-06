extends SceneTree

var failures:Array[String] = []

func check(value:bool, message:String)->void:
	if not value:
		failures.append(message)

func record(id:String, weapon:int, kills:int = 0, tracking:float = 0.0)->Dictionary:
	return {"id":id,"weapon":weapon,"elapsed":1.0,"active":1.0,"duration":0,"credits":0,"progress_kills":kills,"progress_tracking_seconds":tracking,"progress_measurement":false}

func measurement(id:String, weapon:int)->Dictionary:
	var measured := V2Measurement.new()
	measured.begin(weapon,{},123,id)
	measured.shot(0.1,true,0.5,"target",Vector3.ZERO,Vector3.FORWARD,Vector3.FORWARD)
	return measured.completed(60.0)

func _init()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		push_error("SLT_TEST_DATA=1 and isolated APPDATA required")
		quit(2)
		return
	var data := V2Save.defaults()
	check(Progression.unlocked(data,0) and not Progression.unlocked(data,1),"fresh HG only")
	check(not Progression.list_visible(data),"fresh list hidden")
	var running := record("free",0,1)
	V2Ledger.checkpoint(data,running)
	check(Progression.total(data) == 1 and Progression.pending_notifications(data).size() == 1,"first kill unlock")
	V2Ledger.checkpoint(data,running)
	check(Progression.total(data) == 1,"checkpoint idempotent")
	Progression.mark_seen(data,"first_kill")
	check(Progression.pending_notifications(data).is_empty(),"notification read separate")
	for boundary in [5,9,10,99,100,499,500,1499,1500]:
		running.progress_kills = boundary
		V2Ledger.checkpoint(data,running)
		check(Progression.total(data) == boundary,"cumulative delta %d" % boundary)
		for weapon in 5:
			check(Progression.unlocked(data,weapon) == (boundary >= Progression.THRESHOLDS[weapon]),"unlock boundary %d / %d" % [boundary,weapon])
		check(Progression.list_visible(data),"list from 5")
		var expected_rows := 5 if boundary >= 500 else (4 if boundary >= 100 else (3 if boundary >= 10 else 2))
		check(Progression.weapon_rows(data).size() == expected_rows,"rows only next locked")
	check(Progression.weapon_rows(data).all(func(row): return row.unlocked),"no silhouette after all unlocks")
	V2Ledger.finish(data,running,"終了")
	V2Ledger.finish(data,running,"終了")
	check(Progression.total(data) == 1500,"finish idempotent")
	var ar := record("tracking",1,999,0.4)
	V2Ledger.checkpoint(data,ar)
	ar.progress_tracking_seconds = 0.9
	V2Ledger.checkpoint(data,ar)
	check(Progression.total(data) == 1500,"tracking fractional no kills")
	ar.progress_tracking_seconds = 1.1
	V2Ledger.checkpoint(data,ar)
	check(Progression.total(data) == 1501 and is_equal_approx(float(data.progression.tracking_seconds),1.1),"tracking retained fraction")
	V2Ledger.finish(data,ar,"終了")
	var grenade := record("grenade",4,3)
	V2Ledger.finish(data,grenade,"終了")
	check(Progression.total(data) == 1504,"grenade counts actual kills")
	for mode in ["replay","preview","demo","battle","test_fire"]:
		var excluded := record(mode,0,100)
		excluded.mode = mode
		V2Ledger.finish(data,excluded,"終了")
	check(Progression.total(data) == 1504,"excluded modes")
	var dry := record("dry",0)
	V2Ledger.finish(data,dry,"終了")
	check(Progression.total(data) == 1504,"dry fire no progress")
	var invalid := record("aborted",0,30)
	invalid.progress_measurement = true
	invalid.measurement = {"completed":false}
	V2Ledger.checkpoint(data,invalid)
	V2Ledger.finish(data,invalid,"終了")
	check(Progression.total(data) == 1504,"invalid measurement no progress")
	var valid := record("valid",0,20)
	valid.progress_measurement = true
	valid.measurement = measurement("valid",0)
	valid.elapsed = 60.0
	V2Ledger.checkpoint(data,valid)
	check(Progression.total(data) == 1504,"measurement stays provisional")
	V2Ledger.finish(data,valid,"終了")
	V2Ledger.finish(data,valid,"終了")
	check(Progression.total(data) == 1524 and data.measurement_counts[0] == 1,"valid 60sec commits once")
	check(V2Save.save_data(data),"save progression")
	var loaded := V2Save.load_data()
	check(int(loaded.progression.total) == int(data.progression.total) and loaded.progression.achievements == data.progression.achievements and loaded.progression.seen == data.progression.seen and is_equal_approx(float(loaded.progression.tracking_seconds),float(data.progression.tracking_seconds)),"reload exact progression and seen")
	var candidate := loaded.duplicate(true)
	V2Ledger.finish(candidate,record("retry",0,5),"終了")
	V2Save.test_fail_step = "rename"
	check(not V2Save.save_data(candidate),"save failure injected")
	check(Progression.total(V2Save.load_data()) == 1524,"failed candidate leaves committed save")
	V2Save.test_fail_step = ""
	check(V2Save.save_data(candidate),"retry candidate save")
	var retried := V2Save.load_data()
	V2Ledger.finish(retried,record("retry",0,5),"終了")
	check(Progression.total(retried) == 1529,"retry no duplicate")
	for step in ["temp","previous"]:
		var failed_candidate := retried.duplicate(true)
		V2Ledger.finish(failed_candidate,record("failed-"+step,0,3),"終了")
		V2Save.test_fail_step = step
		check(not V2Save.save_data(failed_candidate),"failure stage " + step)
		check(Progression.total(V2Save.load_data()) == 1529,"failed stage preserves " + step)
	V2Save.test_fail_step = ""
	var old := V2Save.defaults()
	old.erase("progression")
	old.credits = "12345"
	old.settings.sensitivity = 2.5
	old.training_history = [record("old-hg",0),record("old-hg",0),record("old-ar",1),record("old-br",2)]
	old.training_history[0].stats = {"kills":7}
	old.training_history[1].stats = {"kills":7}
	old.training_history[2].metrics = {"track_time":3.75}
	old.training_history[3].accuracy = 1.0
	check(Progression.migrate(old),"migrated existing save")
	check(Progression.total(old) == 10 and old.progression.kills == 7,"facts only unique old IDs")
	check(Progression.unlocked(old,2),"existing BR usage stays unlocked")
	check(Progression.pending_notifications(old).is_empty(),"migration no banner flood")
	check(old.credits == "12345" and old.settings.sensitivity == 2.5,"preserve unrelated fields")
	check(not Progression.migrate(old) and Progression.total(old) == 10,"migration once")
	check(Progression.valid(old.progression),"migration schema valid")
	var preserved := V2Save.defaults()
	preserved.progression.preserved_weapons = [1,2]
	var json_restored:Dictionary = JSON.parse_string(JSON.stringify(preserved))
	check(typeof(json_restored.progression.preserved_weapons[0]) == TYPE_FLOAT,"JSON preserved IDs restore as float")
	check(Progression.unlocked(json_restored,1) and Progression.unlocked(json_restored,2),"zero-progress AR and BR survive JSON reload")
	check(not Progression.unlocked(json_restored,3),"preserved locks do not unlock new weapons")
	check(V2Save.save_data(preserved),"save preserved weapons at zero progress")
	var preserved_reload := V2Save.load_data()
	check(Progression.total(preserved_reload) == 0 and Progression.unlocked(preserved_reload,1) and Progression.unlocked(preserved_reload,2),"preserved AR and BR survive actual save/reload")
	check(Progression.weapon_rows(preserved_reload).size() == 4 and Progression.weapon_rows(preserved_reload)[2].unlocked,"reloaded roster retains preserved BR")
	var adopted := V2Save.defaults()
	adopted.erase("progression")
	V2Profiles.adopt(adopted,measurement("adopted-ar",1))
	Progression.migrate(adopted)
	check(Progression.unlocked(adopted,1) and Progression.total(adopted) == 0,"adoption preserves lock without fabricated progress")
	var recovered := V2Save.defaults()
	recovered.erase("progression")
	recovered.active_training = record("old-active",0)
	recovered.active_training.metrics = {"kills":5}
	Progression.migrate(recovered)
	V2Ledger.recover(recovered)
	check(Progression.total(recovered) == 5,"active recovery no double migration")
	var old_file := V2Save.defaults()
	old_file.erase("progression")
	old_file.credits = "991"
	old_file.settings.sensitivity = 3.5
	old_file.training_history = [record("old-file",0)]
	old_file.training_history[0].metrics = {"kills":11}
	old_file.measurement_counts[2] = 1
	check(V2Save._valid_data(old_file),"old v2 accepted without progression")
	var fixture := FileAccess.open(V2Save.PATH,FileAccess.WRITE)
	fixture.store_string(JSON.stringify(old_file))
	fixture.close()
	var migrated_file := V2Save.load_data()
	check(not bool(migrated_file.get("migration_failed",false)),"old v2 loaded and persisted")
	check(Progression.total(migrated_file) == 11 and Progression.unlocked(migrated_file,2),"old file factual counters and measured lock")
	check(migrated_file.credits == "991" and migrated_file.settings.sensitivity == 3.5,"old file credit/settings retained")
	check(Progression.pending_notifications(migrated_file).is_empty(),"old file notifications silent")
	check(Progression.total(V2Save.load_data()) == 11,"old file migration only once")
	var old_duplicate := record("old-file",0,11)
	V2Ledger.finish(migrated_file,old_duplicate,"終了")
	check(Progression.total(migrated_file) == 11,"history ID guard without settled array")
	var broken := migrated_file.duplicate(true)
	broken.progression.total = 999
	check(not V2Save.save_data(broken),"inconsistent progression rejected")
	if failures.is_empty():
		print("PROGRESSION_OK: boundaries, fractional AR, valid measurement only, exclusions, save retry/reload, factual migration, preserved locks")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
