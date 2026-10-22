class_name ShootingReview
extends VBoxContainer

var heading_label: Label
var lines_label: Label
var note_label: Label
var conditions_label: Label
var explanation_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if heading_label != null:
		return
	add_theme_constant_override("separation", 6)
	heading_label = _make_label(14)
	lines_label = _make_label(16)
	note_label = _make_label(14)
	conditions_label = _make_label(14)
	explanation_label = _make_label(14)
	add_child(heading_label)
	add_child(lines_label)
	add_child(note_label)
	add_child(conditions_label)
	add_child(explanation_label)

func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("d4edf5"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func set_review(model: Dictionary, detailed: bool = false) -> void:
	_build_ui()
	heading_label.text = str(model.get("heading", ""))
	var lines: Array = model.get("lines", [])
	lines_label.text = "\n".join(PackedStringArray(lines.slice(0, 2)))
	note_label.text = str(model.get("note", ""))
	conditions_label.text = str(model.get("conditions", ""))
	explanation_label.text = str(model.get("explanation", ""))
	conditions_label.visible = detailed and not conditions_label.text.is_empty()
	explanation_label.visible = detailed and not explanation_label.text.is_empty()
