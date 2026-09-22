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
			s={"kills":18,"hits":24,"shots":30,"track_time":22.0,"fire_time":30.0,"base_points":900.0,"center_bonus":180.0,"speed_bonus":90.0,"streak_bonus":45.0}
			var result:=Balance.score_and_reward(w,d,s,0,60,60.0)
			check(result.score>0 and result.supply>0,"positive reward %d/%d"%[w,d])
			check(result.score<=1305,"bonus cap")
	var first_reward:=Balance.score_and_reward(0,0,{"kills":12,"hits":12,"shots":18,"track_time":0.0,"fire_time":0.0,"base_points":540.0,"center_bonus":90.0,"speed_bonus":45.0,"streak_bonus":25.0},0,60,60.0)
	check(float(first_reward.supply)>=Balance.recruit_cost(0),"first training cannot buy recruit")
	check(Balance.recruit_cost(5)>Balance.recruit_cost(4),"recruit costs increase")
	check(Balance.gear_multiplier(4)>Balance.gear_multiplier(3),"gear effect increases")
	check(Balance.soldier_count(0)==6 and Balance.soldier_count(25)==106,"linear soldier growth")
	check(absf(Balance.cm_per_360(0,1.0,800.0)-51.9545)<0.01,"CS cm/360")
	check(absf(Balance.cm_per_360(1,1.0,800.0)-16.3285)<0.01,"VALORANT cm/360")
	check(Balance.front_hp(30)>Balance.front_hp(12),"infinite front growth")
	check(Balance.format_soldiers(43)=="178人","integer soldier display")
	check(BigUInt.add("1000000000000000000","1")=="1000000000000000001","exact huge credit add")
	check(BigUInt.subtract("1000000000000000001","1")=="1000000000000000000","exact huge credit subtract")
	check(BigUInt.compare("999999999999999999","1000000000000000000")<0,"exact huge credit compare")
	check(Balance.front_hp(100)<100000.0,"front growth remains bounded")
	var defaults:=SaveManager.defaults()
	check(defaults.unlocked==[true,false,false] and defaults.credits=="0" and defaults.version==4,"reset defaults")
	check(defaults.settings.has("shot_sound") and defaults.settings.has("hit_pitch_combo"),"sound settings defaults")
	if failures.is_empty():
		print("TEST_OK: scoring v2, sensitivity, restrained growth, exact credits, sound defaults")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
