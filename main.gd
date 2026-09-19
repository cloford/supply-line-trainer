extends Node

enum Mode { PREP, ARMY, COUNTDOWN, TRAINING, RESULT, PAUSED }
const TRAIN_DURATION := Balance.TRAINING_SECONDS

var data:Dictionary
var mode := Mode.PREP
var mode_before_pause := Mode.PREP
var selected_weapon := 0
var selected_difficulty := 0
var training_weapon := 0
var training_difficulty := 0
var time_left := TRAIN_DURATION
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
var upgrade_buttons:Array[Button] = []
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
var fov_spin:SpinBox
var color_edit:LineEdit
var size_spin:SpinBox
var volume_slider:HSlider
var pause_army_button:Button
var pause_end_button:Button
var audio_player:AudioStreamPlayer

func _ready()->void:
	is_test_mode="--ui-test" in OS.get_cmdline_user_args()
	if is_test_mode:
		data = SaveManager.defaults()
		data["offline_message"]="UI検証モード"
	else:
		data = SaveManager.load_data()
		_apply_offline_income()
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
	var raw := elapsed * Balance.passive_rate(int(data.depot))
	var cap := Balance.offline_cap(int(data.front))
	var gained:float = minf(raw, cap)
	data.supply = float(data.supply) + gained
	data["offline_message"] = "オフライン補給 +%d（%d分、上限%d）" % [int(gained), elapsed / 60, int(cap)] if gained >= 1.0 else "オフライン補給上限: %d（最大8時間）" % int(cap)
	SaveManager.save_data(data)

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
		var b:=Button.new(); b.text=Balance.WEAPONS[i]; b.pressed.connect(_select_weapon.bind(i)); b.custom_minimum_size.x=150; wr.add_child(b); weapon_buttons.append(b)
	train_box.add_child(_label("難易度（訓練中は固定）",18))
	var dr:=HBoxContainer.new(); train_box.add_child(dr)
	for i in 3:
		var b:=Button.new(); b.text=Balance.DIFFICULTY[i].name; b.pressed.connect(_select_difficulty.bind(i)); b.custom_minimum_size.x=150; dr.add_child(b); difficulty_buttons.append(b)
	start_button=Button.new(); start_button.text="60秒訓練を開始"; start_button.custom_minimum_size.y=52; start_button.pressed.connect(_start_training); train_box.add_child(start_button)
	train_box.add_child(_label("WASD: 移動　マウス: 視点　左クリック: 射撃　Esc: 一時停止",14))
	var nav:=HBoxContainer.new(); nav.alignment=BoxContainer.ALIGNMENT_CENTER; nav.add_theme_constant_override("separation",12); prep.add_child(nav)
	var army_btn:=Button.new(); army_btn.text="部隊画面"; army_btn.custom_minimum_size=Vector2(220,44); army_btn.pressed.connect(_show_army); nav.add_child(army_btn)
	var settings_btn:=Button.new(); settings_btn.text="設定"; settings_btn.custom_minimum_size=Vector2(160,44); settings_btn.pressed.connect(_open_pause); nav.add_child(settings_btn)
	_build_army_screen()

	hud=Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; ui.add_child(hud)
	timer_label=_label("60.0",28); timer_label.position=Vector2(24,20); hud.add_child(timer_label)
	stat_label=_label("",18); stat_label.position=Vector2(24,60); hud.add_child(stat_label)
	battle_hud=_label("",15); battle_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); battle_hud.position=Vector2(-360,20); battle_hud.size=Vector2(335,90); battle_hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; hud.add_child(battle_hud)
	countdown_label=_label("",64); countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER); countdown_label.position-=Vector2(100,60); countdown_label.size=Vector2(200,120); countdown_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; hud.add_child(countdown_label)
	hit_label=_label("",20); hit_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER); hit_label.position+=Vector2(-80,38); hit_label.size=Vector2(160,40); hit_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; hud.add_child(hit_label)
	crosshair=AimCrosshair.new(); crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(crosshair)
	var result_parts:=_modal_overlay(570.0); result_panel=result_parts[0]; result_card=result_parts[1]; ui.add_child(result_panel)
	var rv:=VBoxContainer.new(); rv.add_theme_constant_override("separation",14)
	result_card.add_child(rv)
	result_title=_label("訓練結果",28); result_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; rv.add_child(result_title)
	result_detail=_label("",18); result_detail.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; rv.add_child(result_detail)
	var retry:=Button.new(); retry.text="同じ条件で再挑戦"; retry.custom_minimum_size.y=48; retry.pressed.connect(_start_training); rv.add_child(retry)
	var back:=Button.new(); back.text="準備／強化へ"; back.pressed.connect(_show_prep); rv.add_child(back)
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
	army_title=_label("部隊司令",27); left.add_child(army_title)
	var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; left.add_child(scroll)
	var info:=VBoxContainer.new(); info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_theme_constant_override("separation",8); scroll.add_child(info)
	supply_label=_label("",22); info.add_child(supply_label)
	power_label=_label("",16); power_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; info.add_child(power_label)
	for i in 3:
		var b:=Button.new(); b.custom_minimum_size.y=58; b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; b.pressed.connect(_buy_upgrade.bind(i)); info.add_child(b); upgrade_buttons.append(b)
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
	var outer:=VBoxContainer.new(); outer.add_theme_constant_override("separation",10); pause_card.add_child(outer)
	var t:=_label("設定／一時停止",26); t.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; outer.add_child(t)
	var preview_box:=PanelContainer.new(); preview_box.custom_minimum_size.y=82; outer.add_child(preview_box)
	crosshair_preview=AimCrosshair.new(); crosshair_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); preview_box.add_child(crosshair_preview)
	var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; outer.add_child(scroll)
	var v:=VBoxContainer.new(); v.size_flags_horizontal=Control.SIZE_EXPAND_FILL; v.add_theme_constant_override("separation",7); scroll.add_child(v)
	v.add_child(_label("感度（CS標準スケール）",15)); sensitivity_edit=LineEdit.new(); sensitivity_edit.text=str(data.settings.sensitivity); v.add_child(sensitivity_edit)
	v.add_child(_label("水平FOV（4:3基準、75〜110）",15)); fov_spin=SpinBox.new(); fov_spin.min_value=75; fov_spin.max_value=110; fov_spin.step=0.1; fov_spin.value=float(data.settings.fov); v.add_child(fov_spin)
	v.add_child(_label("クロスヘア色（16進RGB）",15)); color_edit=LineEdit.new(); color_edit.text=str(data.settings.crosshair_color); color_edit.text_changed.connect(_preview_crosshair); v.add_child(color_edit)
	v.add_child(_label("クロスヘアサイズ",15)); size_spin=SpinBox.new(); size_spin.min_value=4; size_spin.max_value=30; size_spin.value=float(data.settings.crosshair_size); size_spin.value_changed.connect(_preview_crosshair_size); v.add_child(size_spin)
	v.add_child(_label("音量",15)); volume_slider=HSlider.new(); volume_slider.min_value=0; volume_slider.max_value=1; volume_slider.step=0.01; volume_slider.value=float(data.settings.volume); v.add_child(volume_slider)
	var actions:=HBoxContainer.new(); actions.add_theme_constant_override("separation",8); outer.add_child(actions)
	var resume:=Button.new(); resume.text="保存して戻る"; resume.custom_minimum_size=Vector2(160,46); resume.size_flags_horizontal=Control.SIZE_EXPAND_FILL; resume.pressed.connect(_close_pause); actions.add_child(resume)
	pause_army_button=Button.new(); pause_army_button.text="部隊画面"; pause_army_button.custom_minimum_size.y=46; pause_army_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; pause_army_button.pressed.connect(_pause_to_army); actions.add_child(pause_army_button)
	pause_end_button=Button.new(); pause_end_button.text="途中終了"; pause_end_button.custom_minimum_size.y=46; pause_end_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; pause_end_button.pressed.connect(_end_early); actions.add_child(pause_end_button)
	call_deferred("_resize_pause_card",overlay)
	return overlay

