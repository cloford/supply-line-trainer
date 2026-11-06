class_name CountdownDisplay
extends Control

## Presentation only. Timing, input lockout, and sound are managed by the caller.
var number_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 0
	number_label = Label.new()
	number_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	number_label.anchor_left = 0.5
	number_label.anchor_right = 0.5
	number_label.anchor_top = 0.31
	number_label.anchor_bottom = 0.31
	number_label.offset_left = -110.0
	number_label.offset_right = 110.0
	number_label.offset_top = -78.0
	number_label.offset_bottom = 78.0
	number_label.custom_minimum_size = Vector2(220.0, 156.0)
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_label.add_theme_font_size_override("font_size", 112)
	number_label.add_theme_color_override("font_color", Color("f4faf8"))
	number_label.add_theme_color_override("font_outline_color", Color("071116"))
	number_label.add_theme_constant_override("outline_size", 10)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(number_label)
	hide()

func show_number(value: int) -> void:
	if value < 1 or value > 3:
		clear()
		return
	number_label.text = str(value)
	show()

func clear() -> void:
	number_label.text = ""
	hide()
