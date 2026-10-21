class_name PracticeRecords
extends ColorRect

signal closed
const PAGE_SIZE := 6
var page := 0
var saved:Dictionary
var summary:Label
var rows:VBoxContainer
var page_label:Label
var previous:Button
var next:Button
var notice:Label

func _ready()->void:
	color=Color("071019")
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
	column.add_child(_text("練習記録",26))
	summary=_text("",18);column.add_child(summary)
	notice=_text("",14);column.add_child(notice)
	rows=VBoxContainer.new();rows.add_theme_constant_override("separation",8);rows.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(rows)
	var nav:=HBoxContainer.new();nav.alignment=BoxContainer.ALIGNMENT_CENTER;column.add_child(nav)
	previous=Button.new();previous.text="前のページ";previous.pressed.connect(_turn.bind(-1));nav.add_child(previous)
	page_label=_text("",16);page_label.custom_minimum_size.x=100;page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;nav.add_child(page_label)
	next=Button.new();next.text="次のページ";next.pressed.connect(_turn.bind(1));nav.add_child(next)
	var back:=Button.new();back.text="訓練準備へ戻る";back.custom_minimum_size.y=44;back.pressed.connect(func():closed.emit());column.add_child(back)

func _text(value:String,font_size:int)->Label:
	var label:=Label.new();label.text=value;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("d4edf5"));label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func open(data:Dictionary,recovered:bool=false)->void:
	saved=data;page=0
	var totals:Dictionary=data.practice_totals
	summary.text="累計練習 %s　射撃活動 %s　%d回\n無制限：練習 %s　射撃活動 %s　%d回"%[Balance.clock_text(float(totals.elapsed)),Balance.clock_text(float(totals.active)),int(totals.sessions),Balance.clock_text(float(totals.unlimited_elapsed)),Balance.clock_text(float(totals.unlimited_active)),int(totals.unlimited_sessions)]
	notice.text="更新後の記録です。一時停止は除外。射撃活動は連射中／単発発射後0.2秒の合計。履歴は直近200件、累計は全件。"+("\n前回中断した練習を、最後の保存時点まで復元しました。" if recovered else "")
	_refresh();show()

func _turn(direction:int)->void:
	page+=direction;_refresh()

func _refresh()->void:
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var history:Array=saved.training_history
	var pages:=maxi(1,ceili(float(history.size())/PAGE_SIZE))
	page=clampi(page,0,pages-1)
	page_label.text="%d / %d"%[page+1,pages];previous.disabled=page==0;next.disabled=page==pages-1
	if history.is_empty():rows.add_child(_text("まだ練習記録がありません。訓練を開始してみましょう。",18));return
	for index in range(page*PAGE_SIZE,mini(history.size(),(page+1)*PAGE_SIZE)):
		var entry:Dictionary=history[index]
		var row:=PanelContainer.new();rows.add_child(row)
		row.add_child(_text("%s　%s / %s / %s　%s\n練習 %s　射撃活動 %s　スコア %d　獲得 %d Cr"%[str(entry.started).replace("T"," "),Balance.WEAPONS[int(entry.weapon)],Balance.DIFFICULTY[int(entry.difficulty)].name,Balance.duration_label(int(entry.duration)),str(entry.status),Balance.clock_text(float(entry.elapsed)),Balance.clock_text(float(entry.active)),int(entry.score),int(entry.credits)],16))
