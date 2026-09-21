class_name SaveManager
extends RefCounted

const PATH := "user://save_v1.json"
const TEMP := "user://save_v1.tmp"
const BACKUP := "user://save_v1.backup.json"
const VERSION := 3

static func default_settings()->Dictionary:
	return {"sensitivity":1.0,"sensitivity_game":0,"dpi":800.0,"fov":90.0,"crosshair_color":"66e8ff","crosshair_size":10.0,"crosshair_shape":1,"crosshair_outline":true,"volume":0.75}
static func defaults()->Dictionary:
	return {"version":VERSION,"supply":90.0,"credits":"90","credit_fraction":0.0,"recruit":0,"gear":0,"depot":0,"front":0,"enemy_hp":Balance.front_hp(0),"unlocked":[true,false,false],"bests":{},"legacy_bests":{},"bests_v2":{},"selected_duration":60,"commander_owned":[],"commander_equipped":["","",""],"settings":default_settings(),"last_save":int(Time.get_unix_time_from_system())}

static func load_data()->Dictionary:
	var data:=defaults()
	if not FileAccess.file_exists(PATH):return data
	var f:=FileAccess.open(PATH,FileAccess.READ)
	if f==null:return data
	var parsed=JSON.parse_string(f.get_as_text())
	if typeof(parsed)!=TYPE_DICTIONARY:return data
	var old_version:=int(parsed.get("version",1))
	if old_version<VERSION and not FileAccess.file_exists(BACKUP):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH),ProjectSettings.globalize_path(BACKUP))
	for key in data.keys():
		if parsed.has(key):data[key]=parsed[key]
	if old_version<2:
		data.legacy_bests=data.bests.duplicate(true) if typeof(data.bests)==TYPE_DICTIONARY else {}
		data.bests_v2={}
	if old_version<VERSION or not parsed.has("credits"):data.credits=BigUInt.from_float(float(parsed.get("supply",90.0)))
	if typeof(data.settings)!=TYPE_DICTIONARY:data.settings=default_settings()
	for key in default_settings().keys():
		if not data.settings.has(key):data.settings[key]=default_settings()[key]
	_sanitize_settings(data.settings)
	if typeof(data.unlocked)!=TYPE_ARRAY or data.unlocked.size()!=3:data.unlocked=[true,false,false]
	if typeof(data.commander_owned)!=TYPE_ARRAY:data.commander_owned=[]
	if typeof(data.commander_equipped)!=TYPE_ARRAY or data.commander_equipped.size()!=3:data.commander_equipped=["","",""]
	data.supply=clampf(float(data.supply),0.0,1.0e290)
	data.credits=BigUInt.normalize(str(data.credits));data.credit_fraction=clampf(float(data.credit_fraction),0.0,0.999999)
	data.front=maxi(0,int(data.front))
	data.recruit=clampi(int(data.recruit),0,10000)
	data.gear=clampi(int(data.gear),0,10000)
	data.depot=clampi(int(data.depot),0,10000)
	data.selected_duration=30 if int(data.selected_duration)==30 else 60
	if float(data.enemy_hp)<=0.0:data.enemy_hp=Balance.front_hp(int(data.front))
	data.enemy_hp=clampf(float(data.enemy_hp),0.0,Balance.front_hp(int(data.front)))
	data.version=VERSION
	return data

static func _sanitize_settings(settings:Dictionary)->void:
	var fallback:=default_settings()
	var sensitivity:=float(settings.sensitivity) if typeof(settings.sensitivity) in [TYPE_INT,TYPE_FLOAT] else float(fallback.sensitivity)
	settings.sensitivity=clampf(sensitivity,0.001,100.0) if is_finite(sensitivity) else fallback.sensitivity
	settings.sensitivity_game=clampi(int(settings.sensitivity_game),0,2)
	settings.dpi=clampf(float(settings.dpi),100.0,64000.0)
	var fov:=float(settings.fov) if typeof(settings.fov) in [TYPE_INT,TYPE_FLOAT] else float(fallback.fov)
	settings.fov=clampf(fov,75.0,110.0) if is_finite(fov) else fallback.fov
	var size:=float(settings.crosshair_size) if typeof(settings.crosshair_size) in [TYPE_INT,TYPE_FLOAT] else float(fallback.crosshair_size)
	settings.crosshair_size=clampf(size,4.0,30.0) if is_finite(size) else fallback.crosshair_size
	settings.crosshair_shape=clampi(int(settings.crosshair_shape),0,3)
	settings.crosshair_outline=bool(settings.crosshair_outline)
	var color_text:=str(settings.crosshair_color)
	settings.crosshair_color=color_text if Color.html_is_valid(color_text) else fallback.crosshair_color
	var volume:=float(settings.volume) if typeof(settings.volume) in [TYPE_INT,TYPE_FLOAT] else float(fallback.volume)
	settings.volume=clampf(volume,0.0,1.0) if is_finite(volume) else fallback.volume

static func save_data(data:Dictionary)->bool:
	if not data.has("credits"):data.credits=BigUInt.from_float(float(data.get("supply",90.0)))
	if not data.has("credit_fraction"):data.credit_fraction=0.0
	data.version=VERSION;data.last_save=int(Time.get_unix_time_from_system());data.supply=BigUInt.to_float(str(data.credits))
	var f:=FileAccess.open(TEMP,FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify(data));f.flush();f=null
	var dir:=DirAccess.open("user://")
	if dir==null:return false
	if dir.file_exists("save_v1.json"):dir.remove("save_v1.json")
	return dir.rename("save_v1.tmp","save_v1.json")==OK
