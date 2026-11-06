extends SceneTree

const VIEW := preload("res://progression_view.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var view = VIEW.new()
	var model := {
		"total": 9,
		"rows": [
			{"id": 0, "name": "ハンドガン", "title": "初期装備", "threshold": 0, "unlocked": true},
			{"id": 1, "name": "アサルトライフル", "threshold": 10, "unlocked": false}
		],
		"achievements": [{"id": "first", "title": "はじめの一発", "description": "最初の標的を撃破した", "unlocked": true, "unlocked_at": "2026-11-06"}],
		"effects_enabled": true
	}
	view.refresh(model)
	view.set_context(true, false, true)
	root.add_child(view)
	await process_frame
	assert(view.visible)
	assert(view._model["rows"].size() == 2)
	assert(view._model["total"] == 9)
	assert(view._roster_list.get_child_count() == 2)
	view.set_context(true, true, true)
	assert(view._roster_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	view.set_context(false, true, true)
	assert(view._roster_panel.mouse_filter == Control.MOUSE_FILTER_STOP)
	assert(view.is_overlay_open())
	view.show_achievements()
	assert(view.is_overlay_open())
	view.close_overlay()
	assert(not view.is_overlay_open())
	print("ProgressionView component checks passed")
	quit(0)