func _resize_pause_card(overlay:Control)->void:
	if not pause_card: return
	pause_card.custom_minimum_size=Vector2(maxf(300.0,minf(520.0,overlay.size.x-48.0)),maxf(220.0,minf(620.0,overlay.size.y-48.0)))

func _preview_crosshair(value:String)->void:
	crosshair_preview.set_appearance(value if Color.html_is_valid(value) else "66e8ff",size_spin.value)

func _preview_crosshair_size(value:float)->void:
	crosshair_preview.set_appearance(color_edit.text if Color.html_is_valid(color_edit.text) else "66e8ff",value)

func _select_weapon(i:int)->void: selected_weapon=i; _refresh_prep()
func _select_difficulty(i:int)->void: selected_difficulty=i; _refresh_prep()

func _refresh_prep()->void:
	if not supply_label: return
	supply_label.text="補給: %d" % int(data.supply)
	power_label.text="隊員 %d　装備倍率 ×%.2f　戦闘力 %.1f　自動補給 %.2f/秒" % [Balance.soldiers(int(data.recruit)), Balance.gear_multiplier(int(data.gear)), Balance.combat_power(int(data.recruit),int(data.gear)), Balance.passive_rate(int(data.depot))]
	var costs:=[Balance.recruit_cost(int(data.recruit)),Balance.gear_cost(int(data.gear)),Balance.depot_cost(int(data.depot))]
	var names:=["増員","装備強化","補給拠点"]
	var effects:=["隊員 %d → %d" % [Balance.soldiers(int(data.recruit)),Balance.soldiers(int(data.recruit)+1)],"倍率 ×%.2f → ×%.2f" % [Balance.gear_multiplier(int(data.gear)),Balance.gear_multiplier(int(data.gear)+1)],"%.2f/秒 → %.2f/秒" % [Balance.passive_rate(int(data.depot)),Balance.passive_rate(int(data.depot)+1)]]
	for i in 3:
		upgrade_buttons[i].text="%s　%s　価格 %d%s" % [names[i],effects[i],costs[i],"（補給不足）" if float(data.supply)<costs[i] else ""]
		upgrade_buttons[i].disabled=float(data.supply)<costs[i]
	for i in 3:
		weapon_buttons[i].disabled=not bool(data.unlocked[i]); weapon_buttons[i].text=Balance.WEAPONS[i] + ("" if data.unlocked[i] else "（未開放）"); weapon_buttons[i].button_pressed=i==selected_weapon
		difficulty_buttons[i].button_pressed=i==selected_difficulty
	if not bool(data.unlocked[selected_weapon]): selected_weapon=0
	if int(data.front)>=Balance.FRONT_HP.size():
		front_label.text="全戦線突破完了 — 訓練と自己ベスト更新を継続できます"; front_bar.value=100
	else:
		var maxhp:float=Balance.FRONT_HP[int(data.front)]; front_label.text="戦線 %d/%d　%s　敵耐久 %.0f/%.0f" % [int(data.front)+1,Balance.FRONT_HP.size(),Balance.FRONT_NAMES[int(data.front)],float(data.enemy_hp),maxhp]; front_bar.max_value=maxhp; front_bar.value=maxhp-float(data.enemy_hp)
	if army_title: army_title.text="部隊司令　装備外見 段階%d" % (Balance.visual_tier(int(data.gear))+1)
	_update_battle_view()

