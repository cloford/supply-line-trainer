extends Node

enum Mode { PREP, ARMY, COUNTDOWN, TRAINING, RESULT, PAUSED }
var data:Dictionary
var mode := Mode.PREP
var mode_before_pause := Mode.PREP
var selected_weapon := 0
var selected_difficulty := 0
var selected_duration := 60
var training_weapon := 0
var training_difficulty := 0
var training_duration := 60
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
var offline_label:Label
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
var settings_snapshot:Dictionary={}
var settings_dirty:=false
var discard_confirm:HBoxContainer
var pause_end_button:Button
var commander_box:VBoxContainer
var purchase_batch:=1
var audio_player:AudioStreamPlayer

func _ready()->void:
	is_test_mode=is_test_mode or "--ui-test" in OS.get_cmdline_user_args()
	if is_test_mode:
		data = SaveManager.defaults()
		data["offline_message"]="UI検証モード"
	else:
		data = SaveManager.load_data()
		_apply_offline_income()
	selected_duration=int(data.selected_duration)
	_build_world()
	_build_ui()
	_apply_settings()
	_show_prep()
	get_viewport().focus_exited.connect(_on_focus_lost)
	get_tree().set_auto_accept_quit(false)

func _notification(what:int)->void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not is_test_mode: SaveManager.save_data(data)
		get_tree().quit()

func _apply_offline_income()->void:
	var now := int(Time.get_unix_time_from_system())
	var elapsed := clampi(now - int(data.last_save), 0, 8 * 3600)
	var raw := elapsed * Balance.passive_rate(int(data.depot),data.commander_equipped)
	var cap := Balance.offline_cap(int(data.front))
	var gained:float = minf(raw, cap)
	_credit_add(gained)
	data["offline_message"] = "オフラインクレジット +%s（%d分、上限%s）" % [Balance.format_number(gained), elapsed / 60, Balance.format_number(cap)] if gained >= 1.0 else "オフライン上限: %sクレジット（最大8時間）" % Balance.format_number(cap)
	SaveManager.save_data(data)

func _credit_add(amount:float)->void:
	if amount<=0:return
	var total_fraction:float=float(data.credit_fraction)+fmod(amount,1.0)
	var whole:float=floor(amount)+floor(total_fraction)
	data.credit_fraction=fmod(total_fraction,1.0)
	data.credits=BigUInt.add(str(data.credits),BigUInt.from_float(whole))
func _credit_can_afford(cost:float)->bool:return BigUInt.compare(str(data.credits),BigUInt.from_float(ceil(cost)))>=0
func _credit_spend(cost:float)->bool:
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
	var prep:=VBoxContainer.new(); prep.add_theme_constant_override("separation",10); prep_panel.add_child(prep)
	var title:=_label("SUPPLY LINE TRAINER",30); title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; prep.add_child(title)
	offline_label=_label(str(data.offline_message),15); offline_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; prep.add_child(offline_label)
	var center:=CenterContainer.new(); center.size_flags_vertical=Control.SIZE_EXPAND_FILL; prep.add_child(center)
	var train_box:=_section("訓練準備"); train_box.custom_minimum_size=Vector2(620,0); center.add_child(train_box)
	var wtitle:=_label("武器",18); train_box.add_child(wtitle)
	var wr:=HBoxContainer.new(); train_box.add_child(wr)
	for i in 3:
		var b:=Button.new(); b.toggle_mode=true;b.text=Balance.WEAPONS[i]; b.pressed.connect(_select_weapon.bind(i)); b.custom_minimum_size.x=190; wr.add_child(b); weapon_buttons.append(b)
	train_box.add_child(_label("難易度",18))
	var dr:=HBoxContainer.new(); train_box.add_child(dr)
	for i in 3:
		var b:=Button.new(); b.toggle_mode=true;b.text=Balance.DIFFICULTY[i].name; b.pressed.connect(_select_difficulty.bind(i)); b.custom_minimum_size.x=190; dr.add_child(b); difficulty_buttons.append(b)
	difficulty_info=_label("",14);difficulty_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;train_box.add_child(difficulty_info)
	train_box.add_child(_label("時間",18));var tr:=HBoxContainer.new();train_box.add_child(tr)
	for seconds in Balance.TRAINING_DURATIONS:
		var b:=Button.new();b.toggle_mode=true;b.text="%d秒"%seconds;b.custom_minimum_size.x=190;b.pressed.connect(_select_duration.bind(seconds));tr.add_child(b);duration_buttons.append(b)
	condition_label=_label("",16);condition_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;train_box.add_child(condition_label)
	start_button=Button.new(); start_button.text="訓練開始"; start_button.custom_minimum_size.y=52; start_button.pressed.connect(_start_training); train_box.add_child(start_button)
	train_box.add_child(_label("WASD: 移動　マウス: 視点　左クリック: 射撃　Esc: 一時停止",14))
	var nav:=HBoxContainer.new(); nav.alignment=BoxContainer.ALIGNMENT_CENTER; nav.add_theme_constant_override("separation",12); prep.add_child(nav)
	var army_btn:=Button.new(); army_btn.text="部隊画面"; army_btn.custom_minimum_size=Vector2(220,44); army_btn.pressed.connect(_show_army); nav.add_child(army_btn)
	var settings_btn:=Button.new(); settings_btn.text="設定"; settings_btn.custom_minimum_size=Vector2(160,44); settings_btn.pressed.connect(_open_settings_from_screen); nav.add_child(settings_btn)
	_build_army_screen()

	hud=Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; ui.add_child(hud)
	timer_label=_label("60.0",28); timer_label.position=Vector2(24,20); hud.add_child(timer_label)
	stat_label=_label("",18); stat_label.position=Vector2(24,60); hud.add_child(stat_label)
	battle_hud=_label("",15); battle_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); battle_hud.position=Vector2(-360,20); battle_hud.size=Vector2(335,90); battle_hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; hud.add_child(battle_hud)
	countdown_label=_label("",54);countdown_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);countdown_label.offset_top=82;countdown_label.offset_bottom=162;countdown_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;hud.add_child(countdown_label)
	hit_label=_label("",20); hit_label.position=Vector2(24,100); hit_label.size=Vector2(360,40); hit_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT; hud.add_child(hit_label)
	crosshair=AimCrosshair.new(); crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(crosshair)
	var result_parts:=_modal_overlay(570.0); result_panel=result_parts[0]; result_card=result_parts[1]; ui.add_child(result_panel)
	var rv:=VBoxContainer.new(); rv.add_theme_constant_override("separation",14)
	result_card.add_child(rv)
	result_title=_label("訓練結果",28); result_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; rv.add_child(result_title)
	result_detail=_label("",18); result_detail.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; rv.add_child(result_detail)
	var retry:=Button.new(); retry.text="再挑戦"; retry.custom_minimum_size.y=48; retry.pressed.connect(_start_training); rv.add_child(retry)
	var back:=Button.new(); back.text="条件を変更"; back.pressed.connect(_show_prep); rv.add_child(back)
	var army_result:=Button.new();army_result.text="部隊へ";army_result.pressed.connect(_show_army);rv.add_child(army_result)
	pause_panel=_build_pause_panel(); ui.add_child(pause_panel)
	_refresh_prep()

