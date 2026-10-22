class_name GrowthGoal
extends RefCounted

const KEYS := ["recruit","gear"]

static func price(data:Dictionary,kind:int)->String:
	return BigUInt.from_float(ceil(Balance.recruit_cost(int(data.recruit)) if kind==0 else Balance.gear_cost(int(data.gear))))

static func choose(data:Dictionary,kind:int=-1)->void:
	if kind not in [0,1]:kind=0 if BigUInt.compare(price(data,0),price(data,1))<=0 else 1
	data.upgrade_goal={"kind":kind,"level":int(data[KEYS[kind]])+1,"notified":false}
	# A newly selected goal already affordable is shown ready without a startup fanfare.
	if BigUInt.compare(str(data.credits),price(data,kind))>=0:_mark(data)
	elif int(data.goal_notice_levels[kind])>=int(data.upgrade_goal.level):data.upgrade_goal.notified=true

static func ensure(data:Dictionary)->void:
	if typeof(data.get("goal_notice_levels"))!=TYPE_ARRAY or data.goal_notice_levels.size()!=2:data.goal_notice_levels=[0,0]
	var goal:Variant=data.get("upgrade_goal",{})
	if not goal is Dictionary or int(goal.get("kind",-1)) not in [0,1]:choose(data);return
	var kind:=int(goal.kind)
	if int(goal.get("level",0))!=int(data[KEYS[kind]])+1:choose(data);return
	goal.notified=bool(goal.get("notified",false)) or int(data.goal_notice_levels[kind])>=int(goal.level)
	if BigUInt.compare(str(data.credits),price(data,kind))>=0:_mark(data)

static func available(data:Dictionary,record:Dictionary={})->String:
	var pending:=0
	if not record.is_empty():
		var applied:Dictionary=data.get("active_training",{})
		var credited:=int(applied.get("credits",0)) if str(applied.get("id",""))==str(record.get("id","")) else 0
		pending=maxi(0,int(record.get("credits",0))-credited)
	return BigUInt.add(str(data.credits),str(pending))

static func missing(data:Dictionary,available_points:String)->String:
	return BigUInt.subtract(price(data,int(data.upgrade_goal.kind)),available_points)

static func title(data:Dictionary)->String:
	if int(data.upgrade_goal.kind)==0:
		return "増員 %d人 → %d人"%[Balance.soldier_count(int(data.recruit)),Balance.soldier_count(int(data.recruit)+1)]
	return "部隊装備 Lv.%d → Lv.%d"%[int(data.gear),int(data.gear)+1]

static func poll(data:Dictionary,available_points:String)->bool:
	if bool(data.upgrade_goal.notified) or missing(data,available_points)!="0":return false
	_mark(data);return true

static func _mark(data:Dictionary)->void:
	data.upgrade_goal.notified=true
	var kind:=int(data.upgrade_goal.kind)
	data.goal_notice_levels[kind]=maxi(int(data.goal_notice_levels[kind]),int(data.upgrade_goal.level))

static func transaction(data:Dictionary,kind:int,batch:int)->Dictionary:
	if kind not in [0,1] or batch not in [1,5,10] or bool(data.get("migration_failed",false)):return {}
	var cost:="0"
	for offset in batch:
		var amount:=Balance.recruit_cost(int(data.recruit)+offset) if kind==0 else Balance.gear_cost(int(data.gear)+offset)
		cost=BigUInt.add(cost,BigUInt.from_float(ceil(amount)))
	if BigUInt.compare(str(data.credits),cost)<0:return {}
	var next:=data.duplicate(true)
	next.credits=BigUInt.subtract(str(next.credits),cost)
	next[KEYS[kind]]=int(next[KEYS[kind]])+batch
	if int(next.upgrade_goal.kind)==kind and int(next[KEYS[kind]])>=int(next.upgrade_goal.level):choose(next)
	return next
