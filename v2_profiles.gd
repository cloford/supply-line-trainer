class_name V2Profiles
extends RefCounted

static func basic(weapon:int)->Dictionary:
	var times:Array = []
	for second in range(60):
		if weapon == 0:
			times.append(float(second))
		elif weapon == 1 and second % 2 == 0:
			for bullet in range(10):
				times.append(second + bullet * 0.1)
		elif weapon == 2:
			for bullet in range(3):
				times.append(second + bullet * 0.085)
	return {"weapon":weapon, "record_id":"basic-%d" % weapon, "basic":true, "label":"基礎兵士（標準値）", "rpm":times.size(), "p":0.60, "q":0.0, "c":0.05, "timeline":times, "profile_version":V2Rules.PROFILE_VERSION, "flavor":"ゲームの標準値を持つ基礎兵士"}

static func from_record(record:Dictionary)->Dictionary:
	if str(record.get("mode","")) != "measurement" or not bool(record.get("completed",false)):
		return {}
	if bool(record.get("interrupted",false)) or bool(record.get("settings_changed",false)) or bool(record.get("restored",false)):
		return {}
	if not record.get("weapon") is float and not record.get("weapon") is int:
		return {}
	if str(record.get("record_id","")).is_empty() or not V2Rules.valid_weapon(int(record.get("weapon",-1))):
		return {}
	for key in ["profile_version","measurement_version","elapsed"]:
		if typeof(record.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(record[key])):
			return {}
	if int(record.get("profile_version",0)) != V2Rules.PROFILE_VERSION or int(record.get("measurement_version",0)) != V2Rules.MEASUREMENT_VERSION:
		return {}
	if not is_equal_approx(float(record.get("elapsed",0)), V2Rules.DURATION):
		return {}
	var shots:Variant = record.get("shots",[])
	if not shots is Array or shots.is_empty() or shots.size() > 12000:
		return {}
	var times:Array = []
	var hits := 0
	var quality := 0.0
	var last := -1.0
	for item in shots:
		if not item is Dictionary:
			return {}
		if typeof(item.get("time")) not in [TYPE_INT,TYPE_FLOAT] or typeof(item.get("hit")) != TYPE_BOOL:
			return {}
		var time := float(item.get("time",-1))
		if not is_finite(time) or time < 0.0 or time >= V2Rules.DURATION or time < last:
			return {}
		last = time
		times.append(time)
		if bool(item.get("hit",false)):
			if typeof(item.get("q")) not in [TYPE_INT,TYPE_FLOAT]:
				return {}
			var q := float(item.get("q",0))
			if not is_finite(q):
				return {}
			hits += 1
			quality += clampf(q,0.0,1.0)
	var q := quality / hits if hits > 0 else 0.0
	var intervals:Array = []
	for i in range(1,times.size()):
		intervals.append(float(times[i]) - float(times[i-1]))
	var mean := 0.0
	for interval in intervals:
		mean += float(interval)
	mean = mean / intervals.size() if not intervals.is_empty() else 0.0
	var variance := 0.0
	for interval in intervals:
		variance += pow(float(interval)-mean,2)
	var sd := sqrt(variance / intervals.size()) if not intervals.is_empty() else 0.0
	var flavor := "一回の60秒測定に記録された撃ち方"
	if times.size() >= V2Rules.FLAVOR_MIN_SHOTS:
		if mean > 0.0 and sd / mean < V2Rules.FLAVOR_STABLE_CV:
			flavor = "一定の間合いで、着実に引き金を引く"
		elif mean > 0.0 and sd / mean >= V2Rules.FLAVOR_BURST_CV:
			flavor = "数発を素早く放ち、一拍置いて狙い直す"
		elif q >= V2Rules.FLAVOR_CAREFUL_Q and times.size() < V2Rules.FLAVOR_CAREFUL_MAX_SHOTS:
			flavor = "間を取りながら、標的の中心を捉える"
		elif times.size() >= V2Rules.FLAVOR_HIGH_SHOTS:
			flavor = "短い間隔で射撃を重ねる"
	return {"weapon":int(record.weapon), "record_id":str(record.record_id), "basic":false, "label":"実測プロフィール", "date":str(record.get("date","")), "rpm":float(times.size()), "p":float(hits)/times.size(), "q":q, "c":V2Rules.CRITICAL_SCALE*q, "timeline":times, "shot_count":times.size(), "hit_count":hits, "interval_mean":mean, "interval_sd":sd, "profile_version":V2Rules.PROFILE_VERSION, "flavor":flavor}

static func current(data:Dictionary, weapon:int)->Dictionary:
	var item:Dictionary = data.profiles[weapon]
	return item.profile.duplicate(true) if not item.is_empty() else basic(weapon)

static func adopt(data:Dictionary, record:Dictionary)->bool:
	var profile := from_record(record)
	if profile.is_empty():
		return false
	var weapon := int(profile.weapon)
	if not data.profiles[weapon].is_empty() and str(data.profiles[weapon].profile.record_id) == str(profile.record_id):
		return false
	data.previous_profiles[weapon] = data.profiles[weapon].duplicate(true)
	data.profiles[weapon] = {"profile":profile, "record":record.duplicate(true)}
	return true

static func revert(data:Dictionary, weapon:int)->bool:
	if not V2Rules.valid_weapon(weapon) or data.previous_profiles[weapon].is_empty():
		return false
	var old:Dictionary = data.profiles[weapon].duplicate(true)
	data.profiles[weapon] = data.previous_profiles[weapon].duplicate(true)
	data.previous_profiles[weapon] = old
	return true

static func unlocked(data:Dictionary, weapon:int)->bool:
	return V2Rules.valid_weapon(weapon) and BigUInt.compare(str(data.get("lifetime_credits","0")),V2Rules.UNLOCK_CREDITS[weapon]) >= 0

static func squad_level(data:Dictionary)->int:
	return 3 if unlocked(data,2) else (2 if unlocked(data,1) else 1)

static func hp(data:Dictionary, weapon:int)->float:
	return V2Rules.BASE_HP * (1.0 + (V2Rules.ARMOR_BONUS if bool(data.armor[weapon]) else 0.0) + V2Rules.PROTECTION_BONUS * int(data.protection[weapon]))

static func purchase(data:Dictionary, weapon:int)->bool:
	if not unlocked(data,weapon):
		return false
	var level := int(data.protection[weapon])
	if level >= V2Rules.PROTECTION_COSTS.size():
		return false
	var cost := str(V2Rules.PROTECTION_COSTS[level])
	if BigUInt.compare(str(data.credits),cost) < 0:
		return false
	data.credits = BigUInt.subtract(str(data.credits),cost)
	data.protection[weapon] = level + 1
	return true

static func set_deployed(data:Dictionary, weapon:int, enabled:bool)->bool:
	if not unlocked(data,weapon):
		return false
	data.deployed[weapon] = enabled
	return true