func _modal_overlay(card_width:float)->Array:
	var overlay:=ColorRect.new(); overlay.color=Color("02070bb8"); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",24); margin.add_theme_constant_override("margin_right",24); margin.add_theme_constant_override("margin_top",24); margin.add_theme_constant_override("margin_bottom",24); overlay.add_child(margin)
	var center:=CenterContainer.new(); margin.add_child(center)
	var card:=_panel(); card.custom_minimum_size.x=card_width; card.size_flags_horizontal=Control.SIZE_SHRINK_CENTER; card.size_flags_vertical=Control.SIZE_SHRINK_CENTER; center.add_child(card)
	return [overlay,card]

func _build_army_screen()->void:
	army_panel=ColorRect.new(); army_panel.color=Color("071019"); army_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.add_child(army_panel)
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",16); margin.add_theme_constant_override("margin_right",16); margin.add_theme_constant_override("margin_top",16); margin.add_theme_constant_override("margin_bottom",16); army_panel.add_child(margin)
	var columns:=HBoxContainer.new(); columns.add_theme_constant_override("separation",16); margin.add_child(columns)
	var left_panel:=_panel(); left_panel.custom_minimum_size.x=320; left_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; left_panel.size_flags_stretch_ratio=0.36; columns.add_child(left_panel)
	var left:=VBoxContainer.new(); left.add_theme_constant_override("separation",8); left_panel.add_child(left)
	army_title=_label("部隊司令",27);army_title.custom_minimum_size.y=38;left.add_child(army_title)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;left.add_child(scroll)
	var info:=VBoxContainer.new(); info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_theme_constant_override("separation",8); scroll.add_child(info)
	supply_label=_label("",22); info.add_child(supply_label)
	power_label=_label("",16); power_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; info.add_child(power_label)
	for i in 3:
		var b:=Button.new(); b.custom_minimum_size.y=58; b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; b.pressed.connect(_buy_upgrade.bind(i)); info.add_child(b); upgrade_buttons.append(b)
	var batch_row:=HBoxContainer.new();info.add_child(batch_row)
	for amount in [1,10,100]:
		var bb:=Button.new();bb.text="×%d"%amount;bb.toggle_mode=true;bb.button_pressed=amount==1;bb.pressed.connect(_set_purchase_batch.bind(amount,batch_row));batch_row.add_child(bb)
	commander_box=VBoxContainer.new();commander_box.add_theme_constant_override("separation",5);info.add_child(_label("指揮官装備",19));info.add_child(commander_box)
	front_label=_label("",16); front_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; info.add_child(front_label)
	front_bar=ProgressBar.new(); front_bar.custom_minimum_size.y=24; front_bar.show_percentage=false; info.add_child(front_bar)
	var back:=Button.new(); back.text="訓練へ戻る"; back.custom_minimum_size.y=48; back.pressed.connect(_leave_army); left.add_child(back)
	var right_panel:=_panel(); right_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; right_panel.size_flags_stretch_ratio=0.64; columns.add_child(right_panel)
	var right:=VBoxContainer.new(); right_panel.add_child(right)
	var heading:=_label("進軍状況",24); heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; right.add_child(heading)
	battle_view=BattleView.new(); battle_view.custom_minimum_size=Vector2(480,400); battle_view.size_flags_vertical=Control.SIZE_EXPAND_FILL; battle_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL; right.add_child(battle_view)

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
	var preview_box:=PanelContainer.new();preview_box.custom_minimum_size.y=72;settings_page.add_child(preview_box)
	crosshair_preview=AimCrosshair.new();crosshair_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview_box.add_child(crosshair_preview)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;settings_page.add_child(scroll)
	var v:=VBoxContainer.new();v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_theme_constant_override("separation",6);scroll.add_child(v)
	v.add_child(_label("感度基準ゲーム",15));sensitivity_game=OptionButton.new()
	for preset in Balance.SENSITIVITY_PRESETS:sensitivity_game.add_item(preset.name)
	sensitivity_game.item_selected.connect(func(_value):_settings_changed());v.add_child(sensitivity_game)
	v.add_child(_label("ゲーム内感度",15));sensitivity_edit=LineEdit.new();sensitivity_edit.text_changed.connect(func(_value):_settings_changed());v.add_child(sensitivity_edit)
	sensitivity_slider=HSlider.new();sensitivity_slider.min_value=0.001;sensitivity_slider.max_value=10;sensitivity_slider.step=0.001;sensitivity_slider.value_changed.connect(_sensitivity_slider_changed);v.add_child(sensitivity_slider)
	v.add_child(_label("DPI（表示計算用）",15));dpi_spin=SpinBox.new();dpi_spin.min_value=100;dpi_spin.max_value=64000;dpi_spin.step=50;dpi_spin.value_changed.connect(func(_value):_settings_changed());v.add_child(dpi_spin)
	cm_label=_label("",14);v.add_child(cm_label)
	v.add_child(_label("水平FOV（4:3基準）",15));fov_spin=SpinBox.new();fov_spin.min_value=75;fov_spin.max_value=110;fov_spin.step=0.1;fov_spin.value_changed.connect(_fov_spin_changed);v.add_child(fov_spin)
	fov_slider=HSlider.new();fov_slider.min_value=75;fov_slider.max_value=110;fov_slider.step=0.1;fov_slider.value_changed.connect(_fov_slider_changed);v.add_child(fov_slider)
	v.add_child(_label("クロスヘア形状",15));shape_option=OptionButton.new()
	for shape_name in ["点","十字","隙間付き十字","円"]:shape_option.add_item(shape_name)
	shape_option.item_selected.connect(func(_value):_settings_changed());v.add_child(shape_option)
	v.add_child(_label("クロスヘア色",15));var color_row:=HBoxContainer.new();v.add_child(color_row);color_edit=LineEdit.new();color_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;color_edit.text_changed.connect(_color_text_changed);color_row.add_child(color_edit);color_picker=ColorPickerButton.new();color_picker.color_changed.connect(_color_picker_changed);color_row.add_child(color_picker)
	v.add_child(_label("クロスヘアサイズ",15));size_spin=SpinBox.new();size_spin.min_value=4;size_spin.max_value=30;size_spin.value_changed.connect(_size_spin_changed);v.add_child(size_spin);size_slider=HSlider.new();size_slider.min_value=4;size_slider.max_value=30;size_slider.step=1;size_slider.value_changed.connect(_size_slider_changed);v.add_child(size_slider)
	outline_check=CheckBox.new();outline_check.text="補助輪郭";outline_check.toggled.connect(func(_value):_settings_changed());v.add_child(outline_check)
	v.add_child(_label("音量",15));volume_slider=HSlider.new();volume_slider.min_value=0;volume_slider.max_value=1;volume_slider.step=0.01;volume_slider.value_changed.connect(func(_value):_settings_changed());v.add_child(volume_slider)
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

