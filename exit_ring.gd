extends Control

var value:=0.0:
	set(next):value=next;queue_redraw()

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw()->void:
	draw_arc(Vector2(20,20),15,0,TAU,40,Color("263d4c"),4,true)
	draw_arc(Vector2(20,20),15,-PI/2,-PI/2+TAU*clampf(value/0.8,0,1),40,Color("ffe3a0"),4,true)
