class_name Progression
extends RefCounted

const THRESHOLDS := [0,10,100,500,1500]
const WEAPON_IDS := ["handgun","auto_rifle","burst_rifle","marksman_rifle","grenade_launcher"]
const WEAPON_NAMES := ["ハンドガン","アサルトライフル","バーストライフル","マークスマンライフル","グレネードランチャー"]

static func defaults()->Dictionary:
	return {"kills":0,"tracking_seconds":0.0,"total":0,"achievements":{},"seen":[],"preserved_weapons":[],"list_seen":false,"migrated":false}

static func definitions()->Array:
	var result:Array = [{"id":"first_kill","threshold":1,"name":"はじめの一発","description":"最初の標的を撃破した","kind":"kill"},{"id":"five_progress","threshold":5,"name":"次の一歩","description":"撃破・追従達成が累計5に到達した","kind":"total"}]
	for weapon in range(1,5):
		result.append({"id":"unlock_" + WEAPON_IDS[weapon],"threshold":THRESHOLDS[weapon],"name":WEAPON_NAMES[weapon] + "解放","description":"新しい武器で練習できる","kind":"weapon","weapon":weapon})
	return result

static func valid(value:Variant)->bool:
	if not value is Dictionary:
		return false
	for key in ["kills","total"]:
		if not _number(value.get(key)) or float(value[key]) != floor(float(value[key])):
			return false
	if not _number(value.get("tracking_seconds")) or int(value.total) != int(value.kills) + int(floor(float(value.tracking_seconds) + 0.000000001)):
		return false
	if not value.get("achievements") is Dictionary or not value.get("seen") is Array or not value.get("preserved_weapons") is Array or typeof(value.get("list_seen")) != TYPE_BOOL or typeof(value.get("migrated")) != TYPE_BOOL:
		return false
	var ids:Array = []
	for item in definitions():
		ids.append(item.id)
	for id in value.achievements:
		if id not in ids or not value.achievements[id] is String or str(value.achievements[id]).is_empty():
			return false
	for id in value.seen:
		if id not in ids or not value.achievements.has(id):
			return false
	for weapon in value.preserved_weapons:
		if not _number(weapon) or float(weapon) != floor(float(weapon)) or int(weapon) not in [0,1,2]:
			return false
	return true

static func _number(value:Variant)->bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0

static func total(data:Dictionary)->int:
	return int(data.get("progression",{}).get("total",0))

static func unlocked(data:Dictionary, weapon:int)->bool:
	if weapon < 0 or weapon >= 5:
		return false
	if total(data) >= THRESHOLDS[weapon]:
		return true
	# JSON復元では数値がfloatになる。Array.has/inの型一致に依存しない。
	for preserved in data.get("progression",{}).get("preserved_weapons",[]):
		if _number(preserved) and float(preserved) == float(weapon):
			return true
	return false

static func list_visible(data:Dictionary)->bool:
	return total(data) >= 5 or bool(data.get("progression",{}).get("list_seen",false))

static func weapon_rows(data:Dictionary)->Array:
	var rows:Array = []
	var next_added := false
	for weapon in 5:
		var available := unlocked(data,weapon)
		if not available and next_added:
			continue
		rows.append({"weapon":weapon,"id":weapon,"weapon_id":WEAPON_IDS[weapon],"name":WEAPON_NAMES[weapon] if available else "???","unlocked":available,"threshold":THRESHOLDS[weapon],"current":total(data),"remaining":maxi(0,THRESHOLDS[weapon]-total(data)),"icon":WEAPON_IDS[weapon] if available else "silhouette"})
		if not available:
			next_added = true
	return rows

static func pending_notifications(data:Dictionary)->Array:
	var result:Array = []
	var state:Dictionary = data.get("progression",{})
	for item in definitions():
		if state.get("achievements",{}).has(item.id) and item.id not in state.get("seen",[]):
			var entry:Dictionary = item.duplicate(true)
			entry["title"] = item.name
			entry["unlocked_at"] = state.achievements[item.id]
			result.append(entry)
	return result

static func achievements(data:Dictionary)->Array:
	var result := definitions()
	var unlocked_items:Dictionary = data.get("progression",{}).get("achievements",{})
	for item in result:
		item["title"] = item.name
		item["unlocked"] = unlocked_items.has(item.id)
		item["unlocked_at"] = str(unlocked_items.get(item.id,""))
	return result

static func mark_seen(data:Dictionary, id:String)->void:
	var state:Dictionary = data.get("progression",{})
	if state.get("achievements",{}).has(id) and id not in state.seen:
		state.seen.append(id)

