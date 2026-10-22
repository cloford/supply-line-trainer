extends Node

enum Mode { PREP, ARMY, COUNTDOWN, TRAINING, RESULT, PAUSED, RECORDS }
var session_id:=""
var session_started:=""
var checkpoint_timer:=0.0
var active_seconds:=0.0
var activity_window:=0.0
var auto_points_pending:=0.0
var score_pulse:=0.0
var pulse_cooldown:=0.0
var last_hud_score:=0
var save_warning:=false
var recovered_notice:=false
var target_precisions:Array[float]=[]
var credit_hud:Label
var eta_label:Label
var records_view:PracticeRecords
var data:Dictionary
var mode := Mode.PREP
var mode_before_pause := Mode.PREP
var selected_weapon := 0
var selected_difficulty := 0
var selected_duration := 0
var training_weapon := 0
var training_difficulty := 0
var training_duration := 0
var time_left := 60.0
var countdown := 3.0
var stats := {}
var reward_committed := false
var fire_cooldown := 0.0
var burst_remaining := 0
var burst_timer := 0.0
var mouse_blocked := true
var battle_save_timer := 0.0
var hit_flash := 0.0
var is_test_mode := false

var world:Node3D
var player:CharacterBody3D
var camera:Camera3D
var target_root:Node3D
var targets:Array[StaticBody3D] = []
var target_progress:Array[int] = []
var target_phase := 0.0
var target_spawn_times:Array[float]=[]
var training_elapsed:=0.0
var streak:=0
var last_success_time:=-99.0
var point_display_timer:=0.0
var auto_streak_time:=0.0
var ui:CanvasLayer
var prep_panel:PanelContainer
var army_panel:Control
var hud:Control
var result_panel:Control
var pause_panel:Control
var result_card:PanelContainer
var pause_card:PanelContainer
var supply_label:Label
var front_label:Label
var front_bar:ProgressBar
var power_label:Label
var weapon_buttons:Array[Button] = []
var difficulty_buttons:Array[Button] = []
var duration_buttons:Array[Button] = []
var upgrade_buttons:Array[Button] = []
var condition_label:Label
var difficulty_info:Label
var start_button:Button
var timer_label:Label
var stat_label:Label
var countdown_label:Label
var hit_label:Label
var battle_hud:Label
var battle_progress:ProgressBar
var crosshair:AimCrosshair
var crosshair_preview:AimCrosshair
var battle_view:BattleView
var army_return_mode := Mode.PREP
var army_title:Label
var result_title:Label
var result_detail:Label
var sensitivity_edit:LineEdit
var sensitivity_slider:HSlider
var sensitivity_game:OptionButton
var dpi_spin:SpinBox
var cm_label:Label
var fov_spin:SpinBox
var fov_slider:HSlider
var color_edit:LineEdit
var color_picker:ColorPickerButton
var size_spin:SpinBox
var size_slider:HSlider
var shape_option:OptionButton
var outline_check:CheckBox
var volume_slider:HSlider
var pause_menu:VBoxContainer
var settings_page:VBoxContainer
var settings_scroll:ScrollContainer
var settings_snapshot:Dictionary={}
var settings_dirty:=false
var settings_standalone:=false
var discard_confirm:HBoxContainer
var pause_end_button:Button
var purchase_batch:=1
var batch_row:HBoxContainer
var purchase_lock:=false
var purchase_flash:=0.0
var highlighted_purchase:=-1
var goal_labels:Array[Label]=[]
var goal_details:Array[Label]=[]
var goal_previews:Array[ArmyPreview]=[]
var goal_selectors:Array[HBoxContainer]=[]
var purchase_previews:Array[ArmyPreview]=[]
var gear_preview_detail:Label
var purchase_message:Label
var goal_hud:Label
var goal_notification:Label
var goal_notice_timer:=0.0
var result_goal:Label
var migration_label:Label
var migration_timer:=0.0
var audio_player:AudioStreamPlayer
var hit_audio_player:AudioStreamPlayer
var shot_sound_option:OptionButton
var hit_sound_option:OptionButton
var shot_volume_slider:HSlider
var hit_volume_slider:HSlider
var hit_pitch_check:CheckBox
var hit_sound_cooldown:=0.0
var exit_hold:=0.0
var exit_holding:=false
var exit_ring:Control
var exit_hint:Label
var detail_check:CheckBox
var auto_update_check:CheckBox
var setting_sections:Array[VBoxContainer]=[]
var settings_tabs:HBoxContainer
var session_fraction:=0.0
var feedback_base:=0
var feedback_center:=0
var feedback_other:=0
var app_focused:=true
var feedback_url:="https://github.com/cloford/supply-line-trainer/discussions/3"
var updater:SupplyLineUpdater
var update_labels:Array[Label]=[]
var update_buttons:Array[Button]=[]

func _ready()->void:
	is_test_mode=is_test_mode or "--ui-test" in OS.get_cmdline_user_args()
	if is_test_mode:
		data = SaveManager.defaults()
	else:
		data = SaveManager.load_data()
	recovered_notice=TrainingLedger.recover(data)
	if recovered_notice and not is_test_mode:SaveManager.save_data(data)
	GrowthGoal.ensure(data)
	selected_duration=int(data.selected_duration)
	_build_world()
	_build_ui()
	_apply_settings()
	_show_prep()
	if bool(data.get("growth_migration_notice",false)):
		migration_label.text="購入済みの指揮官装備は部隊強化へ引き継ぎました"
		migration_timer=6.0;data.growth_migration_notice=false
		if not is_test_mode:SaveManager.save_data(data)
	get_viewport().focus_exited.connect(_on_focus_lost)
	get_viewport().focus_entered.connect(func():app_focused=true;_update_battle_view())
	get_tree().set_auto_accept_quit(false)
	SupplyLineUpdater.acknowledge_update()
	if not is_test_mode:
		updater=SupplyLineUpdater.new();add_child(updater)
		updater.status_changed.connect(_update_status)
		updater.ready_changed.connect(func(_ready):_update_status(updater.status))
		_update_status(updater.status)
		if SupplyLineUpdater.available():updater.call_deferred("check",bool(data.settings.auto_update))

func _notification(what:int)->void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _training_session_open():_finish_training(false)
		if not is_test_mode: SaveManager.save_data(data)
		get_tree().quit()

func _credit_can_afford(cost:float)->bool:return BigUInt.compare(str(data.credits),BigUInt.from_float(ceil(cost)))>=0
func _credit_spend(cost:float)->bool:
	if bool(data.get("migration_failed",false)):return false
	var price:=BigUInt.from_float(ceil(cost))
	if BigUInt.compare(str(data.credits),price)<0:return false
	data.credits=BigUInt.subtract(str(data.credits),price);return true
func _credit_text()->String:return BigUInt.format(str(data.credits))

func _build_world()->void:
	world = Node3D.new(); world.name = "TrainingWorld"; add_child(world)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("071018")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("5b7891")
	environment.ambient_light_energy = 0.45
	env.environment = environment; world.add_child(env)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-55,-25,0); light.light_energy = 1.15; light.shadow_enabled = true; world.add_child(light)
	_make_box("Floor", Vector3(20,0.25,24), Vector3(0,-0.125,0), Color("172936"), true)
	_make_box("BackWall", Vector3(20,5,0.3), Vector3(0,2.5,-12), Color("102330"), true)
	_make_box("LeftWall", Vector3(0.3,5,24), Vector3(-10,2.5,0), Color("102330"), true)
	_make_box("RightWall", Vector3(0.3,5,24), Vector3(10,2.5,0), Color("102330"), true)
	for x in [-7.0,-3.5,0.0,3.5,7.0]:
		_make_box("LightStrip", Vector3(0.08,0.08,23.0), Vector3(x,4.8,0), Color("1b6577"), false)
	_make_box("RangeFront",Vector3(12.5,0.025,0.08),Vector3(0,0.02,4.8),Color("55c9e8"),false)
	_make_box("RangeBack",Vector3(12.5,0.025,0.08),Vector3(0,0.02,10.2),Color("55c9e8"),false)
	_make_box("RangeLeft",Vector3(0.08,0.025,5.5),Vector3(-6.2,0.02,7.5),Color("55c9e8"),false)
	_make_box("RangeRight",Vector3(0.08,0.025,5.5),Vector3(6.2,0.02,7.5),Color("55c9e8"),false)
	player = CharacterBody3D.new(); player.name = "Player"; player.position = Vector3(0,1.7,8); player.collision_layer=2; player.collision_mask=1; world.add_child(player)
	var body_shape := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius=0.35; capsule.height=1.7; body_shape.shape=capsule; body_shape.position.y=-0.85; player.add_child(body_shape)
	camera = Camera3D.new(); camera.current=true; camera.near=0.05; player.add_child(camera)
	var gun := MeshInstance3D.new(); var gun_mesh:=BoxMesh.new(); gun_mesh.size=Vector3(0.18,0.16,0.55); gun.mesh=gun_mesh; gun.position=Vector3(0.32,-0.27,-0.55); gun.material_override=_material(Color("394d58")); camera.add_child(gun)
	target_root = Node3D.new(); target_root.name="Targets"; world.add_child(target_root)
	audio_player = AudioStreamPlayer.new(); add_child(audio_player)
	hit_audio_player = AudioStreamPlayer.new(); add_child(hit_audio_player)

