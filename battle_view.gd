class_name BattleView
extends Control

const MAX_ALLIES := 48
var state := {"soldiers":6,"soldier_label":"6","scale_tier":0,"gear":0,"front":0,"enemy_hp":70.0,"enemy_max":70.0}
var anim_time := 0.0
var march := 1.0
var last_front := -1

func _ready()->void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	set_process(true)

func set_state(next:Dictionary)->void:
	var next_front := int(next.front)
	if last_front >= 0 and next_front != last_front:
		march = 0.0
	last_front = next_front
	state = next
	queue_redraw()

func visible_soldiers(count:int)->int:
	return clampi(count, 1, MAX_ALLIES)

func _process(delta:float)->void:
	anim_time += delta
	march = minf(1.0, march + delta * 0.48)
	queue_redraw()

func _draw()->void:
	var w := size.x
	var h := size.y
	if w < 20 or h < 20: return
	var tier:=int(state.get("scale_tier",0));var sky:String=["08131c","0a1820","101625","080e20","050916","03050e"][tier]
	draw_rect(Rect2(Vector2.ZERO,size),Color(sky))
	var horizon := h * 0.44
	draw_rect(Rect2(0, horizon, w, h-horizon), Color("172633"))
	for i in 9:
		var stripe_x := fmod(float(i) * 150.0 - anim_time * 22.0, w + 150.0) - 75.0
		draw_line(Vector2(stripe_x,horizon),Vector2(stripe_x-95,h),Color("284151"),2.0)
	for i in 7:
		var building_x := fmod(float(i)*190.0-anim_time*7.0,w+200.0)-100.0
		draw_rect(Rect2(building_x,horizon-55-(i%2)*22,62,55+(i%2)*22),Color("10232e"))
	var ally_count := visible_soldiers(int(state.soldiers))
	var contact_x := w * 0.58
	var group_x := lerpf(w*0.22,contact_x,march)
	var gear_tier := Balance.visual_tier(int(state.gear))
	_draw_landmark(tier,Vector2(w*0.34,horizon))
	if tier<=1:
		for i in ally_count:
			var row:=i%6;var col:=i/6;_draw_soldier(Vector2(group_x-col*24.0,horizon+45+row*27.0),true,gear_tier,i,0.72 if tier==1 else 1.0)
	else:
		var dots:=mini(240,24+ally_count*4+tier*24)
		for i in dots:
			var px:=group_x-fmod(float(i*37),minf(280.0,w*0.38));var py:=horizon+30+fmod(float(i*53),h-horizon-45);draw_rect(Rect2(Vector2(px,py),Vector2(3,3)),Color("55c9e8"))
	if march>0.42:
		for i in 5:
			_draw_soldier(Vector2(w*0.80+(i/3)*28,horizon+64+(i%3)*42),false,1,i)
		if march>=0.98:
			_draw_fire(Vector2(contact_x+12,horizon+75),Vector2(w*0.79,horizon+75))
	var shown:int = mini(ally_count,MAX_ALLIES)
	draw_string(ThemeDB.fallback_font,Vector2(18,28),"軍勢規模 %s　表示単位 %d" % [str(state.soldier_label),shown],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ccecf5"))

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

func _draw_landmark(tier:int,pos:Vector2)->void:
	var c:=Color("425563")
	if tier==1:
		draw_rect(Rect2(pos+Vector2(-35,-45),Vector2(70,45)),c);draw_rect(Rect2(pos+Vector2(-60,-25),Vector2(22,25)),c)
	elif tier==2:
		draw_line(pos+Vector2(0,-150),pos,Color("667a89"),8);draw_line(pos+Vector2(-35,-65),pos+Vector2(35,-65),c,5)
	elif tier==3:
		draw_circle(pos+Vector2(0,-75),45,Color("58758a"));draw_line(pos+Vector2(0,-30),pos+Vector2(0,0),c,8)
	elif tier==4:
		draw_circle(pos+Vector2(0,-60),58,Color("27628c"));draw_arc(pos+Vector2(0,-60),73,0,TAU,40,Color("8ba4b4"),3)
	elif tier>=5:
		for i in 80:
			var angle:=i*2.399;var radius:=sqrt(float(i))*8.0;draw_circle(pos+Vector2(cos(angle),sin(angle))*radius-Vector2(0,70),2.0,Color("a8d8ff"))

func _draw_fire(from:Vector2,to:Vector2)->void:
	if int(anim_time*7.0)%3!=0: return
	draw_line(from,to,Color("ffd76c"),2.0)
	draw_circle(from,6.0,Color("fff0a0"))
	draw_circle(to,4.0,Color("ff826c"))