func _sync_settings_controls(source:Dictionary)->void:
	sensitivity_game.select(int(source.sensitivity_game));sensitivity_edit.text=str(source.sensitivity);sensitivity_slider.set_value_no_signal(float(source.sensitivity));dpi_spin.set_value_no_signal(float(source.dpi));fov_spin.set_value_no_signal(float(source.fov));fov_slider.set_value_no_signal(float(source.fov));color_edit.text=str(source.crosshair_color);color_picker.color=Color(str(source.crosshair_color));size_spin.set_value_no_signal(float(source.crosshair_size));size_slider.set_value_no_signal(float(source.crosshair_size));shape_option.select(int(source.crosshair_shape));outline_check.button_pressed=bool(source.crosshair_outline);volume_slider.set_value_no_signal(float(source.volume));_settings_changed()
func _draft_settings()->Dictionary:return {"sensitivity":clampf(float(sensitivity_edit.text),0.001,100.0),"sensitivity_game":sensitivity_game.selected,"dpi":dpi_spin.value,"fov":fov_spin.value,"crosshair_color":color_edit.text if Color.html_is_valid(color_edit.text) else "66e8ff","crosshair_size":size_spin.value,"crosshair_shape":shape_option.selected,"crosshair_outline":outline_check.button_pressed,"volume":volume_slider.value}
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
	var equipped:Array=data.commander_equipped
	supply_label.text="クレジット: %s"%_credit_text()
	power_label.text="隊員 %s　装備倍率 ×%.2f　戦闘力 %s　自動収入 %.2f/秒"%[Balance.format_soldiers(int(data.recruit)),Balance.gear_multiplier(int(data.gear)),Balance.format_number(Balance.combat_power(int(data.recruit),int(data.gear),equipped)),Balance.passive_rate(int(data.depot),equipped)]
	var costs:=[_upgrade_total_cost(0),_upgrade_total_cost(1),_upgrade_total_cost(2)]
	var names:=["増員","装備強化","収入設備"]
	var effects:=["規模 %s → %s"%[Balance.format_soldiers(int(data.recruit)),Balance.format_soldiers(int(data.recruit)+purchase_batch)],"倍率 ×%.2f → ×%.2f"%[Balance.gear_multiplier(int(data.gear)),Balance.gear_multiplier(int(data.gear)+purchase_batch)],"%.2f/秒 → %.2f/秒"%[Balance.passive_rate(int(data.depot),equipped),Balance.passive_rate(int(data.depot)+purchase_batch,equipped)]]
	for i in 3:
		upgrade_buttons[i].text="%s ×%d　%s　価格 %s%s"%[names[i],purchase_batch,effects[i],Balance.format_number(costs[i]),"（不足）" if not _credit_can_afford(costs[i]) else ""]
		upgrade_buttons[i].disabled=not _credit_can_afford(costs[i])
	for i in 3:
		weapon_buttons[i].disabled=not bool(data.unlocked[i]);weapon_buttons[i].text=("✓ " if i==selected_weapon else "　")+Balance.WEAPONS[i]+("" if data.unlocked[i] else "（戦線%dで開放）"%([0,3,7][i]));weapon_buttons[i].set_pressed_no_signal(i==selected_weapon)
		difficulty_buttons[i].text=("✓ " if i==selected_difficulty else "　")+Balance.DIFFICULTY[i].name;difficulty_buttons[i].set_pressed_no_signal(i==selected_difficulty)
	for i in duration_buttons.size():duration_buttons[i].text=("✓ " if Balance.TRAINING_DURATIONS[i]==selected_duration else "　")+"%d秒"%Balance.TRAINING_DURATIONS[i];duration_buttons[i].set_pressed_no_signal(Balance.TRAINING_DURATIONS[i]==selected_duration)
	if not bool(data.unlocked[selected_weapon]): selected_weapon=0
	difficulty_info.text="%s　基本点＋中心精度・速さ・連続成功（ボーナス上限45%%）　クレジット倍率×%.2f"%[Balance.DIFFICULTY[selected_difficulty].description,float(Balance.DIFFICULTY[selected_difficulty].reward)]
	condition_label.text="選択中：%s / %s / %d秒"%[Balance.WEAPONS[selected_weapon],Balance.DIFFICULTY[selected_difficulty].name,selected_duration]
	var maxhp:=Balance.front_hp(int(data.front));front_label.text="戦線 %d　%s　敵耐久 %s/%s"%[int(data.front)+1,Balance.front_name(int(data.front)),Balance.format_number(float(data.enemy_hp)),Balance.format_number(maxhp)];front_bar.max_value=100;front_bar.value=(1.0-float(data.enemy_hp)/maxhp)*100.0
	if army_title: army_title.text="部隊司令　装備外見 段階%d" % (Balance.visual_tier(int(data.gear))+1)
	_refresh_commander_box()
	_update_battle_view()

