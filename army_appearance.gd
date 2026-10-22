class_name ArmyAppearance
extends RefCounted

const TIER_THRESHOLDS := [0, 2, 5, 8]
const STAGE_NAMES := ["基本装備", "ヘルメット装備", "重装備", "強化装甲"]
const STAGE_DESCRIPTIONS := ["軽装と基本火器", "ヘルメットと更新火器", "防具と重火器", "背部装甲・バイザーと長銃身"]
const MAX_BACKGROUND_REPRESENTATIVES := 72

static func tier(level:int)->int:
	if level >= TIER_THRESHOLDS[3]:return 3
	if level >= TIER_THRESHOLDS[2]: return 2
	if level >= TIER_THRESHOLDS[1]: return 1
	return 0

static func next_level(level:int)->int:
	for threshold in TIER_THRESHOLDS:
		if level<threshold:return threshold
	return -1

static func formation_rows(count:int)->int:
	if count<10:return 2
	if count<18:return 3
	if count<30:return 4
	return 6

static func formation_name(count:int)->String:
	return "背景隊列の密度増加" if count>=102 else ("背景隊列の展開" if count>=50 else "%d列の隊列"%formation_rows(count))

static func background_representatives(actual_count:int,foreground_capacity:int)->int:
	return clampi(ceili(float(maxi(0,actual_count-maxi(0,foreground_capacity)))/4.0),0,MAX_BACKGROUND_REPRESENTATIVES)

static func weapon_length(visual_tier:int)->float:
	match clampi(visual_tier,0,3):
		0: return 16.0
		1: return 25.0
		2: return 28.0
		_: return 36.0

static func muzzle_offset(visual_tier:int)->float:
	return 14.0+weapon_length(visual_tier)

static func stage_name(level:int)->String:
	return STAGE_NAMES[tier(level)]

static func description(before_level:int,after_level:int)->String:
	var before:=maxi(0,before_level)
	var after:=maxi(0,after_level)
	var before_tier:=tier(before)
	var after_tier:=tier(after)
	if before == after:
		return "装備Lv%d・%s" % [after,STAGE_NAMES[after_tier]]
	if after_tier > before_tier:
		return "装備Lv%d → Lv%d：%sに更新" % [before,after,STAGE_NAMES[after_tier]]
	if after > before:
		var next_visual_level:=next_level(after)
		if next_visual_level >= 0:
			return "装備Lv%d：戦闘力が上昇。外見更新はLv.%d" % [after,next_visual_level]
		return "装備Lv%d：戦闘力が上昇。%s" % [after,STAGE_DESCRIPTIONS[after_tier]]
	return "装備Lv%d → Lv%d：%s" % [before,after,STAGE_DESCRIPTIONS[after_tier]]

static func draw_soldier(canvas:CanvasItem,pos:Vector2,ally:bool,visual_tier:int,index:int,scale:float=1.0,alpha:float=1.0,silhouette:bool=false)->void:
	var s:=maxf(0.1,scale)
	var tint:=Color(1,1,1,clampf(alpha,0.0,1.0))
	var body:Color=(Color("55c9e8") if ally else Color("e45d68"))*tint
	var shade:Color=(Color("244b5e") if ally else Color("612c38"))*tint
	var skin:=Color("e8c6a0")*tint
	var armor:Color=(Color("8adff0") if ally else Color("f08b91"))*tint
	var gun:Color=Color("9ba9ad")*tint
	if silhouette:
		body=Color("547080")*tint;shade=body;skin=body;armor=body;gun=body
	var gun_length:=weapon_length(visual_tier)
	var gun_x:=14.0 if ally else -gun_length
	if visual_tier>=3:
		canvas.draw_rect(Rect2(pos+Vector2(-7,-12)*s,Vector2(9,22)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(-4,-25)*s,Vector2(23,7)*s),armor)
		canvas.draw_rect(Rect2(pos+Vector2(9,-18)*s,Vector2(10,4)*s),armor if silhouette else Color("ffe0a0")*tint)
	# Stage shapes are deliberately distinct at the small preview scale.
	if visual_tier >= 2:
		canvas.draw_rect(Rect2(pos+Vector2(-2,-21)*s,Vector2(19,14)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(3,-17)*s,Vector2(10,7)*s),skin)
		canvas.draw_rect(Rect2(pos+Vector2(1,-9)*s,Vector2(16,16)*s),armor)
		canvas.draw_rect(Rect2(pos+Vector2(1,7)*s,Vector2(6,12)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(12,7)*s,Vector2(6,12)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(gun_x,-5)*s,Vector2(gun_length*s,6*s)),gun)
		canvas.draw_rect(Rect2(pos+Vector2(gun_x,-8)*s,Vector2(8*s,3*s)),gun if silhouette else Color("d7a854")*tint)
		if visual_tier>=3:
			canvas.draw_rect(Rect2(pos+Vector2(gun_x+20,-10)*s,Vector2(9,5)*s),shade)
			canvas.draw_rect(Rect2(pos+Vector2(gun_x+26,1)*s,Vector2(5,10)*s),gun)
	elif visual_tier == 1:
		canvas.draw_rect(Rect2(pos+Vector2(4,-19)*s,Vector2(10,9)*s),skin)
		canvas.draw_rect(Rect2(pos+Vector2(2,-11)*s,Vector2(14,19)*s),body)
		canvas.draw_rect(Rect2(pos+Vector2(2,8)*s,Vector2(5,11)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(11,8)*s,Vector2(5,11)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(1,-23)*s,Vector2(15,6)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(gun_x,-5)*s,Vector2(gun_length*s,5*s)),gun)
	else:
		canvas.draw_rect(Rect2(pos+Vector2(4,-18)*s,Vector2(10,9)*s),skin)
		canvas.draw_rect(Rect2(pos+Vector2(2,-10)*s,Vector2(14,18)*s),body)
		canvas.draw_rect(Rect2(pos+Vector2(2,8)*s,Vector2(5,11)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(11,8)*s,Vector2(5,11)*s),shade)
		canvas.draw_rect(Rect2(pos+Vector2(gun_x,-5)*s,Vector2(16*s,4*s)),gun)