func _refresh_army_runtime()->void:
	supply_label.text="補給: %d" % int(data.supply)
	if int(data.front)>=Balance.FRONT_HP.size():
		front_label.text="全戦線突破完了 — 警戒進軍を継続中"; front_bar.value=front_bar.max_value
	else:
		var maxhp:float=Balance.FRONT_HP[int(data.front)]; front_label.text="戦線 %d/%d　%s　敵耐久 %.0f/%.0f" % [int(data.front)+1,Balance.FRONT_HP.size(),Balance.FRONT_NAMES[int(data.front)],float(data.enemy_hp),maxhp]; front_bar.max_value=maxhp; front_bar.value=maxhp-float(data.enemy_hp)
	_update_battle_view()

func _update_battle_view()->void:
	if not battle_view: return
	var front_index:=int(data.front)
	var enemy_max:float=float(Balance.FRONT_HP[front_index]) if front_index<Balance.FRONT_HP.size() else 1.0
	battle_view.set_state({"soldiers":Balance.soldiers(int(data.recruit)),"gear":int(data.gear),"depot":int(data.depot),"front":front_index,"enemy_hp":float(data.enemy_hp),"enemy_max":enemy_max,"complete":front_index>=Balance.FRONT_HP.size()})

func _buy_upgrade(kind:int)->void:
	var keys:=["recruit","gear","depot"]
	var costs:=[Balance.recruit_cost(int(data.recruit)),Balance.gear_cost(int(data.gear)),Balance.depot_cost(int(data.depot))]
	if float(data.supply)<costs[kind]: return
	data.supply=float(data.supply)-costs[kind]; data[keys[kind]]=int(data[keys[kind]])+1; SaveManager.save_data(data); _refresh_prep()

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
	training_weapon=selected_weapon; training_difficulty=selected_difficulty; time_left=TRAIN_DURATION; countdown=3.0; reward_committed=false; stats={"shots":0,"hits":0,"kills":0,"track_time":0.0,"fire_time":0.0}; fire_cooldown=0; burst_remaining=0; player.position=Vector3(0,1.7,8); player.rotation=Vector3.ZERO
	prep_panel.hide(); army_panel.hide(); result_panel.hide(); pause_panel.hide(); hud.show(); crosshair.show(); mode=Mode.COUNTDOWN; mouse_blocked=true; Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; _spawn_targets()

