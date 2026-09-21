class_name Balance
extends RefCounted

const TRAINING_DURATIONS := [30,60]
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
	{"id":"radio_assault","slot":0,"name":"突撃通信機","cost":420,"combat":1.12,"income":1.00},
	{"id":"radio_logistics","slot":0,"name":"兵站通信機","cost":420,"combat":1.00,"income":1.12},
	{"id":"tablet_tactical","slot":1,"name":"戦術端末","cost":760,"combat":1.18,"income":1.00},
	{"id":"tablet_economy","slot":1,"name":"需給端末","cost":760,"combat":1.00,"income":1.18},
	{"id":"supply_front","slot":2,"name":"前線補給装置","cost":1250,"combat":1.25,"income":1.00},
	{"id":"supply_auto","slot":2,"name":"自動補給装置","cost":1250,"combat":1.00,"income":1.25}
]

static func recruit_cost(level:int)->float:return 85.0*pow(1.48,min(level,160))
static func gear_cost(level:int)->float:return 110.0*pow(1.56,min(level,150))
static func depot_cost(level:int)->float:return 140.0*pow(1.62,min(level,140))
static func soldier_log10(level:int)->float:
	if level<=10:return log(6.0+level*2.0)/log(10.0)
	return log(26.0)/log(10.0)+(level-10)*0.52
static func soldier_display_count(level:int)->int:return clampi(6+level*2,6,48)
static func gear_multiplier(level:int)->float:return 1.0+level*0.22
static func commander_multiplier(equipped:Array,effect:String)->float:
	var result:=1.0
	for id in equipped:
		for item in COMMANDER_ITEMS:
			if str(id)==item.id:result*=float(item[effect])
	return result
static func combat_power(recruit:int,gear:int,equipped:Array=[])->float:
	return pow(10.0,minf(soldier_log10(recruit),290.0))*gear_multiplier(gear)*commander_multiplier(equipped,"combat")
static func passive_rate(depot:int,equipped:Array=[])->float:return (0.08+depot*0.12)*commander_multiplier(equipped,"income")
static func offline_cap(front:int)->float:return minf(1.0e290,(150.0+front*28.0)*pow(1.08,maxi(0,front-11)))
static func front_hp(front:int)->float:
	if front<FRONT_HP.size():return FRONT_HP[front]
	var cycle:=front-FRONT_HP.size()+1
	return minf(1.0e290,FRONT_HP[-1]*pow(1.24,cycle)*(1.0+floor(cycle/10.0)*0.18))
static func front_name(front:int)->String:
	if front<FRONT_NAMES.size():return FRONT_NAMES[front]
	return "継続戦線 %d-%d"%[int((front-12)/10)+1,(front-12)%10+1]
static func visual_tier(level:int)->int:
	if level>=5:return 2
	if level>=2:return 1
	return 0
static func scale_tier(recruit:int)->int:
	var exponent:=int(floor(soldier_log10(recruit)))
	if exponent>=18:return 5
	if exponent>=15:return 4
	if exponent>=11:return 3
	if exponent>=8:return 2
	if exponent>=2:return 1
	return 0
static func format_number(value:float)->String:
	if value<10000.0:return "%d"%int(value)
	var units:=[{"e":20,"u":"垓"},{"e":16,"u":"京"},{"e":12,"u":"兆"},{"e":8,"u":"億"},{"e":4,"u":"万"}]
	for unit in units:
		if value>=pow(10.0,unit.e):return "%.2f%s"%[value/pow(10.0,unit.e),unit.u]
	return "%.3e"%value
static func format_soldiers(level:int)->String:
	var logv:=soldier_log10(level)
	if logv<15.0:return format_number(pow(10.0,logv))
	var exponent:=int(floor(logv));var mantissa:=pow(10.0,logv-exponent)
	if exponent<20:return "%.2f京"%[mantissa*pow(10.0,exponent-16)]
	return "%.2f×10^%d"%[mantissa,exponent]
static func cm_per_360(preset:int,sensitivity:float,dpi:float)->float:
	return 914.4/maxf(0.001,dpi*effective_coefficient(preset)*sensitivity)
static func effective_coefficient(preset:int)->float:return float(SENSITIVITY_PRESETS[clampi(preset,0,2)].coefficient)

static func score_and_reward(weapon:int,difficulty:int,stats:Dictionary,front:int,duration:int,elapsed:float)->Dictionary:
	var base_points:=float(stats.get("base_points",0.0))
	var center_bonus:=float(stats.get("center_bonus",0.0))
	var speed_bonus:=float(stats.get("speed_bonus",0.0))
	var streak_bonus:=float(stats.get("streak_bonus",0.0))
	var bonus:=minf(center_bonus+speed_bonus+streak_bonus,base_points*0.45)
	var score:=int(round(base_points+bonus))
	var accuracy:=float(stats.hits)/maxf(1.0,float(stats.shots)) if weapon!=1 else float(stats.track_time)/maxf(0.001,float(stats.fire_time))
	var minutes:=maxf(0.0,elapsed)/60.0
	var skill_rate:=clampf(float(score)/maxf(1.0,1000.0*maxf(minutes,0.1)),0.15,2.2)
	var credits:=int(round(105.0*minutes*(0.72+0.28*skill_rate)*float(DIFFICULTY[difficulty].reward)*(1.0+min(front,40)*0.012)))
	return {"score":maxi(0,score),"supply":maxi(0,credits),"accuracy":accuracy,"base":int(base_points),"center":int(center_bonus),"speed":int(speed_bonus),"streak":int(streak_bonus),"duration":duration}
