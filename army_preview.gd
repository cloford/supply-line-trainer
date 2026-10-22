class_name ArmyPreview
extends Control

const MAX_PREVIEW_SOLDIERS := 8
var comparison_kind := 0
var before_state := {"soldiers":0,"gear":0}
var after_state := {"soldiers":0,"gear":0}

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_comparison(kind:int,before:Dictionary,after:Dictionary)->void:
	comparison_kind=kind
	before_state={"soldiers":maxi(0,int(before.get("soldiers",0))),"gear":maxi(0,int(before.get("gear",0)))}
	after_state={"soldiers":maxi(0,int(after.get("soldiers",0))),"gear":maxi(0,int(after.get("gear",0)))}
	queue_redraw()

func _draw()->void:
	if size.x<24.0 or size.y<20.0:return
	var center_y:=size.y*0.52
	draw_rect(Rect2(Vector2(0,0),size),Color("101d28"))
	var side_width:=size.x*0.44
	_draw_formation(Rect2(4,2,side_width,size.y-4),before_state,0.45)
	draw_string(ThemeDB.fallback_font,Vector2(size.x*0.46,center_y+5),"→",HORIZONTAL_ALIGNMENT_CENTER,-1,18,Color("75d4e9"))
	_draw_formation(Rect2(size.x*0.55,2,size.x*0.44-4,size.y-4),after_state,1.0)

func _draw_formation(bounds:Rect2,formation:Dictionary,alpha:float)->void:
	var count:=int(formation.soldiers)
	var draw_count:=mini(count,MAX_PREVIEW_SOLDIERS)
	var gear_tier:=ArmyAppearance.tier(int(formation.gear))
	if comparison_kind==1:
		draw_count=mini(maxi(1,draw_count),3) if count>0 else 0
	var scale_factor:=clampf(minf(bounds.size.y/40.0,bounds.size.x/92.0),0.30,0.68)
	var stride_x:=24.0*scale_factor
	var stride_y:=15.0*scale_factor
	var columns:=3 if comparison_kind==1 else 4
	var rows:=ceili(float(draw_count)/float(columns)) if draw_count>0 else 0
	var origin:=Vector2(bounds.position.x+bounds.size.x*0.5-float(columns-1)*stride_x*0.5,bounds.position.y+bounds.size.y*0.52+7.0*scale_factor+float(rows-1)*stride_y*0.5)
	var background_count:=ArmyAppearance.background_representatives(count,BattleView.MAX_ALLIES)
	for i in background_count:
		var bg_columns:=mini(18,background_count)
		var bg_row:=i/bg_columns
		var bg_col:=i%bg_columns
		var bg_pos:=Vector2(bounds.position.x+4.0+float(bg_col)*5.2,bounds.position.y+7.0+float(bg_row)*5.0)
		ArmyAppearance.draw_soldier(self,bg_pos,true,gear_tier,i,0.16,0.45)
	for i in draw_count:
		var pos:=origin+Vector2(float(i%columns)*stride_x,-float(i/columns)*stride_y)
		ArmyAppearance.draw_soldier(self,pos,true,gear_tier,i,scale_factor,alpha)
