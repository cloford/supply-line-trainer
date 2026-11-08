class_name AimPrompt
extends Control

## Click cue shown over the black part of the boot iris. It is decorative and
## never participates in hit testing.
var target_position := Vector2.ZERO
var clicking := false
var phase := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not clicking:
		return
	phase = fposmod(phase + delta * 5.0, TAU)
	queue_redraw()

func set_target(screen_pos: Vector2) -> void:
	if visible and target_position.is_equal_approx(screen_pos):
		return
	target_position = screen_pos
	visible = true
	queue_redraw()

func set_clicking(value: bool) -> void:
	clicking = value
	queue_redraw()

func clear() -> void:
	visible = false

func _draw() -> void:
	# この頂点が標的の投影位置。手のひらは開口の外側へ伸ばす。
	var fingertip := Vector2(0, -96)
	var rotation := Vector2(-0.78, -0.62).angle() + PI * 0.5
	var transform := Transform2D(rotation, target_position - fingertip.rotated(rotation))
	var hand := PackedVector2Array([
		Vector2(-13, 43), Vector2(-19, 14), Vector2(-18, -11),
		Vector2(-14, -17), Vector2(-9, -14), Vector2(-8, 5),
		Vector2(-7, -88), fingertip, Vector2(7, -88),
		Vector2(7, -17), Vector2(12, -31), Vector2(18, -32),
		Vector2(20, -21), Vector2(25, -29), Vector2(31, -26),
		Vector2(31, -13), Vector2(36, -18), Vector2(42, -13),
		Vector2(40, 13), Vector2(32, 38), Vector2(15, 49)
	])
	var points := PackedVector2Array()
	for point in hand:
		points.append(transform * point)
	points.append(points[0])
	draw_colored_polygon(points.slice(0, points.size() - 1), Color("eac293"))
	draw_polyline(points, Color("604a39"), 2.0, true)
	var ring_radius := 12.0 + (sin(phase) + 1.0) * 3.0 if clicking else 14.0
	draw_arc(target_position, ring_radius, 0.0, TAU, 32, Color(0.94, 0.94, 0.82, 0.88), 2.0, true)
