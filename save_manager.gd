class_name SaveManager
extends RefCounted

const PATH := "user://save_v1.json"
const TEMP := "user://save_v1.tmp"
const LEGACY_BACKUP := "user://save_v1.backup.json"
const GROWTH_RESET_BACKUP := "user://save_before_growth_reset_v4.json"
const VERSION := 4

static func default_settings()->Dictionary:
	return {"sensitivity":1.0,"sensitivity_game":0,"dpi":800.0,"fov":90.0,"crosshair_color":"66e8ff","crosshair_size":10.0,"crosshair_shape":1,"crosshair_outline":true,"volume":0.75,"shot_sound":0,"shot_volume":0.55,"hit_sound":0,"hit_volume":0.55,"hit_pitch_combo":true}

static func defaults()->Dictionary:
	return {"version":VERSION,"migration":"growth_reset_v4","supply":0.0,"credits":"0","credit_fraction":0.0,"recruit":0,"gear":0,"depot":0,"front":0,"enemy_hp":Balance.front_hp(0),"unlocked":[true,false,false],"bests":{},"legacy_bests":{},"bests_v2":{},"selected_duration":60,"commander_owned":[],"commander_equipped":["","",""],"settings":default_settings(),"last_save":int(Time.get_unix_time_from_system())}

static func load_data()->Dictionary:
	var data:=defaults()
	if not FileAccess.file_exists(PATH):return data
	var f:=FileAccess.open(PATH,FileAccess.READ)
	if f==null:return data
	var raw_text:=f.get_as_text();f=null
	var parsed=JSON.parse_string(raw_text)
	if typeof(parsed)!=TYPE_DICTIONARY:return data
	var old_version:=int(parsed.get("version",1))
	if old_version<VERSION:
		if not _backup_before_migration(old_version):
			for key in data.keys():
				if parsed.has(key):data[key]=parsed[key]
			data.settings=_merged_settings(parsed.get("settings",{}));data["migration_failed"]=true
			return data
		data.settings=_merged_settings(parsed.get("settings",{}))
		data.bests_v2=parsed.get("bests_v2",{}).duplicate(true) if typeof(parsed.get("bests_v2",{}))==TYPE_DICTIONARY else {}
		data.legacy_bests=parsed.get("legacy_bests",{}).duplicate(true) if typeof(parsed.get("legacy_bests",{}))==TYPE_DICTIONARY else {}
		if old_version<2 and typeof(parsed.get("bests",{}))==TYPE_DICTIONARY:data.legacy_bests=parsed.bests.duplicate(true)
		data.selected_duration=30 if int(parsed.get("selected_duration",60))==30 else 60
		if not save_data(data):data["migration_failed"]=true
		return data
	for key in data.keys():
		if parsed.has(key):data[key]=parsed[key]
	data.settings=_merged_settings(data.settings)
	if typeof(data.unlocked)!=TYPE_ARRAY or data.unlocked.size()!=3:data.unlocked=[true,false,false]
	if typeof(data.commander_owned)!=TYPE_ARRAY:data.commander_owned=[]
	if typeof(data.commander_equipped)!=TYPE_ARRAY or data.commander_equipped.size()!=3:data.commander_equipped=["","",""]
	data.credits=BigUInt.normalize(str(data.credits));data.credit_fraction=clampf(float(data.credit_fraction),0.0,0.999999)
	data.front=maxi(0,int(data.front));data.recruit=clampi(int(data.recruit),0,10000);data.gear=clampi(int(data.gear),0,10000);data.depot=0
	data.selected_duration=30 if int(data.selected_duration)==30 else 60
	if float(data.enemy_hp)<=0.0:data.enemy_hp=Balance.front_hp(int(data.front))
	data.enemy_hp=clampf(float(data.enemy_hp),0.0,Balance.front_hp(int(data.front)))
	data.version=VERSION;data.migration="growth_reset_v4"
	return data

static func _backup_before_migration(old_version:int)->bool:
	var destination:=GROWTH_RESET_BACKUP if old_version>=3 else LEGACY_BACKUP
	if FileAccess.file_exists(destination):return true
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH),ProjectSettings.globalize_path(destination))==OK

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

static func save_data(data:Dictionary)->bool:
	if bool(data.get("migration_failed",false)):return false
	if not data.has("credits"):data.credits=BigUInt.from_float(float(data.get("supply",0.0)))
	data.version=VERSION;data.migration="growth_reset_v4";data.last_save=int(Time.get_unix_time_from_system());data.supply=BigUInt.to_float(str(data.credits));data.depot=0
	var f:=FileAccess.open(TEMP,FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify(data));f.flush();f=null
	var dir:=DirAccess.open("user://")
	if dir==null:return false
	if dir.file_exists("save_v1.json") and dir.remove("save_v1.json")!=OK:return false
	var rename_result:=dir.rename("save_v1.tmp","save_v1.json")
	if rename_result!=OK and FileAccess.file_exists(GROWTH_RESET_BACKUP):DirAccess.copy_absolute(ProjectSettings.globalize_path(GROWTH_RESET_BACKUP),ProjectSettings.globalize_path(PATH))
	return rename_result==OK
