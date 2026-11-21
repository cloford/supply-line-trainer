class_name TargetCurvePreview
extends HBoxContainer

## Preview renderer for the exact score curve used by play. Supply a Callable
## (q, risk) -> points so the preview never duplicates scoring math.
@export var risk := 0.5:
	set(value):
		risk = clampf(value, 0.0, 1.0)
		_update_preview()

var score_curve: Callable
var _target: Control
var _center_label: Label
var _edge_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(280, 142)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 18)
	_target = Control.new()
	_target.custom_minimum_size = Vector2(124, 124)
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target.draw.connect(_draw_target)
	add_child(_target)
	var values := VBoxContainer.new()
	values.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	values.add_theme_constant_override("separation", 4)
	add_child(values)
	for caption in ["中心", "端"]:
		var heading := Label.new()
		heading.text = caption
		heading.add_theme_font_size_override("font_size", 15)
		values.add_child(heading)
		var number := Label.new()
		number.add_theme_font_size_override("font_size", 24)
		number.add_theme_color_override("font_color", Color("f15d58") if caption == "中心" else Color("2994df"))
		values.add_child(number)
		if caption == "中心":
			_center_label = number
		else:
			_edge_label = number
	_update_preview()

func _update_preview() -> void:
	if not is_instance_valid(_target):
		return
	_center_label.text = "%.1f" % center_points()
	_edge_label.text = "%.1f" % edge_points()
	_target.queue_redraw()

func set_curve_callable(curve: Callable) -> void:
	score_curve = curve
	_update_preview()

func set_risk(value: float) -> void:
	risk = value
	_update_preview()

func configure(curve: Callable, value: float) -> void:
	score_curve = curve
	risk = value
	_update_preview()

func center_points() -> float:
	return _points_at(1.0, risk)

func edge_points() -> float:
	return _points_at(0.0, risk)

func _points_at(q: float, risk_value: float) -> float:
	if not score_curve.is_valid():
		return 0.0
	return maxf(0.0, float(score_curve.call(q, risk_value)))

func _draw_target() -> void:
	var center := _target.size * 0.5
	var radius := minf(_target.size.y, _target.size.x) * 0.45
	var rings := 48
	var edge_color := Color("2994df")
	var center_color := Color("f15d58")
	# 編集位置に関係なく、同じ参考点は同じ色になる。
	var high := maxf(0.001, _points_at(1.0, 1.0))
	for band in range(rings, 0, -1):
		var radial := float(band) / float(rings)
		var q := 1.0 - radial
		var points := _points_at(q, risk)
		var color := edge_color.lerp(center_color, clampf(points / high, 0.0, 1.0))
		_target.draw_circle(center, radius * radial, color, true, -1.0, true)
	_target.draw_arc(center, radius, 0.0, TAU, 64, Color("e5eff0"), 2.0, true)
	_target.draw_circle(center, 3.0, Color("fff6e8"))
