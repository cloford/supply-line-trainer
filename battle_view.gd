class_name BattleView
extends Control

const MAX_ALLIES := 48
var state := {"soldiers":6,"soldier_label":"6人","gear":0,"front":0,"enemy_hp":70.0,"enemy_max":70.0}
var anim_time := 0.0
var march := 1.0
var last_front := -1
var defeated := 0
var damage_age := 99.0
var hit_pulse := 0.0
var world_scroll := 0.0
var fallen:Array[Dictionary] = []

func _ready()->void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	set_process(true)

func set_state(next:Dictionary)->void:
	var next_front := int(next.front)
	if last_front >= 0 and next_front != last_front:
		for index in range(defeated,5):fallen.append({"index":index,"life":0.7})
		march = 0.0
		defeated = 0
	elif next_front==last_front:
		var next_defeated:=clampi(int((1.0-float(next.enemy_hp)/maxf(0.001,float(next.enemy_max)))*5.0),0,4)
		for index in range(defeated,next_defeated):fallen.append({"index":index,"life":0.7})
		defeated=next_defeated
		if float(next.enemy_hp)<float(state.enemy_hp) and damage_age>=0.22:
			hit_pulse=0.13;damage_age=0.0
	else:
		defeated=clampi(int((1.0-float(next.enemy_hp)/maxf(0.001,float(next.enemy_max)))*5.0),0,4)
	last_front = next_front
	state = next
	queue_redraw()

func visible_soldiers(count:int)->int:
	return clampi(count, 1, MAX_ALLIES)

func _process(delta:float)->void:
	if not is_visible_in_tree() or not bool(state.get("running",true)):return
	anim_time += delta
	damage_age+=delta
	hit_pulse=maxf(0.0,hit_pulse-delta)
	if march<1.0:world_scroll+=delta*120.0
	march = minf(1.0, march + delta * 0.9)
	for index in range(fallen.size()-1,-1,-1):
		fallen[index].life=float(fallen[index].life)-delta
		if float(fallen[index].life)<=0:fallen.remove_at(index)
	queue_redraw()

func _draw()->void:
	var w := size.x
	var h := size.y
	if w < 20 or h < 20: return
	var sky:String="08131c"
	draw_rect(Rect2(Vector2.ZERO,size),Color(sky))
	var horizon := h * 0.44
	draw_rect(Rect2(0, horizon, w, h-horizon), Color("172633"))
	for i in 9:
		var stripe_x := fposmod(float(i) * 150.0 - world_scroll, w + 150.0) - 75.0
		draw_line(Vector2(stripe_x,horizon),Vector2(stripe_x-95,h),Color("284151"),2.0)
	for i in 7:
		var building_x := fposmod(float(i)*190.0-world_scroll*0.3,w+200.0)-100.0
		draw_rect(Rect2(building_x,horizon-55-(i%2)*22,62,55+(i%2)*22),Color("10232e"))
	var ally_count := visible_soldiers(int(state.soldiers))
	var contact_x := w * 0.58
	var group_x := lerpf(w*0.22,contact_x,march)
	var gear_tier := Balance.visual_tier(int(state.gear))
	for i in ally_count:
		var row:=i%6;var col:=i/6;_draw_soldier(Vector2(group_x-col*24.0,horizon+45+row*27.0),true,gear_tier,i)
	if march>0.42:
		for i in range(defeated,5):
			var enemy_pos:=Vector2(w*0.80+(i/3)*28,horizon+64+(i%3)*42)
			if i==defeated and hit_pulse>0:enemy_pos.x+=3.0
			_draw_soldier(enemy_pos,false,1,i)
			if i==defeated:
				var segment_progress:=clampf((1.0-float(state.enemy_hp)/maxf(0.001,float(state.enemy_max)))*5.0-defeated,0.0,1.0)
				draw_rect(Rect2(enemy_pos+Vector2(-4,-34),Vector2(28,4)),Color("3c2833"))
				draw_rect(Rect2(enemy_pos+Vector2(-4,-34),Vector2(28*(1.0-segment_progress),4)),Color("ed8390"))
		if march>=0.98 and hit_pulse>0:
			_draw_fire(Vector2(contact_x+30,horizon+40),Vector2(w*0.80+(defeated/3)*28,horizon+59+(defeated%3)*42))
	for entry in fallen:
		var index:int=entry.index
		var life:float=entry.life
		var pos:=Vector2(w*0.80+(index/3)*28,horizon+64+(index%3)*42)
		draw_rect(Rect2(pos+Vector2(-2,14),Vector2(27,7)),Color(0.9,0.3,0.35,life/0.7))
		for particle in 4:
			draw_rect(Rect2(pos+Vector2(particle*9-10,-(0.7-life)*40),Vector2(3,3)),Color(1.0,0.7,0.35,life/0.7))
	var shown:int = mini(ally_count,MAX_ALLIES)
	draw_string(ThemeDB.fallback_font,Vector2(18,28),"部隊 %s　表示 %d" % [str(state.soldier_label),shown],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ccecf5"))
	var progress:=clampf(1.0-float(state.enemy_hp)/maxf(0.001,float(state.enemy_max)),0.0,1.0)
	draw_rect(Rect2(18,h-46,w-36,8),Color("233946"))
	draw_rect(Rect2(18,h-46,(w-36)*progress,8),Color("55c9e8"))
	draw_string(ThemeDB.fallback_font,Vector2(18,h-15),"戦線 %d　制圧 %.1f%%　%s"%[int(state.front)+1,progress*100.0,"前進中" if march<0.98 else "交戦中"],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ccecf5"))

func _draw_soldier(pos:Vector2,ally:bool,tier:int,index:int,scale:float=1.0)->void:
	var bob := 0.0 if march>=0.98 else (2.0 if int(anim_time*7.0+index)%2==0 else -1.0)
	pos.y += bob
	# Pixel rectangles remain integer-aligned; scale only changes the camera-like presentation.
	var body := Color("55c9e8") if ally else Color("e45d68")
	var shade := Color("244b5e") if ally else Color("612c38")
	draw_rect(Rect2(pos+Vector2(4,-18),Vector2(10,9)),Color("e8c6a0"))
	draw_rect(Rect2(pos+Vector2(2,-10),Vector2(14,18)),body)
	draw_rect(Rect2(pos+Vector2(2,8),Vector2(5,11)),shade)
	draw_rect(Rect2(pos+Vector2(11,8),Vector2(5,11)),shade)
	if tier>=1:
		draw_rect(Rect2(pos+Vector2(2,-22),Vector2(14,5)),shade)
		draw_rect(Rect2(pos+Vector2(1,-18),Vector2(3,5)),shade)
	if tier>=2:
		draw_rect(Rect2(pos+Vector2(-1,-8),Vector2(20,10)),Color("8adff0") if ally else Color("f08b91"))
		draw_rect(Rect2(pos+Vector2(-3,-4),Vector2(4,12)),shade)
	var gun_len := (16.0 + tier*4.0)*scale
	if ally:draw_rect(Rect2(pos+Vector2(14,-5),Vector2(gun_len,4+mini(tier,1))),Color("9ba9ad"))
	else:draw_rect(Rect2(pos+Vector2(-gun_len,-5),Vector2(gun_len,4+mini(tier,1))),Color("9ba9ad"))

func _draw_fire(from:Vector2,to:Vector2)->void:
	draw_line(from,to,Color("ffd76c"),2.0)
	draw_circle(from,6.0,Color("fff0a0"))
	draw_circle(to,4.0,Color("ff826c"))