func _spawn_targets()->void:
	_clear_targets(); var count:=3 if training_weapon==2 else 1
	for i in count:
		var body:=StaticBody3D.new(); body.set_meta("target_index",i); target_root.add_child(body)
		var mesh:=MeshInstance3D.new(); var sphere:=SphereMesh.new(); sphere.radius=float(Balance.DIFFICULTY[training_difficulty].radius); sphere.height=sphere.radius*2.0; mesh.mesh=sphere; mesh.material_override=_material(Color("58edff") if training_weapon!=2 else Color("ffb84a")); body.add_child(mesh)
		var ring:=MeshInstance3D.new(); var torus:=TorusMesh.new(); torus.inner_radius=sphere.radius*0.48; torus.outer_radius=sphere.radius*0.62; ring.mesh=torus; ring.rotation_degrees.x=90; ring.material_override=_material(Color("ffffff")); body.add_child(ring)
		var shape:=CollisionShape3D.new(); var ss:=SphereShape3D.new(); ss.radius=sphere.radius; shape.shape=ss; body.add_child(shape)
		targets.append(body); target_progress.append(0); _relocate_target(i)

func _clear_targets()->void:
	for child in target_root.get_children(): child.queue_free()
	targets.clear(); target_progress.clear()

func _relocate_target(i:int)->void:
	if i>=targets.size(): return
	var r:float=Balance.DIFFICULTY[training_difficulty].range
	var x:=randf_range(-r,r); var y:=randf_range(1.1,4.1); var z:=randf_range(-10.5,-3.2)
	if training_weapon==2: x=lerpf(-r,r,float(i+1)/float(targets.size()+1))+randf_range(-0.6,0.6)
	targets[i].position=Vector3(x,y,z); target_progress[i]=0

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
		var sensitivity:=float(data.settings.sensitivity); var radians_per_unit:=deg_to_rad(0.022*sensitivity)
		player.rotate_y(-event.relative.x*radians_per_unit); camera.rotation.x=clampf(camera.rotation.x-event.relative.y*radians_per_unit,deg_to_rad(-89),deg_to_rad(89))
	if mode==Mode.TRAINING and event.is_action_pressed("shoot") and not mouse_blocked:
		if training_weapon==0: _fire_shot()
		elif training_weapon==2 and burst_remaining==0: burst_remaining=3; burst_timer=0.0
	if event.is_action_released("shoot"): mouse_blocked=false

func _physics_process(delta:float)->void:
	if mode==Mode.TRAINING:
		var input:=Input.get_vector("move_left","move_right","move_forward","move_back"); var dir:=(player.transform.basis*Vector3(input.x,0,input.y)).normalized(); player.velocity.x=dir.x*5.0; player.velocity.z=dir.z*5.0; player.velocity.y=0; player.move_and_slide(); player.position.x=clampf(player.position.x,-9.3,9.3); player.position.z=clampf(player.position.z,-11.0,11.0)
	else: player.velocity=Vector3.ZERO

