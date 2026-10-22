class_name PracticeRecords
extends ColorRect

signal closed
signal record_selected(record:Dictionary)
const PAGE_SIZE := 5
var page := 0
var saved:Dictionary
var summary:Label
var rows:VBoxContainer
var page_label:Label
var previous:Button
var next:Button
var notice:Label
var archived := false
var archive_button:Button
var listing:VBoxContainer
var detail_view:VBoxContainer
var detail_review:ShootingReview
var detail_title:Label
var detail_back:Button

func _ready()->void:
	color=Color("071019")
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	margin.add_theme_constant_override("margin_bottom",96)
	add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
	column.add_child(_text("練習記録",26))
	summary=_text("",18);column.add_child(summary)
	notice=_text("",14);column.add_child(notice)
	listing=VBoxContainer.new();listing.add_theme_constant_override("separation",10);listing.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(listing)
	archive_button=Button.new();archive_button.text="旧バージョンの記録を見る";archive_button.pressed.connect(_toggle_archive);listing.add_child(archive_button)
	rows=VBoxContainer.new();rows.add_theme_constant_override("separation",8);rows.size_flags_vertical=Control.SIZE_EXPAND_FILL;listing.add_child(rows)
	var nav:=HBoxContainer.new();nav.alignment=BoxContainer.ALIGNMENT_CENTER
	previous=Button.new();previous.text="前のページ";previous.pressed.connect(_turn.bind(-1));nav.add_child(previous)
	page_label=_text("",16);page_label.custom_minimum_size.x=100;page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;nav.add_child(page_label)
	next=Button.new();next.text="次のページ";next.pressed.connect(_turn.bind(1));nav.add_child(next)
	listing.add_child(nav)
	detail_view=VBoxContainer.new();detail_view.add_theme_constant_override("separation",8);detail_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(detail_view)
	detail_title=_text("",18);detail_view.add_child(detail_title)
	detail_review=ShootingReview.new();detail_view.add_child(detail_review)
	detail_back=Button.new();detail_back.text="記録一覧へ戻る";detail_back.pressed.connect(_show_listing);detail_view.add_child(detail_back)
	detail_view.hide()

func _text(value:String,font_size:int)->Label:
	var label:=Label.new();label.text=value;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("d4edf5"));label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func open(data:Dictionary,recovered:bool=false)->void:
	saved=data;page=0;archived=false;_show_listing()
	var totals:Dictionary=data.practice_totals
	summary.text="累計練習 %s　射撃活動 %s　%d回"%[Balance.clock_text(float(totals.elapsed)),Balance.clock_text(float(totals.active)),int(totals.sessions)]
	notice.text="累計は旧バージョン分を含みます。一時停止は除外。履歴は直近200件、累計は全件。"+("\n前回中断した練習を、最後の保存時点まで復元しました。" if recovered else "")
	_refresh();show()

func _toggle_archive()->void:
	archived=not archived;page=0;_show_listing();_refresh()

func _turn(direction:int)->void:
	page+=direction;_refresh()

func _refresh()->void:
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	archive_button.text="現在の記録へ戻る" if archived else "旧バージョンの記録を見る"
	var history:Array=saved.get("legacy_training_history",[]).duplicate(true) if archived else saved.training_history
	if archived:
		for kind in ["bests","legacy_bests","bests_v2","bests_v3"]:
			for key in saved.get(kind,{}):
				history.append({"legacy_best":true,"kind":kind,"key":key,"value":saved[kind][key]})
	var page_size:=4 if not archived and bool(saved.settings.get("score_details",false)) else PAGE_SIZE
	var pages:=maxi(1,ceili(float(history.size())/page_size))
	page=clampi(page,0,pages-1)
	page_label.text="%d / %d"%[page+1,pages];previous.disabled=page==0;next.disabled=page==pages-1
	if history.is_empty():rows.add_child(_text("旧バージョンの記録はありません。" if archived else "まだ練習記録がありません。訓練を開始してみましょう。",18));return
	for index in range(page*page_size,mini(history.size(),(page+1)*page_size)):
		var entry:Dictionary=history[index]
		if entry.get("legacy_best",false):
			var row:=PanelContainer.new();rows.add_child(row)
			row.add_child(_text("旧仕様の自己ベスト（保存値・現在のポイントとは比較不可）\n%s / %s：%s"%[entry.kind,entry.key,str(entry.value)],16));continue
		var metric:="旧仕様スコア %d / 旧補給 %d"%[int(entry.get("score",0)),int(entry.get("credits",0))] if archived else "獲得 %d ポイント　%s %.1f%%"%[int(entry.get("score",0)),"追従率" if int(entry.get("weapon",0))==1 else "命中率",float(entry.get("accuracy",0.0))*100.0]
		var details:=""
		if not archived and bool(saved.settings.get("score_details",false)):
			details="\n基本 %d / 中心 %d / 速度 %d / 連続 %d"%[int(entry.get("base",0)),int(entry.get("center",0)),int(entry.get("speed",0)),int(entry.get("streak",0))]
		var mode_text:=" / "+Balance.duration_label(int(entry.get("duration",0))) if archived else ""
		var select:=Button.new();select.alignment=HORIZONTAL_ALIGNMENT_LEFT;select.text="%s　%s / %s%s　%s\n練習 %s　射撃活動 %s　%s%s"%[str(entry.get("started","")).replace("T"," "),Balance.WEAPONS[clampi(int(entry.get("weapon",0)),0,2)],Balance.DIFFICULTY[clampi(int(entry.get("difficulty",0)),0,2)].name,mode_text,str(entry.get("status","")),Balance.clock_text(float(entry.get("elapsed",0.0))),Balance.clock_text(float(entry.get("active",0.0))),metric,details]
		select.custom_minimum_size.y=68;select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;select.pressed.connect(_select_record.bind(entry));rows.add_child(select)

func _select_record(record:Dictionary)->void:
	record_selected.emit(record.duplicate(true))

func show_detail(model:Dictionary)->void:
	detail_title.text=str(model.get("title", ""))
	detail_review.set_review(model, true)
	listing.hide()
	detail_view.show()

func _show_listing()->void:
	if listing == null:
		return
	detail_view.hide()
	listing.show()
