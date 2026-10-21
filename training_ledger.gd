class_name TrainingLedger
extends RefCounted

const HISTORY_LIMIT := 200

static func totals()->Dictionary:
	return {"elapsed":0.0,"active":0.0,"sessions":0,"unlimited_elapsed":0.0,"unlimited_active":0.0,"unlimited_sessions":0}

# A cumulative checkpoint is applied as a delta, so saving or finalizing twice
# cannot duplicate credits or elapsed time. All fields persist in one save.
static func checkpoint(data:Dictionary, record:Dictionary)->void:
	if float(record.get("elapsed",0.0))<=0.0:return
	for entry in data.training_history:
		if str(entry.id)==str(record.id):return
	var previous:Dictionary=data.get("active_training",{})
	if previous.is_empty():
		data.practice_totals.sessions+=1
		if int(record.duration)==0:data.practice_totals.unlimited_sessions+=1
	elif str(previous.id)!=str(record.id):
		finish(data,previous,"中断復元")
		checkpoint(data,record)
		return
	var elapsed_delta:=maxf(0.0,float(record.elapsed)-float(previous.get("elapsed",0.0)))
	var active_delta:=maxf(0.0,float(record.active)-float(previous.get("active",0.0)))
	var credit_delta:=maxi(0,int(record.credits)-int(previous.get("credits",0)))
	data.practice_totals.elapsed+=elapsed_delta
	data.practice_totals.active+=active_delta
	if int(record.duration)==0:
		data.practice_totals.unlimited_elapsed+=elapsed_delta
		data.practice_totals.unlimited_active+=active_delta
	data.credits=BigUInt.add(str(data.credits),str(credit_delta))
	data.active_training=record.duplicate(true)

static func finish(data:Dictionary,record:Dictionary,status:String)->void:
	if float(record.get("elapsed",0.0))<=0.0:return
	for entry in data.training_history:
		if str(entry.id)==str(record.id):return
	checkpoint(data,record)
	var entry:=record.duplicate(true)
	entry["status"]=status
	data.training_history.push_front(entry)
	if data.training_history.size()>HISTORY_LIMIT:data.training_history.resize(HISTORY_LIMIT)
	data.active_training={}

static func recover(data:Dictionary)->bool:
	var pending:Dictionary=data.get("active_training",{})
	if pending.is_empty():return false
	finish(data,pending,"中断復元")
	return true