func _make_box(node_name:String, size:Vector3, pos:Vector3, color:Color, collision:bool)->void:
	var mesh := MeshInstance3D.new(); mesh.name=node_name; var box:=BoxMesh.new(); box.size=size; mesh.mesh=box; mesh.position=pos; mesh.material_override=_material(color); world.add_child(mesh)
	if collision:
		var body:=StaticBody3D.new(); body.position=pos; var shape:=CollisionShape3D.new(); var box_shape:=BoxShape3D.new(); box_shape.size=size; shape.shape=box_shape; body.add_child(shape); world.add_child(body)

func _material(color:Color)->StandardMaterial3D:
	var m:=StandardMaterial3D.new(); m.albedo_color=color; m.roughness=0.72
	if color.get_luminance()>0.35: m.emission_enabled=true; m.emission=color*0.35
	return m

func _build_ui()->void:
	ui=CanvasLayer.new(); add_child(ui)
	prep_panel=_panel(); prep_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.add_child(prep_panel)
	var prep:=VBoxContainer.new(); prep.add_theme_constant_override("separation",6); prep_panel.add_child(prep)
	var title:=_label("SUPPLY LINE TRAINER",26); title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; prep.add_child(title)
	var center:=CenterContainer.new(); center.size_flags_vertical=Control.SIZE_EXPAND_FILL; prep.add_child(center)
	var train_box:=_section("訓練準備");train_box.add_theme_constant_override("separation",5);train_box.custom_minimum_size=Vector2(620,0); center.add_child(train_box)
	var wtitle:=_label("武器",18); train_box.add_child(wtitle)
	var wr:=HBoxContainer.new(); train_box.add_child(wr)
	for i in 3:
		var b:=Button.new(); b.toggle_mode=true;b.text=Balance.WEAPONS[i]; b.pressed.connect(_select_weapon.bind(i)); b.custom_minimum_size.x=190; wr.add_child(b); weapon_buttons.append(b)
	train_box.add_child(_label("難易度",18))
	var dr:=HBoxContainer.new(); train_box.add_child(dr)
	for i in 3:
		var b:=Button.new(); b.toggle_mode=true;b.text=Balance.DIFFICULTY[i].name; b.pressed.connect(_select_difficulty.bind(i)); b.custom_minimum_size.x=190; dr.add_child(b); difficulty_buttons.append(b)
	difficulty_info=_label("",14);difficulty_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;train_box.add_child(difficulty_info)
	condition_label=_label("",16);condition_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;train_box.add_child(condition_label)
	start_button=Button.new(); start_button.text="訓練開始"; start_button.custom_minimum_size.y=52; start_button.pressed.connect(_start_training); train_box.add_child(start_button)
	train_box.add_child(_label("好きなときに終了できます。獲得ポイントは保存されます。",14))
	train_box.add_child(_label("右クリックを0.8秒長押しで終了／Esc → 訓練を終了",14))
	train_box.add_child(_label("WASD: 移動　マウス: 視点　左クリック: 射撃　Esc: 一時停止",14))
	_build_goal_card(train_box,true)
	migration_label=_label("",14);migration_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;prep.add_child(migration_label)
	var nav:=HBoxContainer.new(); nav.alignment=BoxContainer.ALIGNMENT_CENTER; nav.add_theme_constant_override("separation",12); prep.add_child(nav)
	var army_btn:=Button.new(); army_btn.text="部隊画面"; army_btn.custom_minimum_size=Vector2(220,44); army_btn.pressed.connect(_show_army); nav.add_child(army_btn)
	var settings_btn:=Button.new(); settings_btn.text="設定"; settings_btn.custom_minimum_size=Vector2(160,44); settings_btn.pressed.connect(_open_settings_from_screen); nav.add_child(settings_btn)
	var records_btn:=Button.new();records_btn.text="練習記録";records_btn.custom_minimum_size=Vector2(160,44);records_btn.pressed.connect(_show_records);nav.add_child(records_btn)
	var feedback:=Button.new();feedback.text="意見を送る";feedback.custom_minimum_size=Vector2(160,44);feedback.pressed.connect(func():OS.shell_open(feedback_url));nav.add_child(feedback)
	_build_update_controls(prep)
	records_view=PracticeRecords.new();records_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.add_child(records_view);records_view.closed.connect(_show_prep);records_view.hide()
	_build_army_screen()

	hud=Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; ui.add_child(hud)
	timer_label=_label("60.0",28); timer_label.position=Vector2(24,20); hud.add_child(timer_label)
	stat_label=_label("",18); stat_label.position=Vector2(24,60); hud.add_child(stat_label)
	battle_hud=_label("",15); battle_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); battle_hud.position=Vector2(-360,20); battle_hud.size=Vector2(335,90); battle_hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; hud.add_child(battle_hud)
	battle_progress=ProgressBar.new();battle_progress.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);battle_progress.offset_left=-250;battle_progress.offset_right=-24;battle_progress.offset_top=74;battle_progress.offset_bottom=82;battle_progress.show_percentage=false;battle_progress.max_value=1.0;hud.add_child(battle_progress)
	countdown_label=_label("",54);countdown_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);countdown_label.offset_top=82;countdown_label.offset_bottom=162;countdown_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;hud.add_child(countdown_label)
	hit_label=_label("",20); hit_label.position=Vector2(24,132); hit_label.size=Vector2(360,40); hit_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT; hud.add_child(hit_label)
	credit_hud=_label("",17);credit_hud.position=Vector2(24,94);hud.add_child(credit_hud)
	goal_hud=_label("",15);goal_hud.position=Vector2(24,174);goal_hud.size=Vector2(510,48);goal_hud.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hud.add_child(goal_hud)
	goal_notification=_label("",15);goal_notification.position=Vector2(24,226);hud.add_child(goal_notification)
	crosshair=AimCrosshair.new(); crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(crosshair)
	exit_ring=load("res://exit_ring.gd").new();exit_ring.position=Vector2(24,260);exit_ring.size=Vector2(40,40);hud.add_child(exit_ring);exit_ring.hide()
	exit_hint=_label("離すとキャンセル",16);exit_hint.position=Vector2(72,267);hud.add_child(exit_hint);exit_hint.hide()
	var result_parts:=_modal_overlay(570.0); result_panel=result_parts[0]; result_card=result_parts[1]; ui.add_child(result_panel)
	var rv:=VBoxContainer.new(); rv.add_theme_constant_override("separation",14)
	result_card.add_child(rv)
	result_title=_label("訓練結果",28); result_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; rv.add_child(result_title)
	result_detail=_label("",18); result_detail.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; rv.add_child(result_detail)
	result_goal=_label("",16);result_goal.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rv.add_child(result_goal)
	var retry:=Button.new(); retry.text="再挑戦"; retry.custom_minimum_size.y=48; retry.pressed.connect(_start_training); rv.add_child(retry)
	var back:=Button.new(); back.text="条件を変更"; back.pressed.connect(_show_prep); rv.add_child(back)
	var army_result:=Button.new();army_result.text="部隊へ";army_result.pressed.connect(_army_from_goal);rv.add_child(army_result)
	pause_panel=_build_pause_panel(); ui.add_child(pause_panel)
	_refresh_prep()

func _modal_overlay(card_width:float)->Array:
	var overlay:=ColorRect.new(); overlay.color=Color("02070bb8"); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",24); margin.add_theme_constant_override("margin_right",24); margin.add_theme_constant_override("margin_top",24); margin.add_theme_constant_override("margin_bottom",24); overlay.add_child(margin)
	var center:=CenterContainer.new(); margin.add_child(center)
	var card:=_panel(); card.custom_minimum_size.x=card_width; card.size_flags_horizontal=Control.SIZE_SHRINK_CENTER; card.size_flags_vertical=Control.SIZE_SHRINK_CENTER; center.add_child(card)
	return [overlay,card]