func _refresh_army_runtime()->void:
	supply_label.text="クレジット: %s"%_credit_text();var maxhp:=Balance.front_hp(int(data.front));front_label.text="戦線 %d　%s　敵耐久 %s/%s"%[int(data.front)+1,Balance.front_name(int(data.front)),Balance.format_number(float(data.enemy_hp)),Balance.format_number(maxhp)];front_bar.max_value=100;front_bar.value=(1.0-float(data.enemy_hp)/maxhp)*100.0
	_update_battle_view()

func _update_battle_view()->void:
	if not battle_view: return
	var front_index:=int(data.front);battle_view.set_state({"soldiers":Balance.soldier_display_count(int(data.recruit)),"soldier_label":Balance.format_soldiers(int(data.recruit)),"scale_tier":Balance.scale_tier(int(data.recruit)),"gear":int(data.gear),"front":front_index,"enemy_hp":float(data.enemy_hp),"enemy_max":Balance.front_hp(front_index)})

func _buy_upgrade(kind:int)->void:
	var keys:=["recruit","gear","depot"]
	var costs:=[_upgrade_total_cost(0),_upgrade_total_cost(1),_upgrade_total_cost(2)]
	if not _credit_spend(costs[kind]):return
	data[keys[kind]]=int(data[keys[kind]])+purchase_batch
	if not is_test_mode:SaveManager.save_data(data)
	_refresh_prep()

