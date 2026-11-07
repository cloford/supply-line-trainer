class_name TargetScoring
extends RefCounted

# 自由練習だけの共通配点。測定と爆風には適用しない。
const VERSION := 5
const DEFAULT_RISK := 0.5
static func safe_risk(value:Variant)->float:
	return clampf(float(value),0.0,1.0) if typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) else DEFAULT_RISK

static func reward_factor(q:float,risk:float = DEFAULT_RISK)->float:
	var r := safe_risk(risk)
	var edge := lerpf(1.3,1.0,r*2.0) if r <= 0.5 else lerpf(1.0,0.15,(r-0.5)*2.0)
	var center := lerpf(3.0,4.2,r*2.0) if r <= 0.5 else lerpf(4.2,6.0,(r-0.5)*2.0)
	return edge + (center-edge)*pow(clampf(q,0.0,1.0),lerpf(1.2,6.0,r))

static func preview_points(q:float,risk:float = DEFAULT_RISK)->float:
	return 45.0*float(Balance.POINT_WEIGHTS[0])*reward_factor(q,risk)

static func score(weapon:int,difficulty:int,stats:Dictionary,carry:float)->Dictionary:
	var base := maxf(0.0,float(stats.get("base_points",0.0)))
	var center := float(stats.get("center_bonus",0.0))
	var speed := maxf(0.0,float(stats.get("speed_bonus",0.0)))
	var streak := maxf(0.0,float(stats.get("streak_bonus",0.0)))
	var scale := minf(1.0,base*0.2/maxf(0.001,speed+streak))
	speed *= scale
	streak *= scale
	var weight := float(Balance.POINT_WEIGHTS[clampi(weapon,0,2)])*float(Balance.DIFFICULTY[clampi(difficulty,0,2)].reward)
	var exact := maxf(0.0,(base+center+speed+streak)*weight)
	var cumulative := exact+clampf(carry,0.0,0.999999999)
	var total := int(floor(cumulative+0.000000001))
	var c := int(floor(center*weight))
	var s := int(floor(speed*weight))
	var t := int(floor(streak*weight))
	var accuracy := float(stats.get("hits",0))/maxf(1.0,float(stats.get("shots",0))) if weapon != 1 else float(stats.get("track_time",0.0))/maxf(0.001,float(stats.get("fire_time",0.0)))
	return {"score":total,"supply":total,"accuracy":clampf(accuracy,0.0,1.0),"base":total-c-s-t,"center":c,"speed":s,"streak":t,"duration":0,"fraction":clampf(cumulative-float(total),0.0,0.999999999),"exact_points":exact}
