class_name V2Records
extends PracticeRecords

func open(data:Dictionary, recovered:bool = false)->void:
	super.open(data, recovered)
	archive_button.hide()
	notice.text = "新育成の記録のみ。通常履歴200件。採用中・直前の元記録は別に保持します。"
	if recovered:
		notice.text += "\n前回の中断記録を保存地点まで復元（完了測定には数えません）。"

func _refresh()->void:
	if rows == null:
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var history:Array = saved.get("training_history", [])
	var pages := maxi(1, ceili(float(history.size()) / PAGE_SIZE))
	page = clampi(page, 0, pages - 1)
	page_label.text = "%d / %d" % [page + 1, pages]
	previous.disabled = page == 0
	next.disabled = page == pages - 1
	if history.is_empty():
		rows.add_child(_text("まだ記録はありません。全武器の自由練習・測定を最初から利用できます。", 18))
	for index in range(page * PAGE_SIZE, mini(history.size(), (page + 1) * PAGE_SIZE)):
		var entry:Dictionary = history[index]
		var measurement:Dictionary = entry.get("measurement", {})
		var kind := "60秒測定" if not measurement.is_empty() else "自由練習"
		var status := str(entry.get("status", ""))
		if not measurement.is_empty():
			status = "採用可能" if bool(measurement.get("valid", false)) else str(measurement.get("invalid_reason", "未完了"))
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 68
		button.text = "%s　%s / %s　%s\n練習 %s　獲得 %d クレジット" % [str(entry.get("started", "")), kind, ["ハンドガン", "アサルトライフル", "バーストライフル"][clampi(int(entry.get("weapon", 0)), 0, 2)], status, Balance.clock_text(float(entry.get("elapsed", 0))), int(entry.get("credits", 0))]
		button.pressed.connect(_select_record.bind(entry))
		rows.add_child(button)
