class_name TargetCurvePreview
extends Control

## Preview renderer for the exact score curve used by play. Supply a Callable
## (q, risk) -> points so the preview never duplicates scoring math.
@export var risk := 0.5:
	set(value):
		risk = clampf(value, 0.0, 1.0)
		queue_redraw()

var score_curve: Callable
var _font: Font

func _ready() -> void:
	custom_minimum_size = Vector2(280, 142)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func set_curve_callable(curve: Callable) -> void:
	score_curve = curve
	queue_redraw()

func set_risk(value: float) -> void:
	risk = value
	queue_redraw()

func configure(curve: Callable, value: float) -> void:
	score_curve = curve
	risk = value
	queue_redraw()

func center_points() -> float:
	return _points_at(1.0)

func edge_points() -> float:
	return _points_at(0.0)

func _points_at(q: float) -> float:
	if not score_curve.is_valid():
		return 0.0
	return maxf(0.0, float(score_curve.call(q, risk)))

func _draw() -> void:
	var center := Vector2(minf(size.x * 0.29, size.y * 0.48), size.y * 0.5)
	var radius := minf(size.y * 0.39, size.x * 0.25)
	var segments := 96
	var rings := 24
	var edge_color := Color("2994df")
	var center_color := Color("f15d58")
	var edge_value := _points_at(0.0)
	var center_value := _points_at(1.0)
	var low := minf(edge_value, center_value)
	var high := maxf(edge_value, center_value)
	# Concentric smooth bands keep the target's center red and its edge blue.
	for band in rings:
		var r0 := radius * float(band) / float(rings)
		var r1 := radius * float(band + 1) / float(rings)
		var q := 1.0 - (float(band) + 0.5) / float(rings)
		var points := _points_at(q)
		var t := clampf((points - low) / maxf(0.001, high - low), 0.0, 1.0)
		var color := edge_color.lerp(center_color, t)
		for i in segments:
			var a0 := TAU * float(i) / float(segments)
			var a1 := TAU * float(i + 1) / float(segments)
			var cell := PackedVector2Array([
				center + Vector2.from_angle(a0) * r0,
				center + Vector2.from_angle(a0) * r1,
				center + Vector2.from_angle(a1) * r1,
				center + Vector2.from_angle(a1) * r0
			])
			draw_colored_polygon(cell, color)
	draw_arc(center, radius, 0.0, TAU, 64, Color("e5eff0"), 2.0, true)
	draw_circle(center, 3.0, Color("fff6e8"))
	var label_x := minf(size.x * 0.56, center.x + radius + 18.0)
	var color_text := Color("dce8eb")
	var center_label := "%.1f" % center_points()
	var edge_label := "%.1f" % edge_points()
	_draw_text("CENTER", Vector2(label_x, center.y - 12.0), color_text, 13)
	_draw_text(center_label, Vector2(label_x, center.y + 14.0), center_color, 24)
	_draw_text("EDGE", Vector2(label_x, center.y + 47.0), color_text, 13)
	_draw_text(edge_label, Vector2(label_x, center.y + 71.0), edge_color, 24)

func _draw_text(value: String, position: Vector2, color: Color, font_size: int) -> void:
	if _font != null:
		draw_string(_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
