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
	if not visible:
		return
	phase = fposmod(phase + delta * 5.0, TAU)
	queue_redraw()

func set_target(screen_pos: Vector2) -> void:
	target_position = screen_pos
	visible = true
	queue_redraw()

func set_clicking(value: bool) -> void:
	clicking = value
	queue_redraw()

func clear() -> void:
	visible = false

func _draw() -> void:
	var viewport := get_viewport_rect().size
	if viewport.x < 1.0 or viewport.y < 1.0:
		return
	var origin := Vector2(viewport.x * 0.79, viewport.y * 0.78)
	var toward := (target_position - origin).normalized()
	if toward.length_squared() < 0.01:
		toward = Vector2(-0.55, -0.83)
	var angle := toward.angle()
	var press := 0.0
	if clicking:
		press = (sin(phase) + 1.0) * 0.5 * 9.0
	var hand_center := origin - toward * 64.0 + toward * press
	var transform := Transform2D(angle + PI * 0.5, hand_center)
	var hand := PackedVector2Array([
		Vector2(-13, 43), Vector2(-19, 14), Vector2(-18, -11),
		Vector2(-14, -17), Vector2(-9, -14), Vector2(-8, 5),
		Vector2(-6, -47), Vector2(-1, -55), Vector2(5, -52),
		Vector2(7, -17), Vector2(12, -31), Vector2(18, -32),
		Vector2(20, -21), Vector2(25, -29), Vector2(31, -26),
		Vector2(31, -13), Vector2(36, -18), Vector2(42, -13),
		Vector2(40, 13), Vector2(32, 38), Vector2(15, 49)
	])
	var points := PackedVector2Array()
	for point in hand:
		points.append(transform * point)
	points.append(points[0])
	draw_colored_polygon(points.slice(0, points.size() - 1), Color(0.97, 0.79, 0.55, 0.98))
	draw_polyline(points, Color(0.10, 0.11, 0.12), 5.0, true)
	# Bright nail and fingertip make the pointing direction readable at 720p.
	var nail_center := transform * Vector2(2, -40)
	draw_circle(nail_center, 6.0, Color(1.0, 0.9, 0.78))
	var tip := transform * Vector2(2, -66)
	var ring_radius := 12.0 + (sin(phase) + 1.0) * 3.0
	draw_arc(tip, ring_radius, 0.0, TAU, 32, Color(0.94, 0.94, 0.82, 0.88), 3.0, true)