func _upgrade_total_cost(kind:int)->float:
	var level:=int(data[["recruit","gear","depot"][kind]]);var total:=0.0
	for offset in purchase_batch:total+=([Balance.recruit_cost(level+offset),Balance.gear_cost(level+offset),Balance.depot_cost(level+offset)][kind])
	return minf(total,1.0e290)
func _set_purchase_batch(amount:int,row:HBoxContainer)->void:
	purchase_batch=amount
	for child in row.get_children():child.set_pressed_no_signal(child.text=="×%d"%amount)
	_refresh_prep()
func _refresh_commander_box()->void:
	if not commander_box:return
	for child in commander_box.get_children():child.queue_free()
	for slot in 3:
		commander_box.add_child(_label(["通信機","戦術端末","補給装置"][slot],14))
		for item in Balance.COMMANDER_ITEMS:
			if int(item.slot)!=slot:continue
			var owned:bool=str(item.id) in data.commander_owned;var equipped:bool=str(data.commander_equipped[slot])==str(item.id);var b:=Button.new();b.text=("装備中：" if equipped else "購入済：" if owned else "購入：")+str(item.name)+"　戦闘×%.2f 収入×%.2f"%[item.combat,item.income]+("　%sCr"%Balance.format_number(item.cost) if not owned else "");b.disabled=not owned and not _credit_can_afford(float(item.cost));b.pressed.connect(_commander_item_pressed.bind(item));commander_box.add_child(b)
func _commander_item_pressed(item:Dictionary)->void:
	var id:=str(item.id);var slot:=int(item.slot)
	if not id in data.commander_owned:
		if not _credit_spend(float(item.cost)):return
		data.commander_owned.append(id)
	data.commander_equipped[slot]=id
	if not is_test_mode:SaveManager.save_data(data)
	_refresh_prep()

func _show_prep()->void:
	mode=Mode.PREP; Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; _clear_targets(); prep_panel.show(); army_panel.hide(); hud.hide(); result_panel.hide(); pause_panel.hide(); _refresh_prep()

func _show_army()->void:
	if mode==Mode.PAUSED: army_return_mode=mode_before_pause
	elif mode in [Mode.TRAINING,Mode.COUNTDOWN]: army_return_mode=mode
	else: army_return_mode=Mode.PREP
	mode=Mode.ARMY; mouse_blocked=true; Input.action_release("shoot"); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	prep_panel.hide(); hud.hide(); result_panel.hide(); pause_panel.hide(); army_panel.show(); _refresh_prep()

func _leave_army()->void:
	army_panel.hide()
	if army_return_mode in [Mode.TRAINING,Mode.COUNTDOWN]:
		mode=army_return_mode; hud.show(); crosshair.show(); Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; mouse_blocked=true
	else:
		_show_prep()

func _pause_to_army()->void:
	_show_army()

func _start_training()->void:
	training_weapon=selected_weapon;training_difficulty=selected_difficulty;training_duration=selected_duration;time_left=float(training_duration);training_elapsed=0.0;countdown=3.0;reward_committed=false;stats={"shots":0,"hits":0,"kills":0,"track_time":0.0,"fire_time":0.0,"base_points":0.0,"center_bonus":0.0,"speed_bonus":0.0,"streak_bonus":0.0};fire_cooldown=0;burst_remaining=0;burst_timer=0;target_phase=0;streak=0;last_success_time=-99.0;auto_streak_time=0;point_display_timer=0;hit_label.text="";hit_flash=0;player.position=Vector3(0,1.7,8);player.rotation=Vector3.ZERO;camera.rotation=Vector3.ZERO
	prep_panel.hide(); army_panel.hide(); result_panel.hide(); pause_panel.hide(); hud.show(); crosshair.show(); mode=Mode.COUNTDOWN; mouse_blocked=true; Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; _spawn_targets()

func _spawn_targets()->void:
	_clear_targets(); var count:=3 if training_weapon==2 else 1
	for i in count:
		var body:=StaticBody3D.new(); body.set_meta("target_index",i); target_root.add_child(body)
		var mesh:=MeshInstance3D.new(); var sphere:=SphereMesh.new(); sphere.radius=float(Balance.DIFFICULTY[training_difficulty].radius); sphere.height=sphere.radius*2.0; mesh.mesh=sphere; mesh.material_override=_material(Color("58edff") if training_weapon!=2 else Color("ffb84a")); body.add_child(mesh)
		var ring:=MeshInstance3D.new(); var torus:=TorusMesh.new(); torus.inner_radius=sphere.radius*0.48; torus.outer_radius=sphere.radius*0.62; ring.mesh=torus; ring.rotation_degrees.x=90; ring.material_override=_material(Color("ffffff")); body.add_child(ring)
		var shape:=CollisionShape3D.new(); var ss:=SphereShape3D.new(); ss.radius=sphere.radius; shape.shape=ss; body.add_child(shape)
		targets.append(body);target_progress.append(0);target_spawn_times.append(0.0)
		if training_weapon==1:body.position=_auto_position(0.0)
		else:_relocate_target(i)