func _process(delta:float)->void:
	hit_flash=maxf(0,hit_flash-delta); if hit_label: hit_label.modulate.a=clampf(hit_flash*5.0,0,1)
	if mode!=Mode.PAUSED: _process_battle(delta)
	if mode==Mode.COUNTDOWN:
		countdown-=delta; countdown_label.text=str(max(1,ceili(countdown)))
		if countdown<=0: mode=Mode.TRAINING; countdown_label.text=""; mouse_blocked=Input.is_action_pressed("shoot")
	elif mode==Mode.TRAINING:
		time_left=maxf(0,time_left-delta); timer_label.text="残り %.1f" % time_left; fire_cooldown=maxf(0,fire_cooldown-delta)
		_update_targets(delta); _process_weapon(delta); _update_hud()
		if time_left<=0: _finish_training(true)

func _process_weapon(delta:float)->void:
	if training_weapon==1 and Input.is_action_pressed("shoot") and not mouse_blocked:
		stats.fire_time=float(stats.fire_time)+delta
		if _ray_target_index()>=0: stats.track_time=float(stats.track_time)+delta
		if fire_cooldown<=0: _fire_shot(); fire_cooldown=0.1
	elif training_weapon==2 and burst_remaining>0:
		burst_timer-=delta
		if burst_timer<=0: _fire_shot(); burst_remaining-=1; burst_timer=0.085

func _fire_shot()->void:
	stats.shots=int(stats.shots)+1; var idx:=_ray_target_index(); _play_tone(620.0,0.035,0.10)
	if idx<0: return
	stats.hits=int(stats.hits)+1; hit_label.text="命中"; hit_flash=0.24; _play_tone(1050.0,0.045,0.16)
	if training_weapon==0:
		stats.kills=int(stats.kills)+1; _relocate_target(idx)
	elif training_weapon==2:
		target_progress[idx]+=1
		if target_progress[idx]>=3:
			stats.kills=int(stats.kills)+1; _relocate_target(idx)

func _ray_target_index()->int:
	var from:=camera.global_position; var to:=from-camera.global_transform.basis.z*100.0; var query:=PhysicsRayQueryParameters3D.create(from,to); query.collide_with_areas=false
	query.collision_mask=1
	var hit:=get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_meta("target_index"): return int(hit.collider.get_meta("target_index"))
	return -1

func _update_targets(delta:float)->void:
	if training_weapon!=1 or targets.is_empty(): return
	target_phase+=delta*float(Balance.DIFFICULTY[training_difficulty].speed)
	var r:float=Balance.DIFFICULTY[training_difficulty].range; targets[0].position.x=sin(target_phase)*r; targets[0].position.y=2.45+sin(target_phase*0.63)*1.15; targets[0].position.z=-7.0+cos(target_phase*0.37)*2.0

func _update_hud()->void:
	if training_weapon==0: stat_label.text="撃破 %d　命中 %d/%d" % [stats.kills,stats.hits,stats.shots]
	elif training_weapon==1: stat_label.text="追従 %.1f秒　射撃 %.1f秒" % [stats.track_time,stats.fire_time]
	else: stat_label.text="撃破 %d　有効命中 %d/%d　標的 %s" % [stats.kills,stats.hits,stats.shots,str(target_progress)]

func _finish_training(full_time:bool)->void:
	if reward_committed: return
	reward_committed=true; var result:=Balance.score_and_reward(training_weapon,training_difficulty,stats,int(data.front)); data.supply=float(data.supply)+int(result.supply)
	var key:="%d_%d"%[training_weapon,training_difficulty]; var previous:=int(data.bests.get(key,0)); var is_best:=full_time and int(result.score)>previous
	if is_best: data.bests[key]=int(result.score)
	SaveManager.save_data(data); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; mode=Mode.RESULT; prep_panel.hide(); army_panel.hide(); hud.hide(); pause_panel.hide(); result_panel.show(); _clear_targets()
	var metric:="撃破 %d　命中率 %.1f%%"%[stats.kills,float(result.accuracy)*100.0] if training_weapon!=1 else "追従 %.1f秒　追従率 %.1f%%"%[stats.track_time,float(result.accuracy)*100.0]
	result_title.text="訓練完了" if full_time else "途中終了"
	result_detail.text="%s / %s\n\nスコア %d%s\n自己ベスト %d\n%s\n\n獲得補給 +%d\n現在の補給 %d" % [Balance.WEAPONS[training_weapon],Balance.DIFFICULTY[training_difficulty].name,int(result.score),"　NEW BEST" if is_best else "",max(previous,int(data.bests.get(key,0))),metric,int(result.supply),int(data.supply)]

