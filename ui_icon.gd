class_name UIIcon
extends Control

## Distinct, code-drawn symbols for the main actions. Set icon_id to one of:
## play, squad, history, settings, target_edit, stop, tools, lock, help,
## feedback, award.
@export_enum("play", "squad", "history", "settings", "target_edit", "stop", "tools", "lock", "help", "feedback", "award") var icon_id := "play":
	set(value):
		icon_id = value
		queue_redraw()
@export var selected := false:
	set(value):
		selected = value
		queue_redraw()
@export var disabled := false:
	set(value):
		disabled = value
		queue_redraw()

const INK := Color("e4f0ed")
const ACCENT := Color("83d4c8")
const LOCKED := Color("77848a")

func _ready() -> void:
	custom_minimum_size = Vector2(68, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	var scale_factor := minf(size.x, size.y) / 68.0
	var ink := LOCKED if disabled else INK
	var width := 4.0 * scale_factor
	if selected:
		draw_rect(Rect2(Vector2(4, 4) * scale_factor, size - Vector2(8, 8) * scale_factor), ACCENT, false, 3.0 * scale_factor, true)
	match icon_id:
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-13,-20) * scale_factor, c + Vector2(20,0) * scale_factor, c + Vector2(-13,20) * scale_factor]), ink)
		"squad":
			_draw_person(c + Vector2(0,-10), 1.0, ink, width)
			_draw_person(c + Vector2(-19,1), 0.68, ink, width)
			_draw_person(c + Vector2(19,1), 0.68, ink, width)
		"history":
			draw_arc(c, 22 * scale_factor, -2.7, 2.7, 32, ink, width, true)
			draw_line(c + Vector2(0,0), c + Vector2(0,-14) * scale_factor, ink, width, true)
			draw_line(c, c + Vector2(13,7) * scale_factor, ink, width, true)
			draw_line(c + Vector2(-26,-12) * scale_factor, c + Vector2(-26,0) * scale_factor, ink, width, true)
		"settings":
			for i in 8:
				var a := TAU * float(i) / 8.0
				draw_line(c + Vector2.from_angle(a) * 15 * scale_factor, c + Vector2.from_angle(a) * 25 * scale_factor, ink, width + scale_factor, true)
			draw_circle(c, 15 * scale_factor, ink, false, width, true)
			draw_circle(c, 5 * scale_factor, ink)
		"target_edit":
			draw_arc(c, 23 * scale_factor, 0, TAU, 40, ink, width, true)
			draw_arc(c, 15 * scale_factor, 0, TAU, 40, ACCENT if not disabled else ink, width * 0.8, true)
			draw_circle(c, 5 * scale_factor, ink)
			draw_line(c + Vector2(8,-8) * scale_factor, c + Vector2(25,-25) * scale_factor, ink, width, true)
			draw_line(c + Vector2(19,-25) * scale_factor, c + Vector2(25,-25) * scale_factor, ink, width, true)
			draw_line(c + Vector2(25,-25) * scale_factor, c + Vector2(25,-19) * scale_factor, ink, width, true)
		"stop":
			draw_rect(Rect2(c - Vector2(16,16) * scale_factor, Vector2(32,32) * scale_factor), ink, true)
		"tools":
			# Crossed wrench and screwdriver are separate silhouettes.
			draw_line(c + Vector2(-20,19) * scale_factor, c + Vector2(10,-11) * scale_factor, ink, width + 2 * scale_factor, true)
			draw_arc(c + Vector2(13,-16) * scale_factor, 9 * scale_factor, -0.9, 2.2, 20, ink, width, true)
			draw_line(c + Vector2(-9,-20) * scale_factor, c + Vector2(20,9) * scale_factor, ACCENT if not disabled else ink, width + 2 * scale_factor, true)
			draw_circle(c + Vector2(-11,-22) * scale_factor, 5 * scale_factor, ink, false, width, true)
		"lock":
			draw_rect(Rect2(c + Vector2(-17,-1) * scale_factor, Vector2(34,25) * scale_factor), ink, true)
			draw_arc(c + Vector2(0,-3) * scale_factor, 12 * scale_factor, PI, TAU, 24, ink, width, true)
			draw_circle(c + Vector2(0,10) * scale_factor, 3 * scale_factor, Color("172128") if not disabled else Color("273139"))
		"help":
			draw_circle(c, 23 * scale_factor, ink, false, width, true)
			if _font != null:
				draw_string(_font, c + Vector2(-7,-1) * scale_factor, "?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(32 * scale_factor), ink)
			draw_circle(c + Vector2(0,14) * scale_factor, 2.5 * scale_factor, ink)
		"feedback":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-23,-17) * scale_factor, c + Vector2(23,-17) * scale_factor,
				c + Vector2(23,11) * scale_factor, c + Vector2(3,11) * scale_factor,
				c + Vector2(-9,23) * scale_factor, c + Vector2(-8,11) * scale_factor,
				c + Vector2(-23,11) * scale_factor
			]), ink)
			for i in 3:
				draw_line(c + Vector2(-13 + i * 10,-3) * scale_factor, c + Vector2(-8 + i * 10,-3) * scale_factor, Color("16232a"), width, true)
		"award":
			draw_circle(c + Vector2(0,-8) * scale_factor, 17 * scale_factor, ink)
			var star := PackedVector2Array()
			for point in 10:
				var angle := -PI * 0.5 + TAU * float(point) / 10.0
				var r := (13.0 if point % 2 == 0 else 6.0) * scale_factor
				star.append(c + Vector2.from_angle(angle) * r + Vector2(0,-8) * scale_factor)
			draw_colored_polygon(star, ACCENT if not disabled else LOCKED)
			draw_line(c + Vector2(-7,8) * scale_factor, c + Vector2(-12,25) * scale_factor, ink, width + 2.0, true)
			draw_line(c + Vector2(7,8) * scale_factor, c + Vector2(12,25) * scale_factor, ink, width + 2.0, true)

func _draw_person(center: Vector2, factor: float, color: Color, width: float) -> void:
	draw_circle(center + Vector2(0,-8) * factor, 5 * factor, color)
	draw_arc(center + Vector2(0,11) * factor, 12 * factor, PI, TAU, 24, color, width * factor, true)

var _font: Font:
	get:
		return ThemeDB.fallback_font