func _build_army_screen()->void:
	army_panel=ColorRect.new();army_panel.color=Color("071019");army_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.add_child(army_panel)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);margin.add_theme_constant_override("margin_left",16);margin.add_theme_constant_override("margin_right",16);margin.add_theme_constant_override("margin_top",16);margin.add_theme_constant_override("margin_bottom",16);army_panel.add_child(margin)
	var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",16);margin.add_child(columns)
	var left_panel:=_panel();left_panel.custom_minimum_size.x=330;left_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left_panel.size_flags_stretch_ratio=0.34;columns.add_child(left_panel)
	var left:=VBoxContainer.new();left.add_theme_constant_override("separation",4);left_panel.add_child(left)
	army_title=_label("部隊",22);left.add_child(army_title)
	supply_label=_label("",18);left.add_child(supply_label)
	power_label=_label("",18);left.add_child(power_label)
	front_label=_label("",17);left.add_child(front_label)
	front_bar=ProgressBar.new();front_bar.custom_minimum_size.y=12;front_bar.show_percentage=false;left.add_child(front_bar)
	eta_label=_label("",16);left.add_child(eta_label)
	for i in 2:
		var b:=Button.new();b.custom_minimum_size.y=44;b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;b.pressed.connect(_buy_upgrade.bind(i));left.add_child(b);upgrade_buttons.append(b)
		var preview:=ArmyPreview.new();preview.custom_minimum_size=Vector2(260,36);left.add_child(preview);purchase_previews.append(preview)
		if i==1:gear_preview_detail=_label("",14);gear_preview_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;left.add_child(gear_preview_detail)
	batch_row=HBoxContainer.new();left.add_child(batch_row)
	for amount in [1,5,10]:
		var bb:=Button.new();bb.text="×%d"%amount;bb.toggle_mode=true;bb.button_pressed=amount==1;bb.pressed.connect(_set_purchase_batch.bind(amount,batch_row));batch_row.add_child(bb)
	_build_goal_card(left,false)
	purchase_message=_label("",14);purchase_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;left.add_child(purchase_message);purchase_message.hide()
	var spacer:=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(spacer)
	var back:=Button.new();back.text="訓練準備へ戻る";back.custom_minimum_size.y=40;back.pressed.connect(_leave_army);left.add_child(back)
	var right_panel:=_panel();right_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right_panel.size_flags_stretch_ratio=0.66;columns.add_child(right_panel)
	var right:=VBoxContainer.new();right_panel.add_child(right)
	var heading:=_label("進軍状況",24);heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;right.add_child(heading)
	battle_view=BattleView.new();battle_view.custom_minimum_size=Vector2(480,400);battle_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;battle_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.add_child(battle_view)

func _panel()->PanelContainer:
	var p:=PanelContainer.new(); var sb:=StyleBoxFlat.new(); sb.bg_color=Color("0a1722e8"); sb.border_color=Color("295266"); sb.set_border_width_all(1); sb.set_corner_radius_all(8); sb.content_margin_left=24; sb.content_margin_right=24; sb.content_margin_top=20; sb.content_margin_bottom=20; p.add_theme_stylebox_override("panel",sb); return p

func _section(title:String)->VBoxContainer:
	var v:=VBoxContainer.new(); v.add_theme_constant_override("separation",8); v.add_child(_label(title,22)); return v

func _label(text:String,size:int)->Label:
	var l:=Label.new(); l.text=text; l.add_theme_font_size_override("font_size",size); l.add_theme_color_override("font_color",Color("d7eff8")); return l

func _build_pause_panel()->Control:
	var overlay:=ColorRect.new(); overlay.color=Color("02070bd8"); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.resized.connect(_resize_pause_card.bind(overlay))
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",24); margin.add_theme_constant_override("margin_right",24); margin.add_theme_constant_override("margin_top",24); margin.add_theme_constant_override("margin_bottom",24); overlay.add_child(margin)
	var center:=CenterContainer.new(); margin.add_child(center)
	pause_card=_panel(); pause_card.custom_minimum_size.x=520; pause_card.size_flags_horizontal=Control.SIZE_SHRINK_CENTER; pause_card.size_flags_vertical=Control.SIZE_EXPAND_FILL; center.add_child(pause_card)
	var outer:=VBoxContainer.new();outer.add_theme_constant_override("separation",10);pause_card.add_child(outer)
	pause_menu=VBoxContainer.new();pause_menu.add_theme_constant_override("separation",12);outer.add_child(pause_menu)
	var pt:=_label("一時停止",28);pt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;pause_menu.add_child(pt)
	var resume:=Button.new();resume.text="再開";resume.custom_minimum_size.y=52;resume.pressed.connect(_resume_pause);pause_menu.add_child(resume)
	var settings_button:=Button.new();settings_button.text="設定";settings_button.custom_minimum_size.y=52;settings_button.pressed.connect(_open_settings_page);pause_menu.add_child(settings_button)
	pause_end_button=Button.new();pause_end_button.text="訓練を終了";pause_end_button.custom_minimum_size.y=52;pause_end_button.pressed.connect(_end_early);pause_menu.add_child(pause_end_button)
	settings_page=VBoxContainer.new();settings_page.size_flags_vertical=Control.SIZE_EXPAND_FILL;settings_page.add_theme_constant_override("separation",8);outer.add_child(settings_page)
	var st:=_label("設定",26);st.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;settings_page.add_child(st)
	settings_tabs=HBoxContainer.new();settings_page.add_child(settings_tabs)
	for index in 4:
		var tab:=Button.new();tab.text=["操作","照準","音","更新／情報"][index];tab.toggle_mode=true;tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL;tab.pressed.connect(_select_settings_tab.bind(index));settings_tabs.add_child(tab)
	var preview_box:=PanelContainer.new();preview_box.custom_minimum_size.y=72;settings_page.add_child(preview_box)
	crosshair_preview=AimCrosshair.new();crosshair_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview_box.add_child(crosshair_preview)
	settings_scroll=ScrollContainer.new();settings_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;settings_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;settings_page.add_child(settings_scroll)
	var settings_body:=VBoxContainer.new();settings_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;settings_scroll.add_child(settings_body)
	for index in 4:
		var section:=VBoxContainer.new();section.size_flags_horizontal=Control.SIZE_EXPAND_FILL;section.add_theme_constant_override("separation",6);settings_body.add_child(section);setting_sections.append(section)
	var v:VBoxContainer=setting_sections[0]
	v.add_child(_label("感度基準ゲーム",15));sensitivity_game=OptionButton.new()
	for preset in Balance.SENSITIVITY_PRESETS:sensitivity_game.add_item(preset.name)
	sensitivity_game.item_selected.connect(func(_value):_settings_changed());v.add_child(sensitivity_game)
	v.add_child(_label("ゲーム内感度",15));sensitivity_edit=LineEdit.new();sensitivity_edit.text_changed.connect(func(_value):_settings_changed());v.add_child(sensitivity_edit)
	sensitivity_slider=HSlider.new();sensitivity_slider.min_value=0.001;sensitivity_slider.max_value=10;sensitivity_slider.step=0.001;sensitivity_slider.value_changed.connect(_sensitivity_slider_changed);v.add_child(sensitivity_slider)
	v.add_child(_label("DPI（表示計算用）",15));dpi_spin=SpinBox.new();dpi_spin.min_value=100;dpi_spin.max_value=64000;dpi_spin.step=50;dpi_spin.value_changed.connect(func(_value):_settings_changed());v.add_child(dpi_spin)
	cm_label=_label("",14);v.add_child(cm_label)
	v.add_child(_label("水平FOV（4:3基準）",15));fov_spin=SpinBox.new();fov_spin.min_value=75;fov_spin.max_value=110;fov_spin.step=0.1;fov_spin.value_changed.connect(_fov_spin_changed);v.add_child(fov_spin)
	fov_slider=HSlider.new();fov_slider.min_value=75;fov_slider.max_value=110;fov_slider.step=0.1;fov_slider.value_changed.connect(_fov_slider_changed);v.add_child(fov_slider)
	v=setting_sections[1]
	v.add_child(_label("クロスヘア形状",15));shape_option=OptionButton.new()
	for shape_name in ["点","十字","隙間付き十字","円"]:shape_option.add_item(shape_name)
	shape_option.item_selected.connect(func(_value):_settings_changed());v.add_child(shape_option)
	v.add_child(_label("クロスヘア色",15));var color_row:=HBoxContainer.new();v.add_child(color_row);color_edit=LineEdit.new();color_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;color_edit.text_changed.connect(_color_text_changed);color_row.add_child(color_edit);color_picker=ColorPickerButton.new();color_picker.color_changed.connect(_color_picker_changed);color_row.add_child(color_picker)
	v.add_child(_label("クロスヘアサイズ",15));size_spin=SpinBox.new();size_spin.min_value=4;size_spin.max_value=30;size_spin.value_changed.connect(_size_spin_changed);v.add_child(size_spin);size_slider=HSlider.new();size_slider.min_value=4;size_slider.max_value=30;size_slider.step=1;size_slider.value_changed.connect(_size_slider_changed);v.add_child(size_slider)
	outline_check=CheckBox.new();outline_check.text="補助輪郭";outline_check.toggled.connect(func(_value):_settings_changed());v.add_child(outline_check)
	detail_check=CheckBox.new();detail_check.text="加点の基本・中心追加の内訳を表示";detail_check.toggled.connect(func(_value):_settings_changed());v.add_child(detail_check)
	v=setting_sections[2]
	v.add_child(_label("全体音量",15));volume_slider=HSlider.new();volume_slider.min_value=0;volume_slider.max_value=1;volume_slider.step=0.01;volume_slider.value_changed.connect(func(_value):_settings_changed());v.add_child(volume_slider)
	v.add_child(_label("射撃音",18));shot_sound_option=OptionButton.new();
	for sound_name in ["銃声風","軽い機械音","柔らかな電子音","なし"]:shot_sound_option.add_item(sound_name)
	shot_sound_option.item_selected.connect(func(_value):_settings_changed());v.add_child(shot_sound_option)
	shot_volume_slider=HSlider.new();shot_volume_slider.min_value=0;shot_volume_slider.max_value=1;shot_volume_slider.step=0.01;shot_volume_slider.value_changed.connect(func(_value):_settings_changed());v.add_child(shot_volume_slider)
	var shot_preview:=Button.new();shot_preview.text="射撃音を試聴";shot_preview.pressed.connect(_preview_shot_sound);v.add_child(shot_preview)
	v.add_child(_label("命中音",18));hit_sound_option=OptionButton.new()
	for sound_name in ["クリック","金属音","短い電子音","なし"]:hit_sound_option.add_item(sound_name)
	hit_sound_option.item_selected.connect(func(_value):_settings_changed());v.add_child(hit_sound_option)
	hit_volume_slider=HSlider.new();hit_volume_slider.min_value=0;hit_volume_slider.max_value=1;hit_volume_slider.step=0.01;hit_volume_slider.value_changed.connect(func(_value):_settings_changed());v.add_child(hit_volume_slider)
	hit_pitch_check=CheckBox.new();hit_pitch_check.text="連続成功で音程を上げる";hit_pitch_check.toggled.connect(func(_value):_settings_changed());v.add_child(hit_pitch_check)
	var hit_preview:=Button.new();hit_preview.text="命中音を試聴";hit_preview.pressed.connect(_preview_hit_sound);v.add_child(hit_preview)
	v=setting_sections[3]
	v.add_child(_label("Supply Line Trainer v1.5.0",20))
	auto_update_check=CheckBox.new();auto_update_check.text="新しい安定版を自動取得";auto_update_check.toggled.connect(func(_value):_settings_changed());v.add_child(auto_update_check)
	_build_update_controls(v)
	_select_settings_tab(0)
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",6);settings_page.add_child(actions)
	for spec in [["適用",_apply_settings_draft],["変更を取り消す",_cancel_settings_changes],["初期値に戻す",_reset_settings_draft],["戻る",_settings_back]]:
		var b:=Button.new();b.text=spec[0];b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.pressed.connect(spec[1]);actions.add_child(b)
	discard_confirm=HBoxContainer.new();discard_confirm.add_child(_label("未適用の変更を破棄しますか？",14));var discard:=Button.new();discard.text="破棄";discard.pressed.connect(_confirm_discard);discard_confirm.add_child(discard);var keep:=Button.new();keep.text="編集を続ける";keep.pressed.connect(func():discard_confirm.hide());discard_confirm.add_child(keep);settings_page.add_child(discard_confirm)
	settings_page.hide();discard_confirm.hide()
	call_deferred("_resize_pause_card",overlay)
	return overlay

