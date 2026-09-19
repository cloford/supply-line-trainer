class_name SaveManager
extends RefCounted

const PATH := "user://save_v1.json"
const TEMP := "user://save_v1.tmp"

static func defaults()->Dictionary:
	return {"version":1,"supply":90.0,"recruit":0,"gear":0,"depot":0,"front":0,"enemy_hp":Balance.FRONT_HP[0],"unlocked":[true,false,false],"bests":{},"settings":{"sensitivity":1.0,"fov":90.0,"crosshair_color":"66e8ff","crosshair_size":10.0,"volume":0.75},"last_save":int(Time.get_unix_time_from_system())}

static func load_data()->Dictionary:
	var data := defaults()
	if not FileAccess.file_exists(PATH): return data
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null: return data
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY: return data
	for key in data.keys():
		if parsed.has(key): data[key] = parsed[key]
	if typeof(data.settings) != TYPE_DICTIONARY: data.settings = defaults().settings
	for key in defaults().settings.keys():
		if not data.settings.has(key): data.settings[key] = defaults().settings[key]
	_sanitize_settings(data.settings)
	if typeof(data.unlocked) != TYPE_ARRAY or data.unlocked.size() != 3: data.unlocked = [true,false,false]
	data.supply = clampf(float(data.supply), 0.0, 1000000000.0)
	data.front = clampi(int(data.front), 0, Balance.FRONT_HP.size())
	return data

static func _sanitize_settings(settings:Dictionary)->void:
	var fallback:Dictionary=defaults().settings
	var sensitivity:=float(settings.sensitivity) if typeof(settings.sensitivity) in [TYPE_INT,TYPE_FLOAT] else float(fallback.sensitivity)
	settings.sensitivity=clampf(sensitivity,0.01,20.0) if is_finite(sensitivity) else fallback.sensitivity
	var fov:=float(settings.fov) if typeof(settings.fov) in [TYPE_INT,TYPE_FLOAT] else float(fallback.fov)
	settings.fov=clampf(fov,75.0,110.0) if is_finite(fov) else fallback.fov
	var size:=float(settings.crosshair_size) if typeof(settings.crosshair_size) in [TYPE_INT,TYPE_FLOAT] else float(fallback.crosshair_size)
	settings.crosshair_size=clampf(size,4.0,30.0) if is_finite(size) else fallback.crosshair_size
	var color_text:=str(settings.crosshair_color)
	settings.crosshair_color=color_text if Color.html_is_valid(color_text) else fallback.crosshair_color
	var volume:=float(settings.volume) if typeof(settings.volume) in [TYPE_INT,TYPE_FLOAT] else float(fallback.volume)
	settings.volume=clampf(volume,0.0,1.0) if is_finite(volume) else fallback.volume

static func save_data(data:Dictionary)->bool:
	data.last_save = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(TEMP, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(data))
	f.flush()
	f = null
	var dir := DirAccess.open("user://")
	if dir == null: return false
	if dir.file_exists("save_v1.json"): dir.remove("save_v1.json")
	return dir.rename("save_v1.tmp", "save_v1.json") == OK
