class_name WeaponIcon
extends Control

@export var weapon_id: int = 0
@export var locked: bool = false

const INK := Color("d9e9e9")
const ACCENT := Color("75c9bd")
const MUTED := Color("74858c")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(62, 40)

func _draw() -> void:
	var color := Color("030608") if locked else INK
	var center := size * 0.5
	var line := 3.0
	match weapon_id:
		0: # Compact sidearm
			_draw_body([Vector2(-22, -3), Vector2(-5, -3), Vector2(1, -7), Vector2(15, -7), Vector2(20, -3), Vector2(11, 1), Vector2(7, 4), Vector2(2, 13), Vector2(-5, 13), Vector2(-3, 3), Vector2(-22, 3)], color, line)
		1: # Long, straight rifle
			_draw_body([Vector2(-27, -4), Vector2(-10, -4), Vector2(-5, -7), Vector2(25, -7), Vector2(25, -2), Vector2(6, -2), Vector2(8, 2), Vector2(17, 2), Vector2(13, 5), Vector2(0, 5), Vector2(-5, 12), Vector2(-10, 12), Vector2(-9, 4), Vector2(-27, 4)], color, line)
		2: # Short, heavy burst rifle
			_draw_body([Vector2(-25, -5), Vector2(-9, -5), Vector2(-5, -9), Vector2(11, -9), Vector2(15, -5), Vector2(24, -5), Vector2(24, 0), Vector2(13, 0), Vector2(11, 5), Vector2(3, 5), Vector2(0, 12), Vector2(-6, 12), Vector2(-4, 4), Vector2(-25, 4)], color, line)
		3: # Precision marksman rifle with a scope
			_draw_body([Vector2(-29, -3), Vector2(-16, -3), Vector2(-13, -6), Vector2(27, -6), Vector2(27, -2), Vector2(2, -2), Vector2(4, 3), Vector2(18, 3), Vector2(14, 6), Vector2(-5, 6), Vector2(-10, 12), Vector2(-15, 12), Vector2(-13, 4), Vector2(-29, 4)], color, line)
			_draw_tube(center + Vector2(-1, -11), center + Vector2(11, -11), color, line)
		4: # Tubed launcher
			_draw_tube(center + Vector2(-25, -5), center + Vector2(24, -5), color, line + 1.0)
			_draw_line(center + Vector2(-22, 5), center + Vector2(-8, 5), color, line)
			_draw_line(center + Vector2(-8, 5), center + Vector2(-4, 12), color, line)
			_draw_line(center + Vector2(1, 5), center + Vector2(12, 5), color, line)
			_draw_line(center + Vector2(12, 5), center + Vector2(9, 12), color, line)
			draw_circle(center + Vector2(23, -5), 2.5, Color("030608") if locked else ACCENT)
		_:
			_draw_body([Vector2(-20, -3), Vector2(20, -3), Vector2(20, 3), Vector2(-20, 3)], color, line)

func _draw_body(points: Array, color: Color, width: float) -> void:
	var center := size * 0.5
	var transformed := PackedVector2Array()
	for point in points:
		transformed.append(center + point)
	transformed.append(transformed[0])
	if locked:
		draw_polyline(transformed, MUTED, width + 2.0, true)
		draw_colored_polygon(transformed.slice(0, transformed.size() - 1), color)
	else:
		draw_polyline(transformed, color, width, true)
	_draw_line(center + Vector2(-16, 0), center + Vector2(14, 0), Color("14191c") if locked else color, maxf(1.0, width - 1.0))

func _draw_tube(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var outer := MUTED if locked else color
	_draw_line(from, to, outer, width + (2.0 if locked else 0.0))
	_draw_line(from + Vector2(0, 5), to + Vector2(0, 5), outer, maxf(1.0, width - 1.0) + (2.0 if locked else 0.0))
	if locked:
		_draw_line(from, to, color, width)
		_draw_line(from + Vector2(0, 5), to + Vector2(0, 5), color, maxf(1.0, width - 1.0))

func _draw_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width, true)
