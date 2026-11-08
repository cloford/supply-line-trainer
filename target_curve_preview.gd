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
	return _points_at(1.0, risk)

func edge_points() -> float:
	return _points_at(0.0, risk)

func _points_at(q: float, risk_value: float) -> float:
	if not score_curve.is_valid():
		return 0.0
	return maxf(0.0, float(score_curve.call(q, risk_value)))

func _draw() -> void:
	var center := Vector2(minf(size.x * 0.29, size.y * 0.48), size.y * 0.5)
	var radius := minf(size.y * 0.39, size.x * 0.25)
	var rings := 48
	var edge_color := Color("2994df")
	var center_color := Color("f15d58")
	var edge_value := edge_points()
	var center_value := center_points()
	# 編集位置に関係なく、同じ参考点は同じ色になる。
	var high := maxf(0.001, _points_at(1.0, 1.0))
	for band in range(rings, 0, -1):
		var radial := float(band) / float(rings)
		var q := 1.0 - radial
		var points := _points_at(q, risk)
		var color := edge_color.lerp(center_color, clampf(points / high, 0.0, 1.0))
		draw_circle(center, radius * radial, color, true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 64, Color("e5eff0"), 2.0, true)
	draw_circle(center, 3.0, Color("fff6e8"))
	var label_x := minf(size.x * 0.56, center.x + radius + 18.0)
	var color_text := Color("dce8eb")
	var center_label := "%.1f" % center_value
	var edge_label := "%.1f" % edge_value
	_draw_text("中心", Vector2(label_x, center.y - 12.0), color_text, 15)
	_draw_text(center_label, Vector2(label_x, center.y + 14.0), center_color, 24)
	_draw_text("端", Vector2(label_x, center.y + 47.0), color_text, 15)
	_draw_text(edge_label, Vector2(label_x, center.y + 71.0), edge_color, 24)

func _draw_text(value: String, position: Vector2, color: Color, font_size: int) -> void:
	if _font != null:
		draw_string(_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
