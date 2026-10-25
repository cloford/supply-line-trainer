extends SceneTree

func _initialize()->void:
	call_deferred("_run")

func sample(bursts:bool)->Dictionary:
	var recorder := V2Measurement.new()
	recorder.begin(0, V2Save.SETTING_DEFAULTS, 25, "synthetic-bursts" if bursts else "synthetic-steady")
	var position := Vector3(0, 2.4, -11)
	recorder.target_event(0.0, "spawn", "target", {"position":position, "radius":0.42})
	for index in 60:
		var time := floori(float(index) / 3.0) * 3.0 + (index % 3) * 0.085 if bursts else float(index)
		var hit := index % 4 != 3
		var origin := Vector3(0, 1.6, 0)
		var end := position if hit else position + Vector3(1.2, -0.9, 0)
		recorder.shot(time, hit, 0.8, "target", origin, (end - origin).normalized(), end)
	return recorder.completed(60.0)

func _run()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1":
		quit(1)
		return
	root.size = Vector2i(1280, 480)
	root.content_scale_size = root.size
	var background := ColorRect.new()
	background.color = Color("09151e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(column)
	var heading := Label.new()
	heading.text = "記録の再現 — 等速の合成例。名前・能力数値を隠した比較（人の評価は未実施）"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var views:Array[V2Diorama] = []
	var players:Array[V2Replay] = []
	for bursts in [false, true]:
		var view := V2Diorama.new()
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(view)
		view.set_preview(0, true)
		view.set_active(true)
		views.append(view)
		var replay := V2Replay.new()
		replay.start(sample(bursts))
		players.append(replay)
	await process_frame
	for tick in 240:
		for index in 2:
			var events := players[index].advance(1.0 / 30.0)
			views[index].show_replay(players[index].record, players[index].time, players[index].targets, players[index].pose_state)
			views[index].consume_replay(events)
		await process_frame
	print("V2_RHYTHM_MOVIE_OK: two synthetic recorded rhythms, exact time, no economy/battle state")
	quit(0)
