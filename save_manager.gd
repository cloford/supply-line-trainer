class_name SaveManager
extends RefCounted

const PATH := "user://save_v1.json"
const TEMP := "user://save_v1.tmp"
const LEGACY_BACKUP := "user://save_v1.backup.json"
const GROWTH_RESET_BACKUP := "user://save_before_growth_reset_v4.json"
const POINTS_BACKUP := "user://save_before_v1_4.json"
const VERSION := 4
const GROWTH_BACKUP := "user://save_before_growth_v1_5.json"
const METRICS_BACKUP := "user://save_before_metrics_v1_6.json"
const REWARD_BACKUP := "user://save_before_reward_v1_7.json"

static func default_settings()->Dictionary:
	return {"sensitivity":1.0,"sensitivity_game":0,"dpi":800.0,"fov":90.0,"crosshair_color":"66e8ff","crosshair_size":10.0,"crosshair_shape":1,"crosshair_outline":true,"volume":0.75,"shot_sound":0,"shot_volume":0.55,"hit_sound":0,"hit_volume":0.55,"hit_pitch_combo":true,"score_details":false,"auto_update":true}

static func defaults()->Dictionary:
	var data:Dictionary={"version":VERSION,"migration":"points_v1_4","scoring_version":4,"supply":0.0,"credits":"0","credit_fraction":0.0,"recruit":0,"gear":0,"depot":0,"front":0,"enemy_hp":Balance.front_hp(0),"unlocked":[true,false,false],"bests":{},"legacy_bests":{},"bests_v2":{},"selected_duration":0,"training_schema":2,"bests_v3":{},"bests_v4":{},"practice_totals":TrainingLedger.totals(),"training_history":[],"legacy_training_history":[],"active_training":{},"commander_owned":[],"commander_equipped":["","",""],"settings":default_settings(),"last_save":int(Time.get_unix_time_from_system()),"growth_schema":1,"legacy_army_multiplier":1.0,"growth_migration_notice":false,"upgrade_goal":{},"goal_notice_levels":[0,0]}
	GrowthGoal.ensure(data)
	data["metrics_schema"]=1
	data["scoring_capture_schema"]=1
	return data

static func load_data()->Dictionary:
	var data:=defaults()
	if not FileAccess.file_exists(PATH) and FileAccess.file_exists("user://save_v1.previous.json"):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("user://save_v1.previous.json"),ProjectSettings.globalize_path(PATH))
	if not FileAccess.file_exists(PATH):return data
	var f:=FileAccess.open(PATH,FileAccess.READ)
	if f==null:
		data["migration_failed"]=true
		return data
	var raw_text:=f.get_as_text();f=null
	var json:=JSON.new()
	if json.parse(raw_text)!=OK:
		data["migration_failed"]=true
		return data
	var parsed=json.data
	if typeof(parsed)!=TYPE_DICTIONARY:
		data["migration_failed"]=true
		return data
	var needs_growth:=int(parsed.get("growth_schema",0))<1
	if int(parsed.get("scoring_capture_schema",0))<1 and not FileAccess.file_exists(REWARD_BACKUP):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH),ProjectSettings.globalize_path(REWARD_BACKUP))!=OK:
			for key in data.keys():
				if parsed.has(key):data[key]=parsed[key]
			data.settings=_merged_settings(data.settings);data["migration_failed"]=true
			return data
	# 計測追加前の原本を一度だけ保護。失敗したときは後続の移行・保存を実行しない。
	if int(parsed.get("metrics_schema",0))<1 and not FileAccess.file_exists(METRICS_BACKUP):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH),ProjectSettings.globalize_path(METRICS_BACKUP))!=OK:
			for key in data.keys():
				if parsed.has(key):data[key]=parsed[key]
			data.settings=_merged_settings(data.settings);data["migration_failed"]=true
			return data
	var growth_backup_ok:=true
	if needs_growth and not FileAccess.file_exists(GROWTH_BACKUP):
		growth_backup_ok=DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH),ProjectSettings.globalize_path(GROWTH_BACKUP))==OK
	var needs_migration:=int(parsed.get("scoring_version",3))<4
	var backup_ok:=true
	if needs_migration:
		backup_ok=_backup_before_points_migration()
	for key in data.keys():
		if parsed.has(key):data[key]=parsed[key]
	data.settings=_merged_settings(data.settings)
	if bool(parsed.get("migration_failed",false)):data["migration_failed"]=true
	if typeof(data.unlocked)!=TYPE_ARRAY or data.unlocked.size()!=3:data.unlocked=[true,false,false]
	if typeof(data.commander_owned)!=TYPE_ARRAY:data.commander_owned=[]
	if typeof(data.commander_equipped)!=TYPE_ARRAY or data.commander_equipped.size()!=3:data.commander_equipped=["","",""]
	data.credits=BigUInt.normalize(str(parsed.credits)) if parsed.has("credits") else BigUInt.from_float(float(parsed.get("supply",0.0)))
	data.credit_fraction=clampf(float(data.credit_fraction),0.0,0.999999999)
	data.front=maxi(0,int(data.front));data.recruit=maxi(0,int(data.recruit));data.gear=maxi(0,int(data.gear));data.depot=0
	data.selected_duration=0
	for key in ["bests","legacy_bests","bests_v2","bests_v3","bests_v4"]:
		if typeof(data[key])!=TYPE_DICTIONARY:data[key]={}
	if typeof(data.practice_totals)!=TYPE_DICTIONARY:data.practice_totals=TrainingLedger.totals()
	for key in TrainingLedger.totals():
		if not data.practice_totals.has(key):data.practice_totals[key]=TrainingLedger.totals()[key]
	if typeof(data.training_history)!=TYPE_ARRAY:data.training_history=[]
	if typeof(data.legacy_training_history)!=TYPE_ARRAY:data.legacy_training_history=[]
	if typeof(data.active_training)!=TYPE_DICTIONARY:data.active_training={}
	if float(data.enemy_hp)<=0.0:data.enemy_hp=Balance.front_hp(int(data.front))
	data.enemy_hp=clampf(float(data.enemy_hp),0.0,Balance.front_hp(int(data.front)))
	if needs_growth:
		if not growth_backup_ok:
			data["migration_failed"]=true
			return data
		_migrate_commander(data)
	GrowthGoal.ensure(data)
	if needs_migration:
		if not backup_ok:
			data["migration_failed"]=true
			push_error("v1.4更新前のバックアップに失敗しました。保存を停止します。")
			return data
		# 旧チェックポイントの補給・時間は既に反映済み。同じ値を確定して再加算を防ぐ。
		data.legacy_training_history.append_array(data.training_history)
		data.training_history=[]
		TrainingLedger.recover(data)
		data.legacy_training_history.append_array(data.training_history)
		data.training_history=[]
		data.scoring_version=4;data.training_schema=2
		if not save_data(data):data["migration_failed"]=true
	if needs_growth and not needs_migration:
		if not save_data(data):data["migration_failed"]=true
	data.version=VERSION;data.migration="points_v1_4"
	data.metrics_schema=1
	data.scoring_capture_schema=1
	return data