func _clear_targets()->void:
	for child in target_root.get_children(): child.queue_free()
	targets.clear();target_progress.clear();target_spawn_times.clear()

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
	targets[i].position=candidate;target_progress[i]=0;target_spawn_times[i]=training_elapsed

func _auto_position(phase:float)->Vector3:
	var r:float=Balance.DIFFICULTY[training_difficulty].range
	return Vector3(sin(phase)*r,2.45+sin(phase*0.63)*1.15,-7.5+cos(phase*0.37)*1.5)

func _unhandled_input(event:InputEvent)->void:
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("pause"):
		if mode==Mode.PAUSED:
			_close_pause()
		elif mode in [Mode.PREP,Mode.ARMY,Mode.COUNTDOWN,Mode.TRAINING]:
			_open_pause()
		return
	if mode not in [Mode.COUNTDOWN,Mode.TRAINING]: return
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		var sensitivity:=float(data.settings.sensitivity);var radians_per_unit:=deg_to_rad(Balance.effective_coefficient(int(data.settings.sensitivity_game))*sensitivity);var motion:Vector2=event.screen_relative if event.screen_relative!=Vector2.ZERO else event.relative
		player.rotate_y(-motion.x*radians_per_unit);camera.rotation.x=clampf(camera.rotation.x-motion.y*radians_per_unit,deg_to_rad(-89),deg_to_rad(89))
	if mode==Mode.TRAINING and event.is_action_pressed("shoot") and not mouse_blocked:
		if training_weapon==0: _fire_shot()
		elif training_weapon==2 and burst_remaining==0: burst_remaining=3; burst_timer=0.0
	if event.is_action_released("shoot"): mouse_blocked=false

func _physics_process(delta:float)->void:
	if mode==Mode.TRAINING:
		var input:=Input.get_vector("move_left","move_right","move_forward","move_back");var dir:=(player.transform.basis*Vector3(input.x,0,input.y)).normalized();player.velocity.x=dir.x*5.0;player.velocity.z=dir.z*5.0;player.velocity.y=0;player.move_and_slide();player.position.x=clampf(player.position.x,-6.0,6.0);player.position.z=clampf(player.position.z,5.0,10.0)
	else: player.velocity=Vector3.ZERO

func _process(delta:float)->void:
	hit_flash=maxf(0,hit_flash-delta); if hit_label: hit_label.modulate.a=clampf(hit_flash*5.0,0,1)
	if mode!=Mode.PAUSED: _process_battle(delta)
	if mode==Mode.COUNTDOWN:
		countdown-=delta; countdown_label.text=str(max(1,ceili(countdown)))
		if countdown<=0: mode=Mode.TRAINING; countdown_label.text=""; mouse_blocked=Input.is_action_pressed("shoot")
	elif mode==Mode.TRAINING:
		time_left=maxf(0,time_left-delta);training_elapsed+=delta;timer_label.text="残り %.1f"%time_left;fire_cooldown=maxf(0,fire_cooldown-delta);point_display_timer=maxf(0,point_display_timer-delta)
		_update_targets(delta); _process_weapon(delta); _update_hud()
		if time_left<=0: _finish_training(true)

func _process_weapon(delta:float)->void:
	if training_weapon==1 and Input.is_action_pressed("shoot") and not mouse_blocked:
		stats.fire_time=float(stats.fire_time)+delta;var hit:=_ray_hit()
		if not hit.is_empty():
			stats.track_time=float(stats.track_time)+delta;stats.base_points=float(stats.base_points)+100.0*delta;var precision:=1.0-clampf(hit.normalized_distance,0.0,1.0);stats.center_bonus=float(stats.center_bonus)+25.0*delta*precision;auto_streak_time+=delta;stats.streak_bonus=float(stats.streak_bonus)+(5.0*delta if auto_streak_time>1.0 else 0.0)
			if point_display_timer<=0:hit_label.text="+%d 追従"%int(50.0*delta+precision*5.0);hit_flash=0.3;point_display_timer=0.35
		else:auto_streak_time=maxf(0,auto_streak_time-delta*2.0)
		if fire_cooldown<=0: _fire_shot(); fire_cooldown=0.1
	elif training_weapon==2 and burst_remaining>0:
		burst_timer-=delta
		if burst_timer<=0: _fire_shot(); burst_remaining-=1; burst_timer=0.085