func _resize_pause_card(overlay:Control)->void:
	if not pause_card: return
	pause_card.custom_minimum_size=Vector2(maxf(300.0,minf(520.0,overlay.size.x-48.0)),maxf(220.0,minf(620.0,overlay.size.y-48.0)))

func _select_settings_tab(index:int)->void:
	for i in setting_sections.size():
		setting_sections[i].visible=i==index
		settings_tabs.get_child(i).set_pressed_no_signal(i==index)
	if settings_scroll:settings_scroll.scroll_vertical=0

func _build_update_controls(parent:Node)->void:
	var status:=_label("v1.5.0",14);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(status);update_labels.append(status)
	var row:=HBoxContainer.new();parent.add_child(row)
	var check:=Button.new();check.text="更新を確認";check.pressed.connect(func():if updater:updater.check(true));row.add_child(check)
	var apply:=Button.new();apply.text="再起動して更新";apply.disabled=true;apply.pressed.connect(_apply_update);row.add_child(apply);update_buttons.append(apply)

func _update_status(message:String)->void:
	for label in update_labels:label.text="v1.5.0　"+message
	for button in update_buttons:button.disabled=not updater or not updater.ready_to_apply

func _apply_update()->void:
	if not updater or not updater.ready_to_apply or _training_session_open():return
	if not SaveManager.save_data(data):_update_status("保存に失敗したため更新を中止しました");return
	updater.apply_update()

func _sync_settings_controls(source:Dictionary)->void:
	detail_check.set_pressed_no_signal(bool(source.get("score_details",true)));auto_update_check.set_pressed_no_signal(bool(source.get("auto_update",true)))
	sensitivity_game.select(int(source.sensitivity_game));sensitivity_edit.text=str(source.sensitivity);sensitivity_slider.set_value_no_signal(float(source.sensitivity));dpi_spin.set_value_no_signal(float(source.dpi));fov_spin.set_value_no_signal(float(source.fov));fov_slider.set_value_no_signal(float(source.fov));color_edit.text=str(source.crosshair_color);color_picker.color=Color(str(source.crosshair_color));size_spin.set_value_no_signal(float(source.crosshair_size));size_slider.set_value_no_signal(float(source.crosshair_size));shape_option.select(int(source.crosshair_shape));outline_check.button_pressed=bool(source.crosshair_outline);volume_slider.set_value_no_signal(float(source.volume));shot_sound_option.select(int(source.shot_sound));shot_volume_slider.set_value_no_signal(float(source.shot_volume));hit_sound_option.select(int(source.hit_sound));hit_volume_slider.set_value_no_signal(float(source.hit_volume));hit_pitch_check.set_pressed_no_signal(bool(source.hit_pitch_combo));_settings_changed()
func _draft_settings()->Dictionary:return {"sensitivity":clampf(float(sensitivity_edit.text),0.001,100.0),"sensitivity_game":sensitivity_game.selected,"dpi":dpi_spin.value,"fov":fov_spin.value,"crosshair_color":color_edit.text if Color.html_is_valid(color_edit.text) else "66e8ff","crosshair_size":size_spin.value,"crosshair_shape":shape_option.selected,"crosshair_outline":outline_check.button_pressed,"volume":volume_slider.value,"shot_sound":shot_sound_option.selected,"shot_volume":shot_volume_slider.value,"hit_sound":hit_sound_option.selected,"hit_volume":hit_volume_slider.value,"hit_pitch_combo":hit_pitch_check.button_pressed,"score_details":detail_check.button_pressed,"auto_update":auto_update_check.button_pressed}
func _settings_changed()->void:
	if not crosshair_preview:return
	settings_dirty=_draft_settings()!=settings_snapshot
	var d:=_draft_settings();crosshair_preview.set_appearance(d.crosshair_color,d.crosshair_size,d.crosshair_shape,d.crosshair_outline);cm_label.text="実効係数 %.3f°/count　%.2f cm/360%s"%[Balance.effective_coefficient(d.sensitivity_game)*d.sensitivity,Balance.cm_per_360(d.sensitivity_game,d.sensitivity,d.dpi),"（互換用候補）" if not Balance.SENSITIVITY_PRESETS[d.sensitivity_game].official else ""]
func _sensitivity_slider_changed(value:float)->void:sensitivity_edit.text="%.3f"%value
func _fov_spin_changed(value:float)->void:fov_slider.set_value_no_signal(value);_settings_changed()
func _fov_slider_changed(value:float)->void:fov_spin.set_value_no_signal(value);_settings_changed()
func _size_spin_changed(value:float)->void:size_slider.set_value_no_signal(value);_settings_changed()
func _size_slider_changed(value:float)->void:size_spin.set_value_no_signal(value);_settings_changed()
func _color_text_changed(value:String)->void:
	if Color.html_is_valid(value):color_picker.color=Color(value)
	_settings_changed()
func _color_picker_changed(value:Color)->void:color_edit.text=value.to_html(false)

func _select_weapon(i:int)->void: selected_weapon=i; _refresh_prep()
func _select_difficulty(i:int)->void: selected_difficulty=i; _refresh_prep()
func _select_duration(seconds:int)->void:selected_duration=seconds;data.selected_duration=seconds;_refresh_prep()

