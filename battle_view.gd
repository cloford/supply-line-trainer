class_name BattleView
extends Control

const MAX_ALLIES := 48
const MAX_BACKGROUND := 72
const MAX_REINFORCEMENTS := 12
const MAX_FIRE_EFFECTS := 10
const FIRE_INTERVAL := 0.34
const FIRE_DURATION := 0.08
const REINFORCEMENT_DURATION := 1.0
const GEAR_UPDATE_DURATION := 0.72

var state := {"soldiers":6,"soldier_label":"6人","gear":0,"front":0,"enemy_hp":70.0,"enemy_max":70.0,"running":true}
var anim_time := 0.0
var march := 1.0
var last_front := -1
var defeated := 0
var damage_age := 99.0
var hit_pulse := 0.0
var world_scroll := 0.0
var fallen:Array[Dictionary] = []
var recruit_joins:Array[Dictionary] = []
var reinforcement_wave:Array[Dictionary] = []
var reinforcement_serial:=0
var gear_update_age := GEAR_UPDATE_DURATION
var gear_update_text := ""
var gear_update_from := 0
var gear_update_to := 0

func _ready()->void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	set_process(true)

func set_state(next:Dictionary)->void:
	var next_front := int(next.get("front",0))
	if last_front >= 0 and next_front != last_front:
		for index in range(defeated,5): fallen.append({"index":index,"life":0.7})
		march = 0.0
		defeated = 0
	elif next_front == last_front:
		var next_defeated:=clampi(int((1.0-float(next.get("enemy_hp",state.enemy_hp))/maxf(0.001,float(next.get("enemy_max",state.enemy_max))))*5.0),0,4)
		for index in range(defeated,next_defeated): fallen.append({"index":index,"life":0.7})
		defeated=next_defeated
		if float(next.get("enemy_hp",state.enemy_hp)) < float(state.enemy_hp) and damage_age >= 0.22:
			hit_pulse=0.13
			damage_age=0.0
	else:
		defeated=clampi(int((1.0-float(next.get("enemy_hp",70.0))/maxf(0.001,float(next.get("enemy_max",70.0))))*5.0),0,4)
	last_front = next_front
	state = next.duplicate()
	queue_redraw()

func play_purchase(kind:int,before:Dictionary,after:Dictionary)->void:
	var before_soldiers:=maxi(0,int(before.get("soldiers",0)))
	var after_soldiers:=maxi(0,int(after.get("soldiers",0)))
	if kind == 0 and after_soldiers > before_soldiers:
		var first_visible:=mini(before_soldiers,MAX_ALLIES)
		var final_visible:=mini(after_soldiers,MAX_ALLIES)
		for index in range(first_visible,final_visible):
			if recruit_joins.size()<MAX_ALLIES:
				recruit_joins.append({"index":index,"age":0.0})
		if before_soldiers < MAX_ALLIES and after_soldiers > MAX_ALLIES:
			_add_reinforcement_wave(after_soldiers-MAX_ALLIES)
		elif before_soldiers >= MAX_ALLIES and after_soldiers > before_soldiers:
			_add_reinforcement_wave(after_soldiers-before_soldiers)
		state.soldiers=after_soldiers
	elif kind == 1:
		var from_level:=int(before.get("gear",0))
		var to_level:=int(after.get("gear",from_level))
		if to_level == from_level:return
		gear_update_from=from_level
		gear_update_to=to_level
		gear_update_text=ArmyAppearance.description(from_level,to_level)
		gear_update_age=0.0
		state.gear=to_level
	queue_redraw()

func _add_reinforcement_wave(count:int)->void:
	var added:=mini(count,MAX_REINFORCEMENTS)
	while reinforcement_wave.size()+added>MAX_REINFORCEMENTS:reinforcement_wave.pop_front()
	for index in added:
		reinforcement_wave.append({"index":reinforcement_serial%MAX_REINFORCEMENTS,"age":0.0})
		reinforcement_serial+=1

func visible_soldiers(count:int)->int:
	return clampi(count,0,MAX_ALLIES)

func background_soldiers(count:int)->int:
	return ArmyAppearance.background_representatives(count,MAX_ALLIES)

func fire_effect_count(ally_count:int)->int:
	if not bool(state.get("running",state.get("active",true))) or damage_age>0.48 or float(state.get("enemy_hp",0.0))<=0.0 or march<0.98:return 0
	var visible:=visible_soldiers(ally_count)
	if visible<=0:return 0
	return mini(visible,clampi(int(ceil(float(visible)/5.0)),1,MAX_FIRE_EFFECTS))

static func fire_participants_for_cycle(cycle:int,ally_count:int,effect_count:int)->Array[int]:
	var participants:Array[int]=[]
	if ally_count<=0:return participants
	var bounded_count:=clampi(effect_count,0,mini(ally_count,MAX_FIRE_EFFECTS))
	for shot in bounded_count: participants.append(posmod(cycle*bounded_count+shot,ally_count))
	return participants