static func mark_list_seen(data:Dictionary)->void:
	data.progression.list_seen = true

static func _evaluate(data:Dictionary, silent:bool = false)->void:
	var state:Dictionary = data.progression
	state.total = int(state.kills) + int(floor(float(state.tracking_seconds) + 0.000000001))
	for item in definitions():
		var achieved:bool = int(state.kills) >= int(item.threshold) if item.kind == "kill" else (unlocked(data,int(item.weapon)) if item.kind == "weapon" else total(data) >= int(item.threshold))
		if achieved and not state.achievements.has(item.id):
			state.achievements[item.id] = Time.get_datetime_string_from_system(true)
			if silent:
				mark_seen(data,item.id)

# 累計入力のみ。ARの撃破と追従を重ねない。測定は有効確定時にprevious={}で呼ぶ。
static func apply_record(data:Dictionary, record:Dictionary, previous:Dictionary = {})->void:
	if bool(record.get("progress_excluded",false)) or str(record.get("mode","")) in ["replay","preview","demo","battle","test_fire"]:
		return
	var weapon := int(record.get("weapon",-1))
	if weapon < 0 or weapon > 4:
		return
	if not data.has("progression"):
		migrate(data)
	if weapon == 1:
		var value:Variant = record.get("progress_tracking_seconds",0.0)
		if _number(value):
			data.progression.tracking_seconds += maxf(0.0,float(value)-float(previous.get("progress_tracking_seconds",0.0)))
	else:
		var value:Variant = record.get("progress_kills",0)
		if _number(value) and float(value) == floor(float(value)):
			data.progression.kills += maxi(0,int(value)-int(previous.get("progress_kills",0)))
	_evaluate(data)

# 過去の各記録IDは一度だけ。利用事実と生の撃破/有効追従だけを引き継ぐ。
static func migrate(data:Dictionary)->bool:
	if data.has("progression"):
		return false
	data.progression = defaults()
	data.progression.migrated = true
	var unique := {}
	var entries:Array = data.get("training_history",[]).duplicate(true)
	var active:Dictionary = data.get("active_training",{})
	if not active.is_empty():
		entries.append(active)
	for entry in entries:
		if not entry is Dictionary or str(entry.get("id","")).is_empty() or unique.has(str(entry.id)):
			continue
		unique[str(entry.id)] = true
		if bool(entry.get("progress_excluded",false)) or str(entry.get("mode","")) in ["replay","preview","demo","battle","test_fire"] or float(entry.get("elapsed",0.0)) <= 0.0:
			continue
		var weapon := int(entry.get("weapon",-1))
		if weapon < 0 or weapon > 2:
			continue
		if weapon not in data.progression.preserved_weapons:
			data.progression.preserved_weapons.append(weapon)
		if entry.has("measurement") or bool(entry.get("progress_measurement",false)):
			var measured:Dictionary = entry.get("measurement",{})
			if V2Profiles.from_record(measured).is_empty() or str(measured.get("record_id","")) != str(entry.id) or int(measured.get("weapon",-1)) != weapon:
				continue
		var raw:Dictionary = entry.get("stats",entry.get("metrics",{}))
		var key := "track_time" if weapon == 1 else "kills"
		var value:Variant = raw.get(key)
		if _number(value):
			if weapon == 1:
				data.progression.tracking_seconds += float(value)
			elif float(value) == floor(float(value)):
				data.progression.kills += int(value)
		# 復旧checkpointが移行済みactiveを再計上しない累計基準。
		if not active.is_empty() and str(active.get("id","")) == str(entry.id):
			active["progress_kills"] = int(raw.get("kills",0)) if _number(raw.get("kills")) else 0
			active["progress_tracking_seconds"] = float(raw.get("track_time",0.0)) if _number(raw.get("track_time")) else 0.0
	for key in ["profiles","previous_profiles"]:
		var bundles:Array = data.get(key,[])
		for weapon in mini(3,bundles.size()):
			if bundles[weapon] is Dictionary and not bundles[weapon].is_empty() and weapon not in data.progression.preserved_weapons:
				data.progression.preserved_weapons.append(weapon)
	for weapon in mini(3,data.get("measurement_counts",[]).size()):
		if int(data.measurement_counts[weapon]) > 0 and weapon not in data.progression.preserved_weapons:
			data.progression.preserved_weapons.append(weapon)
	_evaluate(data,true)
	data.progression.list_seen = not data.progression.preserved_weapons.is_empty() or total(data) >= 5
	return true
