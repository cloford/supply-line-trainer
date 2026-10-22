class_name PurchaseEffectView
extends PanelContainer

var _title_label: Label
var _headline_label: Label
var _timing_label: Label
var _has_built := false
var _has_model := false
var _model: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_view()
	if _has_model:
		_apply_model()
	else:
		visible = false

func set_effect(model: Dictionary) -> void:
	if _has_model and _model == model:
		return
	_model = model.duplicate(true)
	_has_model = true
	if not _has_built:
		return
	_apply_model()

func clear_effect() -> void:
	_has_model = false
	_model.clear()
	if is_inside_tree():
		visible = false

func _build_view() -> void:
	if _has_built:
		return
	_has_built = true
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.075, 0.095, 0.94)
	panel_style.border_color = Color(0.30, 0.48, 0.53, 0.72)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.set_content_margin_all(8.0)
	add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	_title_label = _make_label(14, Color(0.77, 0.85, 0.87))
	_headline_label = _make_label(17, Color(0.83, 0.94, 0.88))
	_timing_label = _make_label(14, Color(0.79, 0.87, 0.89))
	content.add_child(_title_label)
	content.add_child(_headline_label)
	content.add_child(_timing_label)

func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _apply_model() -> void:
	_title_label.text = str(_model.get("title", ""))
	_headline_label.text = str(_model.get("headline", ""))
	_timing_label.text = str(_model.get("timing", ""))
	_timing_label.visible = not _timing_label.text.is_empty()
	tooltip_text = str(_model.get("detail", ""))
	visible = true
