extends SceneTree

const VIEW := preload("res://progression_view.gd")
const IRIS := preload("res://iris_intro.gd")
const SPAWN_AUDIO := preload("res://spawn_audio.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var achievements: Array = []
	for definition in Progression.definitions():
		var achievement: Dictionary = definition.duplicate(true)
		achievement["unlocked"] = str(achievement.get("id", "")) == "first_kill"
		achievement["unlocked_at"] = "2026-11-06" if bool(achievement["unlocked"]) else ""
		achievements.append(achievement)
	var view = VIEW.new()
	var model := {
		"total": 9,
		"rows": [
			{"id": 0, "name": "ハンドガン", "title": "初期装備", "threshold": 0, "remaining": 0, "unlocked": true},
			{"id": 1, "name": "アサルトライフル", "threshold": 10, "remaining": 10, "unlocked": false}
		],
		"achievements": achievements,
		"effects_enabled": true
	}
	view.refresh(model)
	view.set_context(true, false, true)
	root.add_child(view)
	await process_frame
	assert(view.visible)
	assert(view._model["rows"].size() == 2)
	assert(view._model["total"] == 9)
	var visible_rows := 0
	for child in view._roster_list.get_children():
		if child.visible:
			visible_rows += 1
	assert(visible_rows == 2)
	var retained_row:Control = view._weapon_widgets[0].box
	var retained_achievement:Label = view._achievement_widgets["first_kill"].title
	view.set_context(false,false,false)
	for refresh_index in 5:view.refresh(model)
	assert(view._weapon_widgets[0].box == retained_row)
	assert(view._achievement_widgets["first_kill"].title == retained_achievement)
	view.set_context(true,false,true)
	view.set_context(true, true, true)
	assert(view._roster_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	view.set_context(false, true, true)
	assert(view._roster_panel.mouse_filter == Control.MOUSE_FILTER_STOP)
	assert(view.is_overlay_open())
	view.show_achievements()
	assert(view.is_overlay_open())
	view.close_overlay()
	assert(not view.is_overlay_open())
	var iris = IRIS.new()
	root.add_child(iris)
	await process_frame
	iris.start_wait(Vector2(300, 200), 64.0)
	assert(iris.visible and iris.waiting and not iris.opening)
	assert(iris.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	iris.open_from(Vector2(300, 200), true)
	assert(iris.opening and not iris.waiting)
	iris.advance(0.2, false)
	assert(is_equal_approx(iris.elapsed, 0.0))
	iris.advance(0.2, true)
	assert(is_equal_approx(iris.elapsed, 0.2))
	assert(iris.anchor == Vector2(300, 200))
	iris.skip()
	assert(not iris.is_active() and not iris.visible)
	var button := Button.new()
	root.add_child(button)
	V2Interface.set_weapon_button(button, 3, false, false, "Precision rifle")
	assert(button.text.begins_with("???") and button.text.contains("500"))
	var icon: WeaponIcon = button.get_child(0)
	assert(icon.locked and icon.weapon_id == 3)
	V2Interface.set_weapon_button(button, 3, true, true, "Precision rifle")
	assert(button.text == "✓ Precision rifle")
	assert(not icon.locked)
	var pop = SPAWN_AUDIO.new()
	root.add_child(pop)
	await process_frame
	assert(pop._stream != null and pop._stream.data.size() > 0)
	assert(not pop._player.playing)
	pop.spawn_at(Vector2(1, 2))
	assert(pop._player.playing)
	pop.spawn_at(Vector2(3, 4))
	assert(pop.play_count == 1)
	pop._player.stop()
	pop.configure({"effects_enabled": true, "volume": 0.0, "shot_volume": 1.0})
	pop.spawn_at()
	assert(not pop._player.playing)
	assert(pop.play_count == 1)
	print("ProgressionView component checks passed")
	for node in [view,iris,button,pop]:
		node.queue_free()
	await process_frame
	quit(0)