func _refresh_prep()->void:
	if not supply_label: return
	supply_label.text="所持ポイント: %s P"%_credit_text()
	power_label.text="%s　部隊装備 Lv.%d"%[Balance.format_soldiers(int(data.recruit)),int(data.gear)]
	var costs:=[_upgrade_total_cost(0),_upgrade_total_cost(1)]
	var names:=["増員","部隊装備"]
	gear_preview_detail.text=ArmyAppearance.description(int(data.gear),int(data.gear)+purchase_batch)
	var effects:=["%s → %s"%[Balance.format_soldiers(int(data.recruit)),Balance.format_soldiers(int(data.recruit)+purchase_batch)],"Lv.%d → Lv.%d"%[int(data.gear),int(data.gear)+purchase_batch]]
	for i in 2:
		var stronger:=data.duplicate(true);stronger[["recruit","gear"][i]]=int(stronger[["recruit","gear"][i]])+purchase_batch
		var percent:=(Balance.army_power(stronger)/maxf(0.001,Balance.army_power(data))-1.0)*100.0
		upgrade_buttons[i].text="%s ×%d　%s\n%s P / 戦闘力 +%.0f%%%s"%[names[i],purchase_batch,effects[i],Balance.format_number(costs[i]),percent,"（不足）" if not _credit_can_afford(costs[i]) else ""]
		upgrade_buttons[i].disabled=not _credit_can_afford(costs[i]) or bool(data.get("migration_failed",false))
		var after:=_appearance_state();after[["soldiers","gear"][i]]=Balance.soldier_count(int(data.recruit)+purchase_batch) if i==0 else int(data.gear)+purchase_batch
		purchase_previews[i].set_comparison(i,_appearance_state(),after)
	for i in 3:
		weapon_buttons[i].disabled=not bool(data.unlocked[i]);weapon_buttons[i].text=("✓ " if i==selected_weapon else "　")+Balance.WEAPONS[i]+("" if data.unlocked[i] else "（戦線%dで開放）"%([0,3,7][i]));weapon_buttons[i].set_pressed_no_signal(i==selected_weapon)
		difficulty_buttons[i].text=("✓ " if i==selected_difficulty else "　")+Balance.DIFFICULTY[i].name;difficulty_buttons[i].set_pressed_no_signal(i==selected_difficulty)
	for i in duration_buttons.size():duration_buttons[i].text=("✓ " if Balance.TRAINING_DURATIONS[i]==selected_duration else "　")+Balance.duration_label(Balance.TRAINING_DURATIONS[i]);duration_buttons[i].set_pressed_no_signal(Balance.TRAINING_DURATIONS[i]==selected_duration)
	if not bool(data.unlocked[selected_weapon]): selected_weapon=0
	difficulty_info.text="%s\n標的の中心に近いほど追加点。中心マークの外でも命中で基本点。"%Balance.DIFFICULTY[selected_difficulty].description
	condition_label.text="選択中：%s / %s"%[Balance.WEAPONS[selected_weapon],Balance.DIFFICULTY[selected_difficulty].name]
	start_button.disabled=bool(data.get("migration_failed",false))
	if start_button.disabled:condition_label.text="セーブ読込またはバックアップに失敗しました。元セーブを保持し、訓練・購入・保存を停止しています。";condition_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var maxhp:=Balance.front_hp(int(data.front));front_label.text="戦線 %d　%s"%[int(data.front)+1,Balance.front_name(int(data.front))];front_bar.max_value=maxhp;front_bar.value=maxhp-float(data.enemy_hp)
	if army_title:army_title.text="部隊"
	_refresh_goals()
	_update_battle_view()

func _refresh_army_runtime()->void:
	supply_label.text="所持ポイント: %s P"%_credit_text();power_label.text="%s　部隊装備 Lv.%d"%[Balance.format_soldiers(int(data.recruit)),int(data.gear)];var maxhp:=Balance.front_hp(int(data.front));front_label.text="戦線 %d　%s"%[int(data.front)+1,Balance.front_name(int(data.front))];front_bar.max_value=maxhp;front_bar.value=maxhp-float(data.enemy_hp)
	_update_battle_view()

func _update_battle_view()->void:
	if not battle_view: return
	_update_battle_hud()
	if eta_label:eta_label.text="次の突破まで "+Balance.eta_text(float(data.enemy_hp),Balance.army_power(data)*0.18,mode!=Mode.PAUSED and app_focused)
	var front_index:=int(data.front);battle_view.set_state({"soldiers":Balance.soldier_count(int(data.recruit)),"soldier_label":Balance.format_soldiers(int(data.recruit)),"gear":int(data.gear),"front":front_index,"enemy_hp":float(data.enemy_hp),"enemy_max":Balance.front_hp(front_index),"running":mode!=Mode.PAUSED and app_focused})

func _buy_upgrade(kind:int)->void:
	if mode!=Mode.ARMY or purchase_lock:return
	purchase_lock=true
	var before:=_appearance_state()
	var candidate:=GrowthGoal.transaction(data,kind,purchase_batch)
	if not candidate.is_empty():
		if is_test_mode or SaveManager.save_data(candidate):
			data=candidate
			purchase_message.hide()
			battle_view.play_purchase(kind,before,_appearance_state())
			_refresh_prep()
		else:
			save_warning=true
			purchase_message.text="保存に失敗したため購入を取り消しました。空き容量や保存先を確認してください。";purchase_message.show()
	call_deferred("_unlock_purchase")

func _unlock_purchase()->void:
	await get_tree().create_timer(0.20).timeout
	purchase_lock=false

func _appearance_state()->Dictionary:
	return {"soldiers":Balance.soldier_count(int(data.recruit)),"gear":int(data.gear)}

func _build_goal_card(parent:Node,with_preview:bool)->void:
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",3);parent.add_child(column)
	var row:=HBoxContainer.new();column.add_child(row)
	var text_column:=VBoxContainer.new();text_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text_column)
	var title:=_label("",14);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text_column.add_child(title);goal_labels.append(title)
	var detail:=_label("",14);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text_column.add_child(detail);goal_details.append(detail)
	if with_preview:
		var preview:=ArmyPreview.new();preview.custom_minimum_size=Vector2(210,52);row.add_child(preview);goal_previews.append(preview)
	var choices:=HBoxContainer.new();column.add_child(choices);goal_selectors.append(choices)
	for kind in 2:
		var button:=Button.new();button.text=["増員を目標","部隊装備を目標"][kind];button.toggle_mode=true;button.pressed.connect(_select_goal.bind(kind));choices.add_child(button)

func _select_goal(kind:int)->void:
	if mode not in [Mode.PREP,Mode.ARMY] or bool(data.get("migration_failed",false)):return
	var candidate:=data.duplicate(true);GrowthGoal.choose(candidate,kind)
	if is_test_mode or SaveManager.save_data(candidate):data=candidate;_refresh_goals()

func _goal_balance()->String:
	return GrowthGoal.available(data,_session_record() if _training_session_open() else {})

func _goal_status(available:String)->String:
	var missing:=GrowthGoal.missing(data,available)
	return "購入可能（部隊画面で購入）" if missing=="0" else "あと %s P（必要 %s P）"%[BigUInt.format(missing),BigUInt.format(GrowthGoal.price(data,int(data.upgrade_goal.kind)))]

func _refresh_goals()->void:
	var kind:=int(data.upgrade_goal.kind)
	var title:="次の目標："+GrowthGoal.title(data)
	var status:=_goal_status(_goal_balance())
	var explanation:="援軍が合流し、隊列が厚くなります" if kind==0 else ArmyAppearance.description(int(data.gear),int(data.gear)+1)
	for index in goal_labels.size():
		goal_labels[index].text=title+"\n"+status
		goal_details[index].text=explanation
	for row in goal_selectors:
		for index in 2:
			row.get_child(index).text=("✓ " if index==kind else "")+["増員を目標","部隊装備を目標"][index]
			row.get_child(index).set_pressed_no_signal(index==kind)
	var after:=_appearance_state()
	if kind==0:after.soldiers=Balance.soldier_count(int(data.recruit)+1)
	else:after.gear=int(data.gear)+1
	for preview in goal_previews:preview.set_comparison(kind,_appearance_state(),after)
	if result_goal:result_goal.text=title+"\n"+status

func _refresh_goal_hud()->void:
	var available:=_goal_balance()
	goal_hud.text="次の目標："+GrowthGoal.title(data)+"\n"+_goal_status(available)
	if mode==Mode.TRAINING and GrowthGoal.poll(data,available):
		goal_notice_timer=1.5;goal_notification.text="目標分のポイントが貯まりました";goal_notification.show()
		_play_synth(hit_audio_player,int(data.settings.hit_sound),true,float(data.settings.hit_volume)*0.7,1.05)

func _army_from_goal()->void:
	_show_army();_set_purchase_batch(1,batch_row)
	highlighted_purchase=int(data.upgrade_goal.kind);purchase_flash=1.2

