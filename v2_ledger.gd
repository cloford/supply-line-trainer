class_name V2Ledger
extends RefCounted

static func checkpoint(data:Dictionary, record:Dictionary)->void:
	if float(record.get("elapsed",0.0)) <= 0.0 or str(record.get("id","")) in data.settled_training_ids:
		return
	var previous:Dictionary = data.get("active_training",{})
	if not previous.is_empty() and str(previous.id) != str(record.id):
		finish(data,previous,"中断復元")
	var before := str(data.credits)
	TrainingLedger.checkpoint(data,record)
	var delta := BigUInt.subtract(str(data.credits),before)
	data.lifetime_credits = BigUInt.add(str(data.lifetime_credits),delta)

static func finish(data:Dictionary, record:Dictionary, status:String, measurement:Dictionary = {})->void:
	if float(record.get("elapsed",0.0)) <= 0.0 or str(record.get("id","")) in data.settled_training_ids:
		return
	var final := record.duplicate(true)
	var measured:Dictionary = measurement.duplicate(true) if not measurement.is_empty() else record.get("measurement",{}).duplicate(true)
	if not measured.is_empty():
		if status == "中断復元":
			measured["restored"] = true
			measured["completed"] = false
		final["measurement"] = measured
	checkpoint(data,final)
	TrainingLedger.finish(data,final,status)
	data.settled_training_ids.append(str(record.id))
	if measured.is_empty():
		return
	var profile := V2Profiles.from_record(measured)
	if profile.is_empty() or str(measured.record_id) != str(record.id) or int(measured.weapon) != int(record.weapon):
		return
	var id := str(measured.record_id)
	if id in data.completed_measurement_ids:
		return
	data.completed_measurement_ids.append(id)
	var weapon := int(measured.weapon)
	data.measurement_counts[weapon] = int(data.measurement_counts[weapon]) + 1
	data.armor[weapon] = int(data.measurement_counts[weapon]) >= 3

static func recover(data:Dictionary)->bool:
	var pending:Dictionary = data.get("active_training",{})
	if pending.is_empty():
		return false
	finish(data,pending,"中断復元")
	return true