func _fire_shot()->void:
	stats.shots=int(stats.shots)+1;var hit:=_ray_hit();_play_tone(620.0,0.035,0.10)
	if hit.is_empty():
		if training_weapon!=1:streak=0
		return
	var idx:=int(hit.index);stats.hits=int(stats.hits)+1;_play_tone(1050.0,0.045,0.16);var precision:=1.0-clampf(float(hit.normalized_distance),0.0,1.0);var gained:=0.0
	if training_weapon==0:
		gained=45.0;stats.base_points=float(stats.base_points)+gained;var center:=15.0*precision;var reaction:=training_elapsed-target_spawn_times[idx];var speed:=12.0*clampf(1.0-reaction/2.5,0.0,1.0);streak=streak+1 if training_elapsed-last_success_time<4.0 else 1;var streak_points:=minf(8.0,float(streak-1)*1.5);stats.center_bonus=float(stats.center_bonus)+center;stats.speed_bonus=float(stats.speed_bonus)+speed;stats.streak_bonus=float(stats.streak_bonus)+streak_points;gained+=center+speed+streak_points;last_success_time=training_elapsed;stats.kills=int(stats.kills)+1;_relocate_target(idx)
	elif training_weapon==2:
		gained=15.0;stats.base_points=float(stats.base_points)+gained;var center:=5.0*precision;stats.center_bonus=float(stats.center_bonus)+center;gained+=center;target_progress[idx]+=1
		if target_progress[idx]>=3:
			stats.base_points=float(stats.base_points)+20.0;gained+=20.0;var switch_time:=training_elapsed-last_success_time;var speed:=10.0*clampf(1.0-switch_time/2.2,0.0,1.0) if last_success_time>=0 else 0.0;streak=streak+1 if switch_time<4.0 else 1;var streak_points:=minf(6.0,float(streak-1));stats.speed_bonus=float(stats.speed_bonus)+speed;stats.streak_bonus=float(stats.streak_bonus)+streak_points;gained+=speed+streak_points;last_success_time=training_elapsed;stats.kills=int(stats.kills)+1;_relocate_target(idx)
	hit_label.text="+%d"%int(round(gained));hit_flash=0.28

func _ray_hit()->Dictionary:
	var from:=camera.global_position; var to:=from-camera.global_transform.basis.z*100.0; var query:=PhysicsRayQueryParameters3D.create(from,to); query.collide_with_areas=false
	query.collision_mask=1
	var hit:=get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_meta("target_index"):
		var idx:=int(hit.collider.get_meta("target_index"));return {"index":idx,"normalized_distance":Vector3(hit.position).distance_to(targets[idx].global_position)/float(Balance.DIFFICULTY[training_difficulty].radius)}
	return {}
func _ray_target_index()->int:
	var hit:=_ray_hit();return -1 if hit.is_empty() else int(hit.index)

func _update_targets(delta:float)->void:
	if training_weapon!=1 or targets.is_empty(): return
	target_phase+=delta*float(Balance.DIFFICULTY[training_difficulty].speed)
	targets[0].position=_auto_position(target_phase)

func _update_hud()->void:
	var current_score:=int(float(stats.base_points)+minf(float(stats.center_bonus)+float(stats.speed_bonus)+float(stats.streak_bonus),float(stats.base_points)*0.45))
	if training_weapon==0: stat_label.text="スコア %d　撃破 %d　連続 %d"%[current_score,stats.kills,streak]
	elif training_weapon==1: stat_label.text="追従 %.1f秒　射撃 %.1f秒" % [stats.track_time,stats.fire_time]
	else: stat_label.text="スコア %d　撃破 %d　連続 %d　標的 %s"%[current_score,stats.kills,streak,str(target_progress)]

func _finish_training(full_time:bool)->void:
	if reward_committed: return
	reward_committed=true;var result:=Balance.score_and_reward(training_weapon,training_difficulty,stats,int(data.front),training_duration,training_elapsed);_credit_add(float(result.supply))
	var key:="v2_%d_%d_%d"%[training_weapon,training_difficulty,training_duration];var previous:=int(data.bests_v2.get(key,0));var is_best:=full_time and int(result.score)>previous
	if is_best:data.bests_v2[key]=int(result.score)
	if not is_test_mode:SaveManager.save_data(data)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; mode=Mode.RESULT; prep_panel.hide(); army_panel.hide(); hud.hide(); pause_panel.hide(); result_panel.show(); _clear_targets()
	var metric:="撃破 %d　命中率 %.1f%%"%[stats.kills,float(result.accuracy)*100.0] if training_weapon!=1 else "追従 %.1f秒　追従率 %.1f%%"%[stats.track_time,float(result.accuracy)*100.0]
	result_title.text="訓練完了" if full_time else "途中終了"
	result_detail.text="%s / %s / %d秒\n\nスコア %d%s\n自己ベスト %d\n基本 %d　中心 %d　速度 %d　連続 %d\n%s\n\n獲得クレジット +%s\n現在 %s"%[Balance.WEAPONS[training_weapon],Balance.DIFFICULTY[training_difficulty].name,training_duration,int(result.score),"　NEW BEST" if is_best else "",max(previous,int(data.bests_v2.get(key,0))),result.base,result.center,result.speed,result.streak,metric,Balance.format_number(float(result.supply)),_credit_text()]