static func _migrate_commander(data:Dictionary)->void:
	var known:Array[String]=[]
	for item in Balance.LEGACY_COMMANDER_ITEMS:
		var id:=str(item.id)
		var slot:=int(item.slot)
		if id in data.commander_owned or str(data.commander_equipped[slot])==id:known.append(id)
	var multiplier:=1.0
	for item in Balance.LEGACY_COMMANDER_ITEMS:
		if str(item.id) in known:multiplier*=float(item.combat)
	data.legacy_army_multiplier=multiplier
	data.growth_schema=1
	data.growth_migration_notice=not known.is_empty()

static func _backup_before_points_migration()->bool:
	if FileAccess.file_exists(POINTS_BACKUP):return true
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH),ProjectSettings.globalize_path(POINTS_BACKUP))==OK

static func _merged_settings(source:Variant)->Dictionary:
	var settings:Dictionary=source.duplicate(true) if typeof(source)==TYPE_DICTIONARY else {}
	for key in default_settings().keys():
		if not settings.has(key):settings[key]=default_settings()[key]
	_sanitize_settings(settings)
	return settings

static func _sanitize_settings(settings:Dictionary)->void:
	var fallback:=default_settings()
	var sensitivity:=float(settings.sensitivity) if typeof(settings.sensitivity) in [TYPE_INT,TYPE_FLOAT] else float(fallback.sensitivity)
	settings.sensitivity=clampf(sensitivity,0.001,100.0) if is_finite(sensitivity) else fallback.sensitivity
	settings.sensitivity_game=clampi(int(settings.sensitivity_game),0,2);settings.dpi=clampf(float(settings.dpi),100.0,64000.0)
	var fov:=float(settings.fov) if typeof(settings.fov) in [TYPE_INT,TYPE_FLOAT] else float(fallback.fov)
	settings.fov=clampf(fov,75.0,110.0) if is_finite(fov) else fallback.fov
	var size:=float(settings.crosshair_size) if typeof(settings.crosshair_size) in [TYPE_INT,TYPE_FLOAT] else float(fallback.crosshair_size)
	settings.crosshair_size=clampf(size,4.0,30.0) if is_finite(size) else fallback.crosshair_size
	settings.crosshair_shape=clampi(int(settings.crosshair_shape),0,3);settings.crosshair_outline=bool(settings.crosshair_outline)
	var color_text:=str(settings.crosshair_color);settings.crosshair_color=color_text if Color.html_is_valid(color_text) else fallback.crosshair_color
	settings.volume=clampf(float(settings.volume),0.0,1.0);settings.shot_sound=clampi(int(settings.shot_sound),0,3);settings.hit_sound=clampi(int(settings.hit_sound),0,3)
	settings.shot_volume=clampf(float(settings.shot_volume),0.0,1.0);settings.hit_volume=clampf(float(settings.hit_volume),0.0,1.0);settings.hit_pitch_combo=bool(settings.hit_pitch_combo)
	settings.score_details=bool(settings.score_details);settings.auto_update=bool(settings.auto_update)

static func save_data(data:Dictionary)->bool:
	if bool(data.get("migration_failed",false)):return false
	if not data.has("credits"):data.credits=BigUInt.from_float(float(data.get("supply",0.0)))
	data.version=VERSION;data.migration="points_v1_4";data.scoring_version=4;data.training_schema=2;data.selected_duration=0;data.last_save=int(Time.get_unix_time_from_system());data.supply=BigUInt.to_float(str(data.credits));data.depot=0
	var f:=FileAccess.open(TEMP,FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify(data));f.flush();f=null
	var dir:=DirAccess.open("user://")
	if dir==null:return false
	if dir.file_exists("save_v1.json"):
		if dir.file_exists("save_v1.previous.json") and dir.remove("save_v1.previous.json")!=OK:return false
		if dir.rename("save_v1.json","save_v1.previous.json")!=OK:return false
	var rename_result:=dir.rename("save_v1.tmp","save_v1.json")
	if rename_result!=OK and dir.file_exists("save_v1.previous.json"):
		dir.rename("save_v1.previous.json","save_v1.json")
	return rename_result==OK