func _update_growth_feedback(delta:float)->void:
	if mode==Mode.PAUSED or not app_focused:return
	goal_notice_timer=maxf(0.0,goal_notice_timer-delta)
	if goal_notification:goal_notification.visible=goal_notice_timer>0
	migration_timer=maxf(0.0,migration_timer-delta)
	if migration_label and migration_timer<=0:migration_label.text=""
	purchase_flash=maxf(0.0,purchase_flash-delta)
	for index in upgrade_buttons.size():upgrade_buttons[index].modulate=Color("9dffe0") if index==highlighted_purchase and purchase_flash>0 else Color.WHITE

func _upgrade_total_cost(kind:int)->float:
	var level:=int(data[["recruit","gear"][kind]]);var total:=0.0
	for offset in purchase_batch:total+=([Balance.recruit_cost(level+offset),Balance.gear_cost(level+offset)][kind])
	return total
func _set_purchase_batch(amount:int,row:HBoxContainer)->void:
	purchase_batch=amount
	for child in row.get_children():child.set_pressed_no_signal(child.text=="×%d"%amount)
	_refresh_prep()

func _show_prep()->void:
	_reset_exit_hold();burst_remaining=0
	records_view.hide();mode=Mode.PREP; Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; _clear_targets(); prep_panel.show(); army_panel.hide(); hud.hide(); result_panel.hide(); pause_panel.hide(); _refresh_prep()

func _show_army()->void:
	_reset_exit_hold();burst_remaining=0
	army_return_mode=Mode.PREP
	records_view.hide();mode=Mode.ARMY; mouse_blocked=true; Input.action_release("shoot"); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	prep_panel.hide();hud.hide();result_panel.hide();pause_panel.hide();army_panel.show();_refresh_prep()

func _leave_army()->void:
	army_panel.hide()
	_show_prep()

func _show_records()->void:
	_reset_exit_hold();burst_remaining=0
	mode=Mode.RECORDS;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	prep_panel.hide();army_panel.hide();hud.hide();result_panel.hide();pause_panel.hide()
	records_view.open(data,recovered_notice)

func _start_training()->void:
	if bool(data.get("migration_failed",false)):return
	if updater and updater.is_applying():return
	_reset_exit_hold()
	feedback_base=0;feedback_center=0;feedback_other=0
	selected_duration=0;session_fraction=float(data.get("credit_fraction",0.0))
	session_id="%d_%d"%[int(Time.get_unix_time_from_system()*1000),Time.get_ticks_usec()]
	session_started=Time.get_datetime_string_from_system(false,true)
	checkpoint_timer=0;active_seconds=0;activity_window=0;auto_points_pending=0;score_pulse=0;pulse_cooldown=0;last_hud_score=0;save_warning=false
	records_view.hide()
	training_weapon=selected_weapon;training_difficulty=selected_difficulty;training_duration=selected_duration;time_left=float(training_duration);training_elapsed=0.0;countdown=3.0;reward_committed=false;stats={"shots":0,"hits":0,"kills":0,"track_time":0.0,"fire_time":0.0,"base_points":0.0,"center_bonus":0.0,"speed_bonus":0.0,"streak_bonus":0.0};fire_cooldown=0;burst_remaining=0;burst_timer=0;target_phase=0;streak=0;last_success_time=-99.0;auto_streak_time=0;point_display_timer=0;hit_label.text="";hit_flash=0;player.position=Vector3(0,1.7,8);player.rotation=Vector3.ZERO;camera.rotation=Vector3.ZERO
	audio_player.stop();hit_audio_player.stop();hit_sound_cooldown=0.0
	prep_panel.hide(); army_panel.hide(); result_panel.hide(); pause_panel.hide(); hud.show(); crosshair.show(); mode=Mode.COUNTDOWN; mouse_blocked=true; Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; _spawn_targets();_update_hud()

func _spawn_targets()->void:
	_clear_targets(); var count:=3 if training_weapon==2 else 1
	for i in count:
		var body:=StaticBody3D.new(); body.set_meta("target_index",i); target_root.add_child(body)
		var mesh:=MeshInstance3D.new(); var sphere:=SphereMesh.new(); sphere.radius=float(Balance.DIFFICULTY[training_difficulty].radius); sphere.height=sphere.radius*2.0; mesh.mesh=sphere; mesh.material_override=_material(Color("58edff") if training_weapon!=2 else Color("ffb84a")); body.add_child(mesh)
		var ring:=MeshInstance3D.new(); var torus:=TorusMesh.new(); torus.inner_radius=sphere.radius*0.48; torus.outer_radius=sphere.radius*0.62; ring.mesh=torus; ring.rotation_degrees.x=90; ring.material_override=_material(Color("ffffff")); body.add_child(ring)
		var shape:=CollisionShape3D.new(); var ss:=SphereShape3D.new(); ss.radius=sphere.radius; shape.shape=ss; body.add_child(shape)
		var marker:=MeshInstance3D.new();marker.name="CenterMark";var dot:=SphereMesh.new();dot.radius=sphere.radius*0.12;dot.height=dot.radius*2;marker.mesh=dot;marker.material_override=_material(Color("ff395c"));marker.position=Vector3(0,0,sphere.radius*1.015);body.add_child(marker)
		targets.append(body);target_progress.append(0);target_spawn_times.append(0.0);target_precisions.append(0.0)
		if training_weapon==1:body.position=_auto_position(0.0)
		else:_relocate_target(i)
	_update_targets(0.0)

func _clear_targets()->void:
	for child in target_root.get_children(): child.queue_free()
	targets.clear();target_progress.clear();target_spawn_times.clear();target_precisions.clear()

func _relocate_target(i:int)->void:
	if i>=targets.size(): return
	var r:float=Balance.DIFFICULTY[training_difficulty].range
	var previous:=targets[i].position;var candidate:=Vector3.ZERO
	for attempt in 20:
		candidate=Vector3(randf_range(-r,r),randf_range(1.1,4.1),randf_range(-10.5,-5.0))
		var valid:=candidate.distance_to(previous)>2.5
		for j in targets.size():
			if j!=i and candidate.distance_to(targets[j].position)<1.6:valid=false
		if valid:break
	targets[i].position=candidate;target_progress[i]=0;target_precisions[i]=0;target_spawn_times[i]=training_elapsed

func _auto_position(phase:float)->Vector3:
	var r:float=Balance.DIFFICULTY[training_difficulty].range
	return Vector3(sin(phase)*r,2.45+sin(phase*0.63)*1.15,-7.5+cos(phase*0.37)*1.5)

func _unhandled_input(event:InputEvent)->void:
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("pause"):
		var focus:=get_viewport().gui_get_focus_owner()
		if focus is LineEdit:
			focus.release_focus();get_viewport().set_input_as_handled();return
		if mode==Mode.PAUSED:
			_close_pause()
		elif mode in [Mode.COUNTDOWN,Mode.TRAINING]:
			_open_pause()
		return
	if mode not in [Mode.COUNTDOWN,Mode.TRAINING]: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if mode==Mode.TRAINING:
			if event.pressed:
				exit_holding=true;exit_hold=0.0;mouse_blocked=true;burst_remaining=0;audio_player.stop();hit_audio_player.stop()
			else:_reset_exit_hold();mouse_blocked=true
		get_viewport().set_input_as_handled();return
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		var sensitivity:=float(data.settings.sensitivity);var radians_per_unit:=deg_to_rad(Balance.effective_coefficient(int(data.settings.sensitivity_game))*sensitivity);var motion:Vector2=event.screen_relative if event.screen_relative!=Vector2.ZERO else event.relative
		player.rotate_y(-motion.x*radians_per_unit);camera.rotation.x=clampf(camera.rotation.x-motion.y*radians_per_unit,deg_to_rad(-89),deg_to_rad(89))
	if mode==Mode.TRAINING and event.is_action_pressed("shoot") and not mouse_blocked and not exit_holding:
		if training_weapon==0: _fire_shot()
		elif training_weapon==2 and burst_remaining==0: burst_remaining=3; burst_timer=0.0
	if event.is_action_released("shoot") and not exit_holding: mouse_blocked=false

func _physics_process(delta:float)->void:
	if mode==Mode.TRAINING and not exit_holding:
		var input:=Input.get_vector("move_left","move_right","move_forward","move_back");var dir:=(player.transform.basis*Vector3(input.x,0,input.y)).normalized();player.velocity.x=dir.x*5.0;player.velocity.z=dir.z*5.0;player.velocity.y=0;player.move_and_slide();player.position.x=clampf(player.position.x,-6.0,6.0);player.position.z=clampf(player.position.z,5.0,10.0)
	else: player.velocity=Vector3.ZERO