func _process(delta:float)->void:
	if not is_visible_in_tree():return
	if not bool(state.get("running",state.get("active",true))):
		hit_pulse=0.0
		damage_age=99.0
		queue_redraw()
		return
	anim_time += delta
	damage_age+=delta
	hit_pulse=maxf(0.0,hit_pulse-delta)
	if march<1.0:world_scroll+=delta*120.0
	march=minf(1.0,march+delta*0.9)
	for index in range(fallen.size()-1,-1,-1):
		fallen[index].life=float(fallen[index].life)-delta
		if float(fallen[index].life)<=0:fallen.remove_at(index)
	_advance_effects(recruit_joins,delta)
	_advance_effects(reinforcement_wave,delta)
	gear_update_age=minf(GEAR_UPDATE_DURATION,gear_update_age+delta)
	queue_redraw()

func _advance_effects(effects:Array[Dictionary],delta:float)->void:
	for index in range(effects.size()-1,-1,-1):
		effects[index].age=float(effects[index].age)+delta
		if float(effects[index].age)>=REINFORCEMENT_DURATION:effects.remove_at(index)

func _draw()->void:
	var w:=size.x
	var h:=size.y
	if w<20 or h<20:return
	draw_rect(Rect2(Vector2.ZERO,size),Color("08131c"))
	var horizon:=h*0.44
	draw_rect(Rect2(0,horizon,w,h-horizon),Color("172633"))
	for i in 9:
		var stripe_x:=fposmod(float(i)*150.0-world_scroll,w+150.0)-75.0
		draw_line(Vector2(stripe_x,horizon),Vector2(stripe_x-95,h),Color("284151"),2.0)
	for i in 7:
		var building_x:=fposmod(float(i)*190.0-world_scroll*0.3,w+200.0)-100.0
		draw_rect(Rect2(building_x,horizon-55-(i%2)*22,62,55+(i%2)*22),Color("10232e"))
	var actual_count:=maxi(0,int(state.get("soldiers",0)))
	var ally_count:=visible_soldiers(actual_count)
	var contact_x:=w*0.58
	var group_x:=lerpf(w*0.22,contact_x,march)
	var gear_tier:=ArmyAppearance.tier(int(state.get("gear",0)))
	var background_count:=background_soldiers(actual_count)
	for i in background_count:
		var row:=i%8
		var col:=i/8
		var bg_pos:=Vector2(group_x-30.0-col*13.0,horizon+22.0+row*13.0)
		ArmyAppearance.draw_soldier(self,bg_pos,true,gear_tier,i,0.42,0.46)
	var ally_positions:Array[Vector2]=[]
	for i in ally_count:
		var row:=i%6
		var col:=i/6
		var soldier_pos:=Vector2(group_x-col*24.0,horizon+45+row*27.0)
		ally_positions.append(soldier_pos)
	var combat_active:=bool(state.get("running",state.get("active",true))) and damage_age<=0.48 and float(state.get("enemy_hp",0.0))>0.0
	var firing_count:=fire_effect_count(ally_count)
	var fire_cycle:=int(floor(anim_time/FIRE_INTERVAL))
	if gear_tier==2 and fire_cycle%8==0:firing_count=mini(firing_count,MAX_FIRE_EFFECTS-3)
	var visible_duration:=FIRE_DURATION/FIRE_INTERVAL
	var cycle_phase:=fposmod(anim_time,FIRE_INTERVAL)/FIRE_INTERVAL
	var participants:=fire_participants_for_cycle(fire_cycle,ally_count,firing_count)
	for i in ally_count:
		var recoil:=0.0
		var gear_motion:=0.0
		if gear_update_age<GEAR_UPDATE_DURATION:gear_motion=sin(gear_update_age/GEAR_UPDATE_DURATION*PI*3.0+float(i%3)*0.25)*2.0
		var volley:=gear_tier==2 and fire_cycle%8==0 and i<mini(3,firing_count) and cycle_phase<visible_duration
		if volley:recoil=2.0*(1.0-cycle_phase/visible_duration)
		if firing_count>0:
			for shot in firing_count:
				var shot_phase:=cycle_phase-float(shot)/float(firing_count)
				if participants[shot]==i and shot_phase>=0.0 and shot_phase<visible_duration:recoil=2.0*(1.0-shot_phase/visible_duration)
		var join_alpha:=1.0
		for joined in recruit_joins:
			if int(joined.index)==i:
				var join_phase:=clampf(float(joined.age)/REINFORCEMENT_DURATION,0.0,1.0)
				join_alpha=join_phase
				ally_positions[i].x=lerpf(w*0.04,ally_positions[i].x,join_phase)
		ArmyAppearance.draw_soldier(self,ally_positions[i]+Vector2(-recoil,gear_motion),true,gear_tier,i,1.0,join_alpha)
		if volley:
			var muzzle:=ally_positions[i]+Vector2(ArmyAppearance.muzzle_offset(gear_tier)-recoil,-3.0+gear_motion)
			_draw_fire(muzzle,Vector2(w*0.80,horizon+59+(defeated%3)*42),1.0-cycle_phase/visible_duration)
		if firing_count>0:
			for shot in firing_count:
				var shot_phase:=cycle_phase-float(shot)/float(firing_count)
				if participants[shot]!=i or shot_phase<0.0 or shot_phase>=visible_duration:continue
				var muzzle:=ally_positions[i]+Vector2(ArmyAppearance.muzzle_offset(gear_tier)-recoil,-3.0+gear_motion)
				var target:=Vector2(w*0.80+(defeated/3)*28,horizon+59+(defeated%3)*42)
				_draw_fire(muzzle,target,1.0-shot_phase/visible_duration)
	for entry in reinforcement_wave:
		var phase:=clampf(float(entry.age)/REINFORCEMENT_DURATION,0.0,1.0)
		var row:=int(entry.index)%4
		var col:=int(entry.index)/4
		var pos:=Vector2(w*0.06-col*22.0,horizon+38.0+row*25.0)
		pos.x=lerpf(pos.x,group_x-40.0-col*24.0,phase)
		ArmyAppearance.draw_soldier(self,pos,true,gear_tier,ally_count+int(entry.index),0.88,1.0-phase*0.15)
	if march>0.42:
		for i in range(defeated,5):
			var enemy_pos:=Vector2(w*0.80+(i/3)*28,horizon+64+(i%3)*42)
			if i==defeated and hit_pulse>0 and combat_active:enemy_pos.x+=3.0
			ArmyAppearance.draw_soldier(self,enemy_pos,false,1,i)
			if i==defeated:
				var hp:=float(state.get("enemy_hp",0.0))
				var max_hp:=maxf(0.001,float(state.get("enemy_max",1.0)))
				var segment_progress:=clampf((1.0-hp/max_hp)*5.0-defeated,0.0,1.0)
				draw_rect(Rect2(enemy_pos+Vector2(-4,-34),Vector2(28,4)),Color("3c2833"))
				draw_rect(Rect2(enemy_pos+Vector2(-4,-34),Vector2(28*(1.0-segment_progress),4)),Color("ed8390"))
	for entry in fallen:
		var index:int=entry.index
		var life:float=entry.life
		var pos:=Vector2(w*0.80+(index/3)*28,horizon+64+(index%3)*42)
		draw_rect(Rect2(pos+Vector2(-2,14),Vector2(27,7)),Color(0.9,0.3,0.35,life/0.7))
		for particle in 4:draw_rect(Rect2(pos+Vector2(particle*9-10,-(0.7-life)*40),Vector2(3,3)),Color(1.0,0.7,0.35,life/0.7))
	draw_string(ThemeDB.fallback_font,Vector2(18,28),"部隊 %s" % str(state.get("soldier_label","%d人"%actual_count)),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ccecf5"))
	var progress:=clampf(1.0-float(state.get("enemy_hp",0.0))/maxf(0.001,float(state.get("enemy_max",1.0))),0.0,1.0)
	draw_rect(Rect2(18,h-46,w-36,8),Color("233946"))
	draw_rect(Rect2(18,h-46,(w-36)*progress,8),Color("55c9e8"))
	var running:=bool(state.get("running",state.get("active",true)))
	var combat_label:String="停止中" if not running else ("前進中" if march<0.98 else "交戦中")
	draw_string(ThemeDB.fallback_font,Vector2(18,h-15),"戦線 %d　制圧 %.1f%%　%s"%[int(state.get("front",0))+1,progress*100.0,combat_label],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ccecf5"))
	if gear_update_age<GEAR_UPDATE_DURATION:
		var phase:=1.0-gear_update_age/GEAR_UPDATE_DURATION
		var banner_width:=minf(w*0.62,maxf(0.0,w*0.96-w*0.34))
		var banner:=Rect2(Vector2(w*0.34,10.0-12.0*phase),Vector2(banner_width,28))
		draw_rect(banner,Color(0.04,0.10,0.15,0.88*(1.0-phase*0.3)))
		var display_text:=gear_update_text
		var max_text_width:=maxf(0.0,banner.size.x-16.0)
		while not display_text.is_empty() and ThemeDB.fallback_font.get_string_size(display_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x>max_text_width:
			display_text=display_text.substr(0,display_text.length()-1)
		if display_text!=gear_update_text and not display_text.is_empty():display_text=display_text.substr(0,maxi(0,display_text.length()-1))+"…"
		draw_string(ThemeDB.fallback_font,banner.position+Vector2(8,20),display_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.78,0.93,0.97,1.0-phase*0.25))

func _draw_fire(from:Vector2,to:Vector2,intensity:float=1.0)->void:
	var alpha:=clampf(intensity,0.0,1.0)
	var flash:=3.0+ArmyAppearance.tier(int(state.gear))
	var tracer_end:=from+(to-from).normalized()*minf(80.0,from.distance_to(to))
	draw_line(from,tracer_end,Color(1.0,0.843,0.424,alpha),2.0)
	draw_rect(Rect2(from-Vector2.ONE*flash/2,Vector2.ONE*flash),Color(1.0,0.941,0.627,alpha))
	draw_rect(Rect2(to-Vector2(2,2),Vector2(4,4)),Color(1.0,0.51,0.424,alpha))
