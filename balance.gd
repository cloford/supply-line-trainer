class_name Balance
extends RefCounted

const TRAINING_DURATIONS := [0]
const POINT_WEIGHTS := [0.105,0.05,0.075]
const SCORING_VERSION := 4
const DIFFICULTY := [
	{"name":"初級","radius":0.62,"speed":2.3,"range":5.0,"reward":1.00,"description":"大きい的・狭い範囲・低速"},
	{"name":"中級","radius":0.46,"speed":3.4,"range":6.5,"reward":1.08,"description":"標準サイズ・標準範囲・中速"},
	{"name":"上級","radius":0.34,"speed":4.6,"range":8.0,"reward":1.16,"description":"小さい的・広い範囲・高速"}
]
const WEAPONS := ["ハンドガン","オートライフル","バーストライフル"]
const FRONT_HP := [70.0,110.0,165.0,240.0,340.0,470.0,640.0,850.0,1100.0,1400.0,1760.0,2180.0]
const FRONT_NAMES := ["外縁ゲート","通信塔","資材集積所","峡谷監視所","中継基地","防空陣地","軌道倉庫","精製区画","中央要塞","司令区画","最終防壁","中枢制圧"]
const SENSITIVITY_PRESETS := [
	{"name":"CS:GO","coefficient":0.022,"official":true},
	{"name":"VALORANT","coefficient":0.07,"official":false},
	{"name":"Apex Legends","coefficient":0.022,"official":false}
]
const COMMANDER_ITEMS := [
	{"id":"radio_assault","slot":0,"name":"戦術通信機","cost":260,"combat":1.10,"description":"部隊の連携を改善：戦闘力×1.10"},
	{"id":"tablet_tactical","slot":1,"name":"戦術端末","cost":520,"combat":1.14,"description":"射撃指示を高速化：戦闘力×1.14"},
	{"id":"supply_front","slot":2,"name":"前線補給装置","cost":850,"combat":1.18,"description":"前線維持を強化：戦闘力×1.18"}
]

static func recruit_cost(level:int)->float:return 70.0+level*24.0+floor(level/10.0)*45.0
static func gear_cost(level:int)->float:return 120.0+level*85.0
static func soldier_count(level:int)->int:return 6+maxi(0,level)*4
static func soldier_display_count(level:int)->int:return clampi(soldier_count(level),6,42)
static func gear_multiplier(level:int)->float:return 1.0+level*0.16
static func commander_multiplier(equipped:Array)->float:
	var result:=1.0
	for id in equipped:
		for item in COMMANDER_ITEMS:
			if str(id)==item.id:result*=float(item.combat)
	return result
static func combat_power(recruit:int,gear:int,equipped:Array=[])->float:
	return soldier_count(recruit)*gear_multiplier(gear)*commander_multiplier(equipped)
static func front_hp(front:int)->float:
	if front<FRONT_HP.size():return FRONT_HP[front]
	var extra:=front-FRONT_HP.size()+1
	return FRONT_HP[-1]+extra*260.0+pow(float(extra),1.35)*45.0
static func front_name(front:int)->String:
	if front<FRONT_NAMES.size():return FRONT_NAMES[front]
	return "継続戦線 %d-%d"%[int((front-12)/10)+1,(front-12)%10+1]
static func visual_tier(level:int)->int:
	if level>=5:return 2
	if level>=2:return 1
	return 0
static func format_number(value:float)->String:
	if value<10000.0:return "%d"%int(value)
	var units:=[{"e":20,"u":"垓"},{"e":16,"u":"京"},{"e":12,"u":"兆"},{"e":8,"u":"億"},{"e":4,"u":"万"}]
	for unit in units:
		if value>=pow(10.0,unit.e):return "%.2f%s"%[value/pow(10.0,unit.e),unit.u]
	return "%.3e"%value
static func format_soldiers(level:int)->String:
	return "%d人"%soldier_count(level)
static func cm_per_360(preset:int,sensitivity:float,dpi:float)->float:
	return 914.4/maxf(0.001,dpi*effective_coefficient(preset)*sensitivity)
static func effective_coefficient(preset:int)->float:return float(SENSITIVITY_PRESETS[clampi(preset,0,2)].coefficient)

static func duration_label(seconds:int)->String:
	return "時間無制限" if seconds==0 else "%d秒"%seconds

static func clock_text(seconds:float)->String:
	var value:=maxi(0,int(seconds))
	return "%02d:%02d:%02d"%[value/3600,(value/60)%60,value%60]

static func battle_dps(recruit:int,gear:int,equipped:Array)->float:
	return combat_power(recruit,gear,equipped)*0.18

static func eta_text(hp:float,dps:float,running:bool)->String:
	if not running:return "停止中"
	if not is_finite(hp) or not is_finite(dps) or dps<=0:return "計算中"
	var seconds:=ceili(maxf(0.0,hp)/dps)
	return "約%d分%02d秒"%[seconds/60,seconds%60]

static func center_precision(origin:Vector3,direction:Vector3,center:Vector3,radius:float)->float:
	var ray:=direction.normalized()
	var offset:=center-origin
	var perpendicular:=offset-ray*offset.dot(ray)
	return pow(1.0-clampf(perpendicular.length()/maxf(radius,0.001),0.0,1.0),1.5)

static func score_and_reward(weapon:int,difficulty:int,stats:Dictionary,_front:int,_duration:int,_elapsed:float,carry:float=0.0)->Dictionary:
	var base_points:=maxf(0.0,float(stats.get("base_points",0.0)))
	var center_bonus:=clampf(float(stats.get("center_bonus",0.0)),0.0,base_points)
	var speed_raw:=maxf(0.0,float(stats.get("speed_bonus",0.0)))
	var streak_raw:=maxf(0.0,float(stats.get("streak_bonus",0.0)))
	var other_scale:=minf(1.0,base_points*0.2/maxf(0.001,speed_raw+streak_raw))
	var speed_bonus:=speed_raw*other_scale
	var streak_bonus:=streak_raw*other_scale
	# 武器ごとの得点頻度を補正し、表示・獲得・購入に使うポイントを統一する。
	var weight:=float(POINT_WEIGHTS[clampi(weapon,0,2)])*float(DIFFICULTY[clampi(difficulty,0,2)].reward)
	var exact_score:=(base_points+center_bonus+speed_bonus+streak_bonus)*weight
	var carried:=clampf(carry,0.0,0.999999999)
	var cumulative:=exact_score+carried
	var score:=int(floor(cumulative+0.000000001))
	var fraction:=clampf(cumulative-float(score),0.0,0.999999999)
	var center:=int(floor(center_bonus*weight))
	var speed:=int(floor(speed_bonus*weight))
	var combo:=int(floor(streak_bonus*weight))
	# 端数は基本点へ配分し、内訳の和と上限を整数でも維持する。
	var base:=score-center-speed-combo
	var accuracy:=float(stats.get("hits",0))/maxf(1.0,float(stats.get("shots",0))) if weapon!=1 else float(stats.get("track_time",0.0))/maxf(0.001,float(stats.get("fire_time",0.0)))
	return {"score":score,"supply":score,"accuracy":clampf(accuracy,0.0,1.0),"base":base,"center":center,"speed":speed,"streak":combo,"duration":0,"fraction":fraction,"exact_points":exact_score}
