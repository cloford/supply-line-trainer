class_name GrowthGoal
extends RefCounted

const KEYS := ["recruit","gear"]
const RECRUIT_LEVELS := [1,3,6,11,24]

# Purchase and milestone prices use exactly the same per-purchase rounding.
static func total_cost(data:Dictionary,kind:int,target:int)->String:
	var total:="0"
	for level in range(int(data[KEYS[kind]]),maxi(int(data[KEYS[kind]]),target)):
		total=BigUInt.add(total,BigUInt.from_float(ceil(Balance.recruit_cost(level) if kind==0 else Balance.gear_cost(level))))
	return total

static func milestone(data:Dictionary,kind:int)->int:
	var level:=int(data[KEYS[kind]])
	if kind==1:return ArmyAppearance.next_level(level)
	for threshold in RECRUIT_LEVELS:
		if level<threshold:return threshold
	return -1

static func choose_milestone(data:Dictionary,kind:int)->void:
	var target:=milestone(data,kind)
	if target<0:return
	data.upgrade_goal={"kind":kind,"level":target,"mode":"milestone","notified":false,"achieved_notified":false}
	if missing(data,str(data.credits))=="0":data.upgrade_goal.notified=true

static func is_milestone(data:Dictionary)->bool:return str(data.upgrade_goal.get("mode",""))=="milestone"
static func achieved(data:Dictionary)->bool:return is_milestone(data) and int(data[KEYS[int(data.upgrade_goal.kind)]])>=int(data.upgrade_goal.level)
static func goal_cost(data:Dictionary)->String:
	return total_cost(data,int(data.upgrade_goal.kind),int(data.upgrade_goal.level)) if is_milestone(data) else price(data,int(data.upgrade_goal.kind))

static func effect(kind:int,level:int)->String:
	if kind==1:return ArmyAppearance.STAGE_NAMES[ArmyAppearance.tier(level)]+"：防具・火器と射撃表現が更新（特別能力なし）"
	return ArmyAppearance.formation_name(Balance.soldier_count(level))+"：隊列・射撃参加兵が増加"

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
	if str(goal.get("mode",""))=="milestone":
		var target:=int(goal.get("level",-1))
		if target not in (RECRUIT_LEVELS if kind==0 else ArmyAppearance.TIER_THRESHOLDS.slice(1)):
			choose(data,kind);return
		goal.notified=bool(goal.get("notified",false));goal.achieved_notified=bool(goal.get("achieved_notified",false))
		# Passed stages on load are acknowledged silently, never replayed in bulk.
		if achieved(data):goal.achieved_notified=true
		if missing(data,str(data.credits))=="0":goal.notified=true
		return
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
	return BigUInt.subtract(goal_cost(data),available_points)

static func title(data:Dictionary)->String:
	if is_milestone(data):
		var kind:=int(data.upgrade_goal.kind);var target:=int(data.upgrade_goal.level)
		return ("増員の節目 %d / %d人"%[Balance.soldier_count(int(data.recruit)),Balance.soldier_count(target)]) if kind==0 else ("装備の節目 Lv.%d / %d・%s"%[int(data.gear),target,ArmyAppearance.STAGE_NAMES[ArmyAppearance.tier(target)]])
	if int(data.upgrade_goal.kind)==0:
		return "増員 %d人 → %d人"%[Balance.soldier_count(int(data.recruit)),Balance.soldier_count(int(data.recruit)+1)]
	return "部隊装備 Lv.%d → Lv.%d"%[int(data.gear),int(data.gear)+1]

static func poll(data:Dictionary,available_points:String)->bool:
	if achieved(data):return false
	if bool(data.upgrade_goal.notified) or missing(data,available_points)!="0":return false
	_mark(data);return true

static func _mark(data:Dictionary)->void:
	data.upgrade_goal.notified=true
	var kind:=int(data.upgrade_goal.kind)
	if not is_milestone(data):data.goal_notice_levels[kind]=maxi(int(data.goal_notice_levels[kind]),int(data.upgrade_goal.level))

static func transaction(data:Dictionary,kind:int,batch:int)->Dictionary:
	if kind not in [0,1] or batch not in [1,5,10] or bool(data.get("migration_failed",false)):return {}
	var cost:=total_cost(data,kind,int(data[KEYS[kind]])+batch)
	if BigUInt.compare(str(data.credits),cost)<0:return {}
	var next:=data.duplicate(true)
	next.credits=BigUInt.subtract(str(next.credits),cost)
	next[KEYS[kind]]=int(next[KEYS[kind]])+batch
	if int(next.upgrade_goal.kind)==kind and int(next[KEYS[kind]])>=int(next.upgrade_goal.level):
		if is_milestone(next):next.upgrade_goal.achieved_notified=true
		else:choose(next)
	return next
