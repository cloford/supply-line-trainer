class_name AimCrosshair
extends Control

var line_color := Color("66e8ff")
var line_size := 10.0
var shape := 1
var outline_enabled := true

func _ready()->void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_appearance(value:String, pixels:float, next_shape:int=1, next_outline:bool=true)->void:
	line_color = Color(value) if Color.html_is_valid(value) else Color("66e8ff")
	line_size = clampf(pixels, 4.0, 30.0)
	shape=clampi(next_shape,0,3);outline_enabled=next_outline
	queue_redraw()

func _draw()->void:
	var center := size * 0.5
	var outline := Color(0.92,0.97,1.0,0.96) if line_color.get_luminance()<0.25 else Color(0.015,0.025,0.035,0.96)
	var outer := 5.0 if outline_enabled else 0.0
	var inner := 2.0
	if shape==0:
		if outline_enabled:draw_circle(center,4.0,outline)
		draw_circle(center,2.0,line_color)
	elif shape==3:
		if outline_enabled:draw_arc(center,line_size,0,TAU,32,outline,outer,false)
		draw_arc(center,line_size,0,TAU,32,line_color,inner,false)
	else:
		var gap:=0.0 if shape==1 else maxf(3.0,line_size*0.35)
		for segment in [[Vector2(-line_size,0),Vector2(-gap,0)],[Vector2(gap,0),Vector2(line_size,0)],[Vector2(0,-line_size),Vector2(0,-gap)],[Vector2(0,gap),Vector2(0,line_size)]]:
			if outline_enabled:draw_line(center+segment[0],center+segment[1],outline,outer,false)
			draw_line(center+segment[0],center+segment[1],line_color,inner,false)