func _end_early()->void:
	if mode==Mode.PAUSED and mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]: _finish_training(false)

func _open_pause()->void:
	if mode==Mode.PAUSED: return
	mode_before_pause=mode; mode=Mode.PAUSED; Input.action_release("shoot"); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; pause_panel.show(); mouse_blocked=true; crosshair.hide()
	pause_end_button.visible=mode_before_pause in [Mode.COUNTDOWN,Mode.TRAINING]
	pause_army_button.visible=mode_before_pause!=Mode.ARMY
	_preview_crosshair(color_edit.text)

func _close_pause()->void:
	var sens:=float(sensitivity_edit.text); if sens<=0 or sens>20: sens=1.0
	data.settings.sensitivity=sens; data.settings.fov=fov_spin.value; data.settings.crosshair_color=color_edit.text if Color.html_is_valid(color_edit.text) else "66e8ff"; data.settings.crosshair_size=size_spin.value; data.settings.volume=volume_slider.value; _apply_settings();
	if not is_test_mode: SaveManager.save_data(data)
	pause_panel.hide(); mode=mode_before_pause
	if mode in [Mode.COUNTDOWN,Mode.TRAINING]: Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; mouse_blocked=true; crosshair.show()
	else: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; _refresh_prep()

func _apply_settings()->void:
	if not camera: return
	var h4:=deg_to_rad(float(data.settings.fov)); var aspect:=4.0/3.0; camera.fov=rad_to_deg(2.0*atan(tan(h4/2.0)/aspect))
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,float(data.settings.volume)))); AudioServer.set_bus_mute(0,float(data.settings.volume)<=0.001)
	if crosshair: crosshair.set_appearance(str(data.settings.crosshair_color),float(data.settings.crosshair_size))
	if crosshair_preview: crosshair_preview.set_appearance(str(data.settings.crosshair_color),float(data.settings.crosshair_size))

func _process_battle(delta:float)->void:
	data.supply=float(data.supply)+Balance.passive_rate(int(data.depot))*delta
	if int(data.front)<Balance.FRONT_HP.size():
		data.enemy_hp=float(data.enemy_hp)-Balance.combat_power(int(data.recruit),int(data.gear))*0.18*delta
		if float(data.enemy_hp)<=0: _advance_front()
	battle_save_timer+=delta
	if battle_save_timer>=15.0:
		battle_save_timer=0
		if not is_test_mode: SaveManager.save_data(data)
	if battle_hud:
		battle_hud.text="戦況: 全戦線突破" if int(data.front)>=Balance.FRONT_HP.size() else "戦線 %d/%d　敵耐久 %.0f\n味方 %d名 / 戦闘力 %.1f" % [int(data.front)+1,Balance.FRONT_HP.size(),float(data.enemy_hp),Balance.soldiers(int(data.recruit)),Balance.combat_power(int(data.recruit),int(data.gear))]
	if mode==Mode.ARMY:
		_refresh_army_runtime()

func _advance_front()->void:
	data.front=int(data.front)+1
	if int(data.front)>=3: data.unlocked[1]=true
	if int(data.front)>=7: data.unlocked[2]=true
	if int(data.front)<Balance.FRONT_HP.size(): data.enemy_hp=Balance.FRONT_HP[int(data.front)]
	else: data.enemy_hp=0.0
	SaveManager.save_data(data); hit_label.text="戦線突破！" if hit_label else ""; hit_flash=1.0

func _on_focus_lost()->void:
	Input.action_release("shoot"); mouse_blocked=true
	if mode in [Mode.COUNTDOWN,Mode.TRAINING]: _open_pause()

func _play_tone(freq:float,duration:float,volume:float)->void:
	var stream:=AudioStreamWAV.new(); stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=22050; stream.stereo=false
	var frames:=int(duration*stream.mix_rate); var bytes:=PackedByteArray(); bytes.resize(frames*2)
	for i in frames:
		var fade:=1.0-float(i)/frames; var sample:=int(sin(TAU*freq*i/stream.mix_rate)*32767.0*volume*fade); bytes.encode_s16(i*2,sample)
	stream.data=bytes; audio_player.stream=stream; audio_player.play()
