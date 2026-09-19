class_name AimCrosshair
extends Control

var line_color := Color("66e8ff")
var line_size := 10.0

func _ready()->void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_appearance(value:String, pixels:float)->void:
	line_color = Color(value) if Color.html_is_valid(value) else Color("66e8ff")
	line_size = clampf(pixels, 4.0, 30.0)
	queue_redraw()

func _draw()->void:
	var center := size * 0.5
	var outline := Color(0.92,0.97,1.0,0.96) if line_color.get_luminance()<0.25 else Color(0.015,0.025,0.035,0.96)
	var outer := 5.0
	var inner := 2.0
	draw_line(center + Vector2(-line_size, 0), center + Vector2(line_size, 0), outline, outer, false)
	draw_line(center + Vector2(0, -line_size), center + Vector2(0, line_size), outline, outer, false)
	draw_line(center + Vector2(-line_size, 0), center + Vector2(line_size, 0), line_color, inner, false)
	draw_line(center + Vector2(0, -line_size), center + Vector2(0, line_size), line_color, inner, false)
	draw_circle(center, 1.5, line_color)
