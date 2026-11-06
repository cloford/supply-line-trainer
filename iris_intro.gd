class_name IrisIntro
extends Control

signal finished

const DEFAULT_OPEN_SECONDS := 0.78
const FAST_OPEN_SECONDS := 0.24

var anchor := Vector2.ZERO
var radius_pixels := 72.0
var opening := false
var waiting := false
var elapsed := 0.0
var duration := DEFAULT_OPEN_SECONDS
var _shade: ColorRect
var _material: ShaderMaterial
var _last_viewport := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 anchor_uv = vec2(0.5, 0.5);
uniform float radius_px = 72.0;
uniform vec2 viewport_px = vec2(1280.0, 720.0);
void fragment() {
	vec2 delta_px = (UV - anchor_uv) * viewport_px;
	COLOR = vec4(0.0, 0.0, 0.0, step(radius_px, length(delta_px)));
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.material = _material
	add_child(_shade)
	visible = false
	_sync_shader()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_shader()

func start_wait(screen_pos: Vector2, radius: float) -> void:
	anchor = screen_pos
	radius_pixels = maxf(12.0, radius)
	opening = false
	waiting = true
	elapsed = 0.0
	visible = true
	_sync_shader()

func open_from(screen_pos: Vector2, effects_enabled: bool = true) -> void:
	if not waiting and not opening:
		return
	# Snapshot once: world/camera motion must not move the aperture mid animation.
	anchor = screen_pos
	opening = true
	waiting = false
	elapsed = 0.0
	duration = DEFAULT_OPEN_SECONDS if effects_enabled else FAST_OPEN_SECONDS
	_sync_shader()

func advance(delta: float, active: bool = true) -> void:
	if not active or not opening:
		return
	elapsed += maxf(0.0, delta)
	_sync_shader()
	if elapsed >= duration:
		clear()
		finished.emit()

func skip() -> void:
	if opening or waiting:
		clear()
		finished.emit()

func clear() -> void:
	opening = false
	waiting = false
	elapsed = 0.0
	visible = false

func is_active() -> bool:
	return waiting or opening

func _sync_shader() -> void:
	if _material == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	if _last_viewport.x > 0.0 and _last_viewport.y > 0.0 and _last_viewport != viewport_size:
		anchor = (anchor / _last_viewport) * viewport_size
	_last_viewport = viewport_size
	var radius := radius_pixels
	if opening:
		var t := clampf(elapsed / maxf(0.001, duration), 0.0, 1.0)
		# Smoothly grow from the crosshair window to beyond all viewport corners.
		radius = lerpf(radius_pixels, viewport_size.length() + 2.0, t * t * (3.0 - 2.0 * t))
	_material.set_shader_parameter("anchor_uv", anchor / viewport_size)
	_material.set_shader_parameter("radius_px", radius)
	_material.set_shader_parameter("viewport_px", viewport_size)
