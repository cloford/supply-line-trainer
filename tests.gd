extends SceneTree

var failures:Array[String] = []

func check(condition:bool, message:String)->void:
	if not condition: failures.append(message)

func _init()->void:
	var vertical:=rad_to_deg(2.0*atan(tan(deg_to_rad(90.0)/2.0)/(4.0/3.0)))
	check(absf(vertical-73.7398)<0.001,"FOV conversion")
	for w in 3:
		for d in 3:
			var s:Dictionary
			if w==0: s={"kills":22,"hits":22,"shots":28,"track_time":0.0,"fire_time":0.0}
			elif w==1: s={"kills":0,"hits":0,"shots":300,"track_time":22.0,"fire_time":30.0}
			else: s={"kills":18,"hits":26,"shots":36,"track_time":0.0,"fire_time":0.0}
			var result:=Balance.score_and_reward(w,d,s,0)
			check(result.score>0 and result.supply>0,"positive reward %d/%d"%[w,d])
	check(Balance.recruit_cost(5)>Balance.recruit_cost(4),"recruit costs increase")
	check(Balance.gear_multiplier(4)>Balance.gear_multiplier(3),"gear effect increases")
	check(Balance.offline_cap(11)>Balance.offline_cap(0),"offline cap follows progress")
	var defaults:=SaveManager.defaults()
	check(defaults.unlocked==[true,false,false],"initial unlocks")
	if failures.is_empty():
		print("TEST_OK: scoring, economy, FOV, defaults")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