func _end_early()->void:
	if mode==Mode.PAUSED and mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]: _finish_training(false)

func _open_pause()->void:
	if mode==Mode.PAUSED: return
	mode_before_pause=mode;mode=Mode.PAUSED;Input.action_release("shoot");Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;pause_panel.show();mouse_blocked=true;crosshair.hide();pause_menu.show();settings_page.hide();pause_end_button.visible=mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]

func _close_pause()->void:
	if settings_page.visible:_settings_back();return
	_resume_pause()
func _resume_pause()->void:
	pause_panel.hide();mode=mode_before_pause
	if mode in [Mode.COUNTDOWN,Mode.TRAINING]: Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; mouse_blocked=true; crosshair.show()
	else: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; _refresh_prep()
func _open_settings_from_screen()->void:
	_open_pause();_open_settings_page()
func _open_settings_page()->void:
	settings_snapshot=data.settings.duplicate(true);settings_dirty=false;_sync_settings_controls(settings_snapshot);pause_menu.hide();settings_page.show();discard_confirm.hide()
func _apply_settings_draft()->void:
	data.settings=_draft_settings();settings_snapshot=data.settings.duplicate(true);settings_dirty=false;_apply_settings();if not is_test_mode:SaveManager.save_data(data)
func _cancel_settings_changes()->void:_sync_settings_controls(settings_snapshot);settings_dirty=false
func _reset_settings_draft()->void:_sync_settings_controls(SaveManager.default_settings());settings_dirty=true
func _settings_back()->void:
	if settings_dirty:discard_confirm.show();return
	if mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]:settings_page.hide();pause_menu.show()
	else:_resume_pause()
func _confirm_discard()->void:
	_sync_settings_controls(settings_snapshot);settings_dirty=false;discard_confirm.hide()
	if mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]:settings_page.hide();pause_menu.show()
	else:_resume_pause()

func _apply_settings()->void:
	if not camera: return
	var h4:=deg_to_rad(float(data.settings.fov)); var aspect:=4.0/3.0; camera.fov=rad_to_deg(2.0*atan(tan(h4/2.0)/aspect))
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,float(data.settings.volume)))); AudioServer.set_bus_mute(0,float(data.settings.volume)<=0.001)
	if crosshair:crosshair.set_appearance(str(data.settings.crosshair_color),float(data.settings.crosshair_size),int(data.settings.crosshair_shape),bool(data.settings.crosshair_outline))
	if crosshair_preview:crosshair_preview.set_appearance(str(data.settings.crosshair_color),float(data.settings.crosshair_size),int(data.settings.crosshair_shape),bool(data.settings.crosshair_outline))

func _process_battle(delta:float)->void:
	_credit_add(Balance.passive_rate(int(data.depot),data.commander_equipped)*delta)
	data.enemy_hp=float(data.enemy_hp)-Balance.combat_power(int(data.recruit),int(data.gear),data.commander_equipped)*0.18*delta
	if float(data.enemy_hp)<=0:_advance_front()
	battle_save_timer+=delta
	if battle_save_timer>=15.0:
		battle_save_timer=0
		if not is_test_mode: SaveManager.save_data(data)
	if battle_hud:
		battle_hud.text="戦線 %d　敵耐久 %s\n味方 %s / 戦闘力 %s"%[int(data.front)+1,Balance.format_number(float(data.enemy_hp)),Balance.format_soldiers(int(data.recruit)),Balance.format_number(Balance.combat_power(int(data.recruit),int(data.gear),data.commander_equipped))]
	if mode==Mode.ARMY:
		_refresh_army_runtime()

func _advance_front()->void:
	data.front=int(data.front)+1
	_credit_add(30.0*pow(1.12,mini(int(data.front),500)))
	if int(data.front)>=3: data.unlocked[1]=true
	if int(data.front)>=7: data.unlocked[2]=true
	data.enemy_hp=Balance.front_hp(int(data.front))
	if not is_test_mode:SaveManager.save_data(data)
	hit_label.text="戦線突破！" if hit_label else ""; hit_flash=1.0

func _on_focus_lost()->void:
	Input.action_release("shoot"); mouse_blocked=true
	if mode in [Mode.COUNTDOWN,Mode.TRAINING]: _open_pause()

func _play_tone(freq:float,duration:float,volume:float)->void:
	var stream:=AudioStreamWAV.new(); stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=22050; stream.stereo=false
	var frames:=int(duration*stream.mix_rate); var bytes:=PackedByteArray(); bytes.resize(frames*2)
	for i in frames:
		var fade:=1.0-float(i)/frames; var sample:=int(sin(TAU*freq*i/stream.mix_rate)*32767.0*volume*fade); bytes.encode_s16(i*2,sample)
	stream.data=bytes; audio_player.stream=stream; audio_player.play()
