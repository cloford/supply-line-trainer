class_name V2Measurement
extends RefCounted

var record:Dictionary = {}
var _sequence := 0
var _closed := false

func begin(weapon:int, settings:Dictionary, seed_value:int, id:String = "")->void:
	_sequence = 0
	_closed = false
	var record_id := id if not id.is_empty() else "%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	record = {"record_id":record_id, "weapon":weapon, "weapon_id":V2Rules.WEAPON_IDS[clampi(weapon,0,2)], "measurement_version":V2Rules.MEASUREMENT_VERSION, "profile_version":V2Rules.PROFILE_VERSION, "date":Time.get_datetime_string_from_system(true), "elapsed":0.0, "conditions":V2Rules.MEASUREMENT_CONDITIONS.duplicate(true), "settings":settings.duplicate(true), "seed":seed_value, "shots":[], "target_events":[], "poses":[], "events":[], "shot_count":0, "hit_count":0, "q_sum":0.0, "completed":false, "interrupted":false, "settings_changed":false, "restored":false, "mode":"measurement"}

func _event(time:float, kind:String, payload:Dictionary)->Dictionary:
	var event := payload.duplicate(true)
	event["time"] = time
	event["type"] = kind
	event["sequence"] = _sequence
	_sequence += 1
	record.events.append(event)
	return event

func shot(time:float, hit:bool, q:float, target_id:Variant, origin:Vector3, direction:Vector3, end:Vector3, burst_id:int = -1, bullet_index:int = 0)->bool:
	if _closed or record.is_empty() or not is_finite(time) or time < 0.0 or time >= V2Rules.DURATION:
		return false
	if record.shots.size() >= 12000:
		return false
	if not record.shots.is_empty() and time < float(record.shots.back().time):
		return false
	var quality := clampf(q,0.0,1.0) if hit and is_finite(q) else 0.0
	var payload := {"hit":hit, "q":quality, "target_id":str(target_id), "origin":vector_array(origin), "direction":vector_array(direction), "end":vector_array(end), "burst_id":burst_id, "bullet_index":bullet_index}
	record.shots.append(_event(time,"shot",payload))
	record.shot_count += 1
	if hit:
		record.hit_count += 1
		record.q_sum += quality
	return true

func target_event(time:float, kind:String, target_id:Variant, state:Dictionary = {})->void:
	if _closed or record.is_empty() or not is_finite(time) or time < 0.0 or time >= V2Rules.DURATION or record.target_events.size() >= 24000:
		return
	record.target_events.append(_event(time,kind,{"target_id":str(target_id), "state":json_value(state)}))

func pose(time:float, origin:Vector3, rotation:Vector3)->void:
	if _closed or record.is_empty() or not is_finite(time) or time < 0.0 or time >= V2Rules.DURATION or record.poses.size() >= 1800:
		return
	if not record.poses.is_empty() and time - float(record.poses.back().time) < 1.0 / 30.0 - 0.000001:
		return
	record.poses.append({"time":time, "origin":vector_array(origin), "rotation":vector_array(rotation)})

func completed(elapsed:float, interrupted:bool = false, settings_changed:bool = false)->Dictionary:
	if record.is_empty():
		return {}
	if _closed:
		return record.duplicate(true)
	_closed = true
	record.elapsed = clampf(elapsed,0.0,V2Rules.DURATION) if is_finite(elapsed) else 0.0
	record.interrupted = interrupted
	record.settings_changed = settings_changed
	record.completed = elapsed >= V2Rules.DURATION and not interrupted and not settings_changed
	record["valid"] = not V2Profiles.from_record(record).is_empty()
	record["invalid_reason"] = "" if record.valid else ("実発射がありません" if int(record.shot_count) == 0 else "60秒の同一条件測定が完了していません")
	return record.duplicate(true)

func snapshot(elapsed:float)->Dictionary:
	var result := record.duplicate(true)
	if not result.is_empty() and not _closed:
		result.elapsed = clampf(elapsed,0.0,V2Rules.DURATION)
	return result

static func vector_array(value:Vector3)->Array:
	return [value.x,value.y,value.z]

static func json_value(value:Variant)->Variant:
	if value is Vector3:
		return vector_array(value)
	if value is Vector2:
		return [value.x,value.y]
	if value is Dictionary:
		var out := {}
		for key in value:
			out[str(key)] = json_value(value[key])
		return out
	if value is Array:
		var out:Array = []
		for item in value:
			out.append(json_value(item))
		return out
	return value