func _process(delta:float)->void:
	_update_growth_feedback(delta)
	hit_flash=maxf(0,hit_flash-delta);hit_sound_cooldown=maxf(0,hit_sound_cooldown-delta)
	score_pulse=maxf(0,score_pulse-delta);pulse_cooldown=maxf(0,pulse_cooldown-delta)
	if hit_label:hit_label.modulate.a=clampf(hit_flash*5.0,0,1)
	if stat_label:stat_label.modulate=Color.WHITE.lerp(Color("ffe3a0"),clampf(score_pulse*4.0,0,1))
	if app_focused and mode in [Mode.PREP,Mode.ARMY,Mode.COUNTDOWN,Mode.TRAINING,Mode.RESULT,Mode.RECORDS]:_process_battle(delta)
	if mode==Mode.COUNTDOWN:
		countdown-=delta;countdown_label.text=str(max(1,ceili(countdown)))
		if countdown<=0:mode=Mode.TRAINING;countdown_label.text="";mouse_blocked=Input.is_action_pressed("shoot")
	elif mode==Mode.TRAINING:
		var step:=delta
		training_elapsed+=step
		if exit_holding:
			exit_hold+=step;exit_ring.value=exit_hold;exit_ring.show();exit_hint.show()
			if exit_hold>=0.8:_finish_training(false);return
		if training_weapon==1:
			if Input.is_action_pressed("shoot") and not mouse_blocked:active_seconds+=step
		else:
			active_seconds+=minf(activity_window,step)
			activity_window=maxf(0,activity_window-step)
		fire_cooldown=maxf(0,fire_cooldown-step);point_display_timer=maxf(0,point_display_timer-step)
		_update_targets(step);_process_weapon(step);_update_hud()
		checkpoint_timer+=step
		if checkpoint_timer>=15.0:_checkpoint_training()

func _process_weapon(delta:float)->void:
	if exit_holding:return
	if training_weapon==1 and Input.is_action_pressed("shoot") and not mouse_blocked:
		var before:=_training_result()
		stats.fire_time=float(stats.fire_time)+delta;var hit:=_ray_hit()
		if not hit.is_empty():
			stats.track_time=float(stats.track_time)+delta;stats.base_points=float(stats.base_points)+100.0*delta;var precision:float=hit.precision;stats.center_bonus=float(stats.center_bonus)+100.0*delta*precision;auto_streak_time+=delta;stats.streak_bonus=float(stats.streak_bonus)+(5.0*delta if auto_streak_time>1.0 else 0.0)
			_add_point_feedback(before,point_display_timer<=0)
		else:auto_streak_time=maxf(0,auto_streak_time-delta*2.0)
		if fire_cooldown<=0: _fire_shot(); fire_cooldown=0.1
	elif training_weapon==2 and burst_remaining>0:
		burst_timer-=delta
		if burst_timer<=0: _fire_shot(); burst_remaining-=1; burst_timer=0.085

func _fire_shot()->void:
	if exit_holding:return
	var before:=_training_result()
	stats.shots=int(stats.shots)+1;var hit:=_ray_hit();_play_shot_sound()
	if training_weapon!=1:activity_window=0.2
	if hit.is_empty():
		if training_weapon!=1:streak=0
		return
	var idx:=int(hit.index);stats.hits=int(stats.hits)+1;var precision:float=hit.precision;var gained:=0.0
	if training_weapon==0:
		gained=45.0;stats.base_points=float(stats.base_points)+gained;var center:=45.0*precision;var reaction:=training_elapsed-target_spawn_times[idx];var speed:=12.0*clampf(1.0-reaction/2.5,0.0,1.0);streak=streak+1 if training_elapsed-last_success_time<4.0 else 1;var streak_points:=minf(8.0,float(streak-1)*1.5);stats.center_bonus=float(stats.center_bonus)+center;stats.speed_bonus=float(stats.speed_bonus)+speed;stats.streak_bonus=float(stats.streak_bonus)+streak_points;gained+=center+speed+streak_points;last_success_time=training_elapsed;stats.kills=int(stats.kills)+1;_relocate_target(idx)
	elif training_weapon==2:
		gained=15.0;stats.base_points=float(stats.base_points)+gained;var center:=15.0*precision;target_precisions[idx]+=precision;stats.center_bonus=float(stats.center_bonus)+center;gained+=center;target_progress[idx]+=1
		if target_progress[idx]>=3:
			stats.base_points=float(stats.base_points)+20.0;var kill_center:=20.0*target_precisions[idx]/3.0;stats.center_bonus=float(stats.center_bonus)+kill_center;gained+=20.0+kill_center;var switch_time:=training_elapsed-last_success_time;var speed:=10.0*clampf(1.0-switch_time/2.2,0.0,1.0) if last_success_time>=0 else 0.0;streak=streak+1 if switch_time<4.0 else 1;var streak_points:=minf(6.0,float(streak-1));stats.speed_bonus=float(stats.speed_bonus)+speed;stats.streak_bonus=float(stats.streak_bonus)+streak_points;gained+=speed+streak_points;last_success_time=training_elapsed;stats.kills=int(stats.kills)+1;_relocate_target(idx)
	_play_hit_sound(int(floor(auto_streak_time)) if training_weapon==1 else streak,precision>=0.8)
	if training_weapon!=1:_add_point_feedback(before,true)

func _add_point_feedback(before:Dictionary,display:bool)->void:
	var after:=_training_result()
	var total:=maxi(0,int(after.score)-int(before.score))
	var center_added:=clampi(int(after.center)-int(before.center),0,total)
	var other_added:=clampi(int(after.speed)+int(after.streak)-int(before.speed)-int(before.streak),0,total-center_added)
	feedback_base+=total-center_added-other_added
	feedback_center+=center_added
	feedback_other+=other_added
	if not display or feedback_base+feedback_center+feedback_other<=0:return
	hit_label.text="+%d P"%(feedback_base+feedback_center+feedback_other)
	if bool(data.settings.get("score_details",false)):
		hit_label.text+="　基本 %d / 中心 +%d / 他 +%d"%[feedback_base,feedback_center,feedback_other]
	hit_label.add_theme_color_override("font_color",Color("ffe3a0") if feedback_center>0 else Color("d7eff8"))
	feedback_base=0;feedback_center=0;feedback_other=0;hit_flash=0.35;point_display_timer=0.35

func _ray_hit()->Dictionary:
	var from:=camera.global_position; var to:=from-camera.global_transform.basis.z*100.0; var query:=PhysicsRayQueryParameters3D.create(from,to); query.collide_with_areas=false
	query.collision_mask=1
	var hit:=get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_meta("target_index"):
		var idx:=int(hit.collider.get_meta("target_index"));return {"index":idx,"precision":Balance.center_precision(from,to-from,targets[idx].global_position,float(Balance.DIFFICULTY[training_difficulty].radius))}
	return {}
func _ray_target_index()->int:
	var hit:=_ray_hit();return -1 if hit.is_empty() else int(hit.index)

func _update_targets(delta:float)->void:
	if targets.is_empty():return
	if training_weapon==1:
		target_phase+=delta*float(Balance.DIFFICULTY[training_difficulty].speed)
		targets[0].position=_auto_position(target_phase)
	for target in targets:
		target.get_node("CenterMark").position=(camera.global_position-target.global_position).normalized()*float(Balance.DIFFICULTY[training_difficulty].radius)*1.015

func _training_result()->Dictionary:
	return Balance.score_and_reward(training_weapon,training_difficulty,stats,int(data.front),0,training_elapsed,session_fraction)

func _update_hud()->void:
	var result:=_training_result()
	var current_score:=int(result.score)
	if current_score>last_hud_score and pulse_cooldown<=0:score_pulse=0.25;pulse_cooldown=0.35
	last_hud_score=current_score
	timer_label.text="経過 "+Balance.clock_text(training_elapsed)
	stat_label.text="今回の獲得 %d P"%current_score
	_refresh_goal_hud()
	credit_hud.text=("撃破 %d　命中率 %.1f%%"%[stats.kills,float(result.accuracy)*100.0] if training_weapon!=1 else "追従 %.1f秒　追従率 %.1f%%"%[stats.track_time,float(result.accuracy)*100.0])+(" / 保存再試行中" if save_warning else "")

func _training_session_open()->bool:
	return not reward_committed and (mode in [Mode.COUNTDOWN,Mode.TRAINING] or (mode==Mode.PAUSED and mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]))

func _session_record()->Dictionary:
	var result:=_training_result()
	return {"id":session_id,"started":session_started,"weapon":training_weapon,"difficulty":training_difficulty,"duration":0,"elapsed":training_elapsed,"active":minf(active_seconds,training_elapsed),"score":int(result.score),"credits":int(result.supply),"point_fraction":float(result.fraction),"accuracy":float(result.accuracy),"base":result.base,"center":result.center,"speed":result.speed,"streak":result.streak,"scoring_version":Balance.SCORING_VERSION}

func _checkpoint_training()->void:
	checkpoint_timer=0.0
	if not _training_session_open() or training_elapsed<=0:return
	TrainingLedger.checkpoint(data,_session_record())
	if not is_test_mode:save_warning=not SaveManager.save_data(data)

func _finish_training(_full_time:bool)->void:
	if reward_committed:return
	_reset_exit_hold();mouse_blocked=true;burst_remaining=0;audio_player.stop();hit_audio_player.stop()
	var result:=_training_result()
	var record:=_session_record()
	var status:="終了"
	TrainingLedger.finish(data,record,status)
	reward_committed=true
	if not is_test_mode:save_warning=not SaveManager.save_data(data)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;mode=Mode.RESULT;prep_panel.hide();army_panel.hide();hud.hide();pause_panel.hide();result_panel.show();_clear_targets()
	var metric:="撃破 %d　命中率 %.1f%%"%[stats.kills,float(result.accuracy)*100.0] if training_weapon!=1 else "追従 %.1f秒　追従率 %.1f%%"%[stats.track_time,float(result.accuracy)*100.0]
	result_title.text="訓練"+status
	_refresh_goals()
	result_detail.text="%s / %s\n練習 %s\n\n今回の獲得 %d P\n基本 %d　中心追加 %d　その他 %d\n%s\n\n所持ポイント %s P%s"%[Balance.WEAPONS[training_weapon],Balance.DIFFICULTY[training_difficulty].name,Balance.clock_text(training_elapsed),int(result.score),result.base,result.center,result.speed+result.streak,metric,_credit_text(),"\n保存に失敗しました。終了時に再試行します。" if save_warning else ""]

func _reset_exit_hold()->void:
	exit_holding=false;exit_hold=0.0
	if exit_ring:exit_ring.hide()
	if exit_hint:exit_hint.hide()

func _end_early()->void:
	if mode==Mode.PAUSED and mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]: _finish_training(false)

func _open_pause()->void:
	if mode==Mode.PAUSED: return
	_reset_exit_hold();burst_remaining=0
	_checkpoint_training();settings_standalone=false;mode_before_pause=mode;mode=Mode.PAUSED;Input.action_release("shoot");Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;audio_player.stop();hit_audio_player.stop();pause_panel.show();mouse_blocked=true;crosshair.hide();pause_menu.show();settings_page.hide();pause_end_button.visible=true;_update_battle_view()

func _close_pause()->void:
	if settings_page.visible:_settings_back();return
	_resume_pause()
func _resume_pause()->void:
	pause_panel.hide();mode=mode_before_pause;settings_standalone=false
	if mode in [Mode.COUNTDOWN,Mode.TRAINING]: Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; mouse_blocked=true; crosshair.show()
	else: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; _refresh_prep()
	_update_battle_view()
func _open_settings_from_screen()->void:
	if mode in [Mode.PREP,Mode.ARMY,Mode.RESULT]:
		settings_standalone=true;mode_before_pause=mode;mode=Mode.PAUSED;pause_panel.show();pause_menu.hide();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		_update_battle_view()
	_open_settings_page()
func _open_settings_page(sound_only:bool=false)->void:
	settings_snapshot=data.settings.duplicate(true);settings_dirty=false;_sync_settings_controls(settings_snapshot);pause_menu.hide();settings_page.show();discard_confirm.hide()
	_select_settings_tab(2 if sound_only else 0)
func _scroll_settings_to_sound()->void:settings_scroll.scroll_vertical=int(settings_scroll.get_v_scroll_bar().max_value)
func _apply_settings_draft()->void:
	data.settings=_draft_settings();settings_snapshot=data.settings.duplicate(true);settings_dirty=false;_apply_settings();if not is_test_mode:SaveManager.save_data(data)
func _cancel_settings_changes()->void:_sync_settings_controls(settings_snapshot);settings_dirty=false
func _reset_settings_draft()->void:_sync_settings_controls(SaveManager.default_settings());settings_dirty=true
func _settings_back()->void:
	if settings_dirty:discard_confirm.show();return
	if settings_standalone:_resume_pause()
	else:settings_page.hide();pause_menu.show()
func _confirm_discard()->void:
	_sync_settings_controls(settings_snapshot);settings_dirty=false;discard_confirm.hide()
	if settings_standalone:_resume_pause()
	else:settings_page.hide();pause_menu.show()

func _apply_settings()->void:
	if not camera: return
	var h4:=deg_to_rad(float(data.settings.fov)); var aspect:=4.0/3.0; camera.fov=rad_to_deg(2.0*atan(tan(h4/2.0)/aspect))
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,float(data.settings.volume)))); AudioServer.set_bus_mute(0,float(data.settings.volume)<=0.001)
	if crosshair:crosshair.set_appearance(str(data.settings.crosshair_color),float(data.settings.crosshair_size),int(data.settings.crosshair_shape),bool(data.settings.crosshair_outline))
	if crosshair_preview:crosshair_preview.set_appearance(str(data.settings.crosshair_color),float(data.settings.crosshair_size),int(data.settings.crosshair_shape),bool(data.settings.crosshair_outline))

func _process_battle(delta:float)->void:
	data.enemy_hp=float(data.enemy_hp)-Balance.army_power(data)*0.18*delta
	if float(data.enemy_hp)<=0:_advance_front()
	battle_save_timer+=delta
	if battle_save_timer>=15.0:
		battle_save_timer=0
		if not is_test_mode: SaveManager.save_data(data)
	_update_battle_hud()
	if mode==Mode.ARMY:
		_refresh_army_runtime()

func _update_battle_hud()->void:
	if not battle_hud:return
	var ratio:=1.0-float(data.enemy_hp)/Balance.front_hp(int(data.front))
	battle_progress.value=clampf(ratio,0.0,1.0)
	battle_hud.text="戦線 %d　制圧 %.1f%%\n次の突破まで %s"%[int(data.front)+1,ratio*100.0,Balance.eta_text(float(data.enemy_hp),Balance.army_power(data)*0.18,mode!=Mode.PAUSED)]

func _advance_front()->void:
	data.front=int(data.front)+1
	if int(data.front)>=3: data.unlocked[1]=true
	if int(data.front)>=7: data.unlocked[2]=true
	data.enemy_hp=Balance.front_hp(int(data.front))
	if not is_test_mode:SaveManager.save_data(data)
	hit_label.text="戦線突破！" if hit_label else ""; hit_flash=1.0

func _on_focus_lost()->void:
	app_focused=false
	_reset_exit_hold();burst_remaining=0
	Input.action_release("shoot"); mouse_blocked=true
	if mode in [Mode.COUNTDOWN,Mode.TRAINING]: _open_pause()
	_update_battle_view()

func _play_shot_sound()->void:
	_play_synth(audio_player,int(data.settings.shot_sound),false,float(data.settings.shot_volume),1.0)
func _play_hit_sound(combo:int,center_hit:bool=false)->void:
	if hit_sound_cooldown>0:return
	hit_sound_cooldown=0.055
	var pitch:float=_hit_pitch(combo)*(1.035 if center_hit else 1.0)
	_play_synth(hit_audio_player,int(data.settings.hit_sound),true,float(data.settings.hit_volume),pitch)
func _hit_pitch(combo:int)->float:return 1.0+mini(maxi(combo,0),8)*0.025 if bool(data.settings.hit_pitch_combo) else 1.0
func _preview_shot_sound()->void:_play_synth(audio_player,shot_sound_option.selected,false,shot_volume_slider.value,1.0)
func _preview_hit_sound()->void:_play_synth(hit_audio_player,hit_sound_option.selected,true,hit_volume_slider.value,1.12 if hit_pitch_check.button_pressed else 1.0)
func _play_synth(player_node:AudioStreamPlayer,choice:int,is_hit:bool,volume:float,pitch:float)->void:
	if choice==3:player_node.stop();return
	var duration:float=[0.025,0.075,0.05][choice] if is_hit else [0.07,0.04,0.065][choice]
	var base:float=([1250.0,1550.0,880.0][choice] if is_hit else [115.0,680.0,430.0][choice])*pitch
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=22050;stream.stereo=false
	var frames:=int(duration*stream.mix_rate);var bytes:=PackedByteArray();bytes.resize(frames*2)
	for i in frames:
		var t:=float(i)/stream.mix_rate;var fade:=pow(1.0-float(i)/frames,2.0);var wave:=sin(TAU*base*t)
		if choice==0 and not is_hit:wave=0.65*wave+0.35*sin(TAU*(base*2.7)*t)
		elif choice==1:wave=0.55*wave+0.45*sin(TAU*(base*1.61)*t)
		var sample:=clampi(int(wave*32767.0*minf(volume,1.0)*0.28*fade),-32768,32767);bytes.encode_s16(i*2,sample)
	stream.data=bytes;player_node.stream=stream;player_node.play()
