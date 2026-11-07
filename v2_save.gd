class_name V2Save
extends RefCounted

const PATH := "user://save_v2.json"
const TEMP := "user://save_v2.tmp"
const PREVIOUS := "user://save_v2.previous.json"
const LEGACY := "user://save_v1.json"
const RESET_GUARD := "user://reset_generation.json"
const SETTING_DEFAULTS := {"sensitivity":1.0,"sensitivity_game":0,"dpi":800.0,"fov":90.0,"crosshair_color":"66e8ff","crosshair_size":10.0,"crosshair_shape":1,"crosshair_outline":true,"volume":0.75,"shot_sound":0,"shot_volume":0.55,"hit_sound":0,"hit_volume":0.55,"hit_pitch_combo":true,"score_details":false,"auto_update":true,"show_training_goal":false,"goal_notifications":true,"effects_enabled":true}
static var last_error := ""
static var test_fail_step := ""

static func defaults()->Dictionary:
	return {"version":V2Rules.SAVE_VERSION,"scoring_version":TargetScoring.VERSION,"migration":"settings_only_v2","migration_notice":true,"credits":"0","lifetime_credits":"0","credit_fraction":0.0,"practice_totals":TrainingLedger.totals(),"training_history":[],"active_training":{},"settled_training_ids":[],"completed_measurement_ids":[],"measurement_counts":[0,0,0],"armor":[false,false,false],"protection":[0,0,0],"profiles":[{},{},{}],"previous_profiles":[{},{},{}],"names":["ハンドガン兵","アサルト兵","バースト兵"],"deployed":[true,true,true],"front":0,"battle_status":"fighting","expedition_complete":false,"settings":SETTING_DEFAULTS.duplicate(true),"selected_weapon":0,"selected_difficulty":0,"selected_duration":0,"help_seen":false,"v2_notice_seen":false,"selected_measurement":false,"last_save":0,"intro_seen":false,"guidance_credited":false,"target_risk":TargetScoring.DEFAULT_RISK,"progression":Progression.defaults()}

static func validate_settings(source:Variant)->Dictionary:
	var result := SETTING_DEFAULTS.duplicate(true)
	if not source is Dictionary:
		return result
	var limits := {"sensitivity":[0.001,100.0],"sensitivity_game":[0,2],"dpi":[100.0,64000.0],"fov":[75.0,110.0],"crosshair_size":[4.0,30.0],"crosshair_shape":[0,3],"volume":[0.0,1.0],"shot_sound":[0,3],"shot_volume":[0.0,1.0],"hit_sound":[0,3],"hit_volume":[0.0,1.0]}
	for key in result:
		if not source.has(key):
			continue
		var value:Variant = source[key]
		if key == "crosshair_color":
			if value is String and Color.html_is_valid(value):
				result[key] = value
		elif typeof(result[key]) == TYPE_BOOL:
			if typeof(value) == TYPE_BOOL:
				result[key] = value
		elif limits.has(key) and typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)):
			var bound:Array = limits[key]
			result[key] = clampi(int(value),int(bound[0]),int(bound[1])) if typeof(result[key]) == TYPE_INT else clampf(float(value),float(bound[0]),float(bound[1]))
	return result

static func _failure(reason:String)->Dictionary:
	last_error = reason
	var data := defaults()
	data["migration_failed"] = true
	data["migration_error"] = reason
	data["retry_possible"] = true
	return data

static func _valid_data(data:Variant)->bool:
	if not data is Dictionary or typeof(data.get("version")) not in [TYPE_INT,TYPE_FLOAT] or int(data.get("version",0)) != V2Rules.SAVE_VERSION:
		return false
	if data.has("progression") and not Progression.valid(data.progression):
		return false
	if data.has("intro_seen") and typeof(data.intro_seen) != TYPE_BOOL:
		return false
	if data.has("guidance_credited") and typeof(data.guidance_credited) != TYPE_BOOL:return false
	if data.has("target_risk") and (typeof(data.target_risk) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data.target_risk)) or float(data.target_risk) < 0.0 or float(data.target_risk) > 1.0):return false
	for key in ["credits","lifetime_credits"]:
		if not data.get(key) is String or BigUInt.normalize(data[key]) != data[key]:
			return false
	for key in ["practice_totals","settings","active_training"]:
		if not data.get(key) is Dictionary:
			return false
	for key in ["training_history","settled_training_ids","completed_measurement_ids"]:
		if not data.get(key) is Array:
			return false
	for key in ["measurement_counts","armor","protection","profiles","previous_profiles","names","deployed"]:
		if not data.get(key) is Array or data[key].size() != 3:
			return false
	for key in TrainingLedger.totals():
		if not data.practice_totals.has(key) or typeof(data.practice_totals[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data.practice_totals[key])):
			return false
	for key in ["front","credit_fraction"]:
		if typeof(data.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) < 0.0:
			return false
	if float(data.credit_fraction) >= 1.0:
		return false
	for id in data.settled_training_ids + data.completed_measurement_ids:
		if not id is String:
			return false
	for entry in data.training_history + [data.active_training]:
		if not entry is Dictionary:
			return false
		if entry.is_empty():
			continue
		if not entry.get("id") is String:
			return false
		for key in ["weapon","duration","elapsed","active","credits"]:
			if typeof(entry.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(entry[key])) or float(entry[key]) < 0.0:
				return false
		for key in ["progress_kills","progress_tracking_seconds"]:
			if entry.has(key) and (typeof(entry[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(entry[key])) or float(entry[key]) < 0.0):
				return false
		if entry.has("progress_kills") and float(entry.progress_kills) != floor(float(entry.progress_kills)):
			return false
		if entry.has("progress_measurement") and typeof(entry.progress_measurement) != TYPE_BOOL:
			return false
	for weapon in range(3):
		for key in ["protection","measurement_counts"]:
			if typeof(data[key][weapon]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key][weapon])) or float(data[key][weapon]) != floor(float(data[key][weapon])):
				return false
		if typeof(data.armor[weapon]) != TYPE_BOOL or typeof(data.deployed[weapon]) != TYPE_BOOL or not data.names[weapon] is String:
			return false
		if int(data.protection[weapon]) < 0 or int(data.protection[weapon]) > 5 or int(data.measurement_counts[weapon]) < 0:
			return false
		for key in ["profiles","previous_profiles"]:
			var bundle:Variant = data[key][weapon]
			if not bundle is Dictionary:
				return false
			if not bundle.is_empty():
				if not bundle.get("record") is Dictionary or not bundle.get("profile") is Dictionary:
					return false
				var converted := V2Profiles.from_record(bundle.record)
				if converted.is_empty() or int(converted.weapon) != weapon or str(converted.record_id) != str(bundle.profile.get("record_id","")):
					return false
				for field in ["rpm","p","q","c","shot_count","hit_count","profile_version","weapon"]:
					if typeof(bundle.profile.get(field)) not in [TYPE_INT,TYPE_FLOAT] or not is_equal_approx(float(bundle.profile[field]),float(converted[field])):
						return false
				if bundle.profile.get("timeline") != converted.timeline:
					return false
	return true

static func _read(path:String)->Variant:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data

static func _unique_path(prefix:String)->String:
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var base := "user://%s_%s_%d" % [prefix,stamp,Time.get_ticks_usec()]
	var result := base + ".json"
	var suffix := 0
	while FileAccess.file_exists(result):
		suffix += 1
		result = base + "_%d.json" % suffix
	return result

static func _copy(source:String, target:String)->bool:
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(target)) == OK

static func _fail(step:String)->bool:
	return OS.get_environment("SLT_TEST_DATA") == "1" and test_fail_step == step

static func load_data()->Dictionary:
	last_error = ""
	var guard:Variant = _read(RESET_GUARD) if FileAccess.file_exists(RESET_GUARD) else {}
	if not guard is Dictionary:return _failure("初期化世代の確認に失敗しました。保存ファイルと初期化前バックアップを保全しています。")
	var expected := str(guard.get("generation",""))
	if FileAccess.file_exists(PATH) or FileAccess.file_exists(PREVIOUS):
		var parsed:Variant = _read(PATH) if FileAccess.file_exists(PATH) else null
		if not expected.is_empty() and (not parsed is Dictionary or str(parsed.get("reset_generation","")) != expected):parsed = null
		if not _valid_data(parsed):
			var previous:Variant = _read(PREVIOUS)
			if not expected.is_empty() and (not previous is Dictionary or str(previous.get("reset_generation","")) != expected):previous = null
			if not _valid_data(previous):
				return _failure("新セーブが読めません。原本を保全したまま再試行できます。")
			if FileAccess.file_exists(PATH):
				var protected := _unique_path("save_v2_corrupt")
				if not _copy(PATH,protected):
					return _failure("破損セーブの保全に失敗しました。")
				if DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH)) != OK:
					return _failure("破損セーブを保護後に復旧できませんでした。")
			if not _copy(PREVIOUS,PATH):
				return _failure("直前セーブの復旧に失敗しました。")
			parsed = previous
			parsed["recovery_notice"] = "直前に確定した保存から復旧しました。"
		var data:Dictionary = parsed
		# 既存プレイヤーには新規導入演出を挿入しない。
		if not data.has("intro_seen"):
			data.intro_seen = true
		# 既存進行へ後日の誘導一発を追加しない。旧難易度の履歴は不変、未設定の曲線は初期値へ。
		if not data.has("guidance_credited"):data.guidance_credited = bool(data.intro_seen) or Progression.total(data) > 0
		data.target_risk = TargetScoring.safe_risk(data.get("target_risk",TargetScoring.DEFAULT_RISK))
		data.settings = validate_settings(data.settings)
		data.training_history.resize(mini(data.training_history.size(),V2Rules.HISTORY_LIMIT))
		var migrated := Progression.migrate(data)
		var recovered := V2Ledger.recover(data)
		if (migrated or recovered) and not save_data(data):
			return _failure("中断記録の確定保存に失敗しました。" + last_error)
		return data
	var data := defaults()
	if not expected.is_empty():return _failure("初期化後の保存が読めません。旧データの自動復元を停止しています。初期化前バックアップ："+str(guard.get("backup","")))
	if FileAccess.file_exists(LEGACY):
		if _fail("backup"):
			return _failure("旧データのバックアップに失敗しました。")
		var backup := _unique_path("save_v1_before_v2")
		if not _copy(LEGACY,backup):
			return _failure("旧データのバックアップに失敗しました。")
		var legacy:Variant = _read(LEGACY)
		if not legacy is Dictionary or _fail("settings_read"):
			return _failure("旧設定の読み込みに失敗しました。旧データは変更していません。")
		data.settings = validate_settings(legacy.get("settings",{}))
		data["legacy_backup"] = backup
	if not save_data(data):
		return _failure("新セーブの初回作成に失敗しました。" + last_error)
	return data

# 呼出側はwriterを排他停止してから実行する。退避先は通常復旧の検索対象外。
static func reset_all()->Dictionary:
	last_error = ""
	var generation := "%d_%d" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	var backup := "user://reset_archive_"+generation
	if DirAccess.make_dir_absolute(ProjectSettings.globalize_path(backup)) != OK:return {"okay":false,"error":"初期化前バックアップの保存先を作れません。"}
	for path in [PATH,PREVIOUS,TEMP,LEGACY,RESET_GUARD]:
		if FileAccess.file_exists(path) and (not _copy(path,backup+"/"+path.get_file()) or FileAccess.get_sha256(path) != FileAccess.get_sha256(backup+"/"+path.get_file())):
			return {"okay":false,"error":"初期化前データの退避・照合に失敗しました。元データを保持しています。","backup":backup}
	var candidate := defaults()
	candidate.reset_generation = generation
	candidate.v2_notice_seen = true
	var old_guard:Variant = _read(RESET_GUARD)
	var guard_file := FileAccess.open(RESET_GUARD,FileAccess.WRITE)
	if guard_file == null:return {"okay":false,"error":"初期化世代を保存できません。元データを保持しています。","backup":backup}
	guard_file.store_string(JSON.stringify({"generation":generation,"backup":backup}))
	guard_file.flush()
	var guard_error := guard_file.get_error()
	guard_file = null
	var checked_guard:Variant = _read(RESET_GUARD)
	if guard_error != OK or not checked_guard is Dictionary or str(checked_guard.get("generation","")) != generation:
		_restore_reset_guard(old_guard)
		return {"okay":false,"error":"初期化世代の検証に失敗しました。元データを保持しています。","backup":backup}
	if not save_data(candidate):
		var reason := last_error
		_restore_reset_guard(old_guard)
		return {"okay":false,"error":reason+" 初期化前バックアップから復旧できます。","backup":backup}
	# 通常fallbackも新世代へ揃える。失敗時もguardが旧進行の復活を防ぐ。
	if not _copy(PATH,PREVIOUS):
		return {"okay":false,"error":"新規状態は保存しましたが復旧用コピーに失敗しました。再読み込み後に初期化を再試行できます。","backup":backup,"new_data":candidate}
	return {"okay":true,"data":candidate,"backup":backup}

static func _restore_reset_guard(previous:Variant)->void:
	if previous is Dictionary:
		var file := FileAccess.open(RESET_GUARD,FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(previous));file.flush()
	elif FileAccess.file_exists(RESET_GUARD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESET_GUARD))

# 履歴の各確定recordは不変。外側の配列だけ複製し、候補への追加/差替えを隔離する。
# mutableな現行セッション・設定・進行・所持量は深く複製する。
static func transaction_copy(data:Dictionary)->Dictionary:
	var candidate:Dictionary = {}
	for key in data:
		var value:Variant = data[key]
		if key in ["training_history","profiles","previous_profiles"]:
			candidate[key] = value.duplicate()
		else:
			candidate[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return candidate

static func save_data(data:Dictionary)->bool:
	return save_owned_snapshot(data.duplicate(true))

# 呼出側から所有権を移したスナップショット専用。実行中のdataには触れない。
static func save_owned_snapshot(candidate:Dictionary)->bool:
	last_error = ""
	if bool(candidate.get("migration_failed",false)):
		last_error = str(candidate.get("migration_error","移行を再試行してください。"))
		return false
	candidate.version = V2Rules.SAVE_VERSION
	Progression.migrate(candidate)
	candidate.settings = validate_settings(candidate.get("settings",{}))
	candidate.last_save = int(Time.get_unix_time_from_system())
	if not _valid_data(candidate):
		last_error = "保存候補の整合性を確認できません。"
		return false
	if FileAccess.file_exists(PATH) and not _valid_data(_read(PATH)):
		last_error = "既存セーブが破損しています。再読み込みで復旧してください。"
		return false
	if _fail("temp"):
		last_error = "一時ファイル作成に失敗しました。"
		return false
	var file := FileAccess.open(TEMP,FileAccess.WRITE)
	if file == null:
		last_error = "一時ファイルを開けません。"
		return false
	file.store_string(JSON.stringify(V2Measurement.json_value(candidate)))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK or not _valid_data(_read(TEMP)):
		last_error = "書き込んだ一時ファイルの検証に失敗しました。"
		return false
	var directory := DirAccess.open("user://")
	if directory == null:
		last_error = "保存先を開けません。"
		return false
	if directory.file_exists("save_v2.json"):
		if _fail("previous"):
			last_error = "直前セーブの保全に失敗しました。"
			return false
		if directory.file_exists("save_v2.previous.json") and directory.remove("save_v2.previous.json") != OK:
			last_error = "直前セーブを更新できません。"
			return false
		if directory.rename("save_v2.json","save_v2.previous.json") != OK:
			last_error = "現セーブを保全できません。"
			return false
	var error := ERR_CANT_CREATE if _fail("rename") else directory.rename("save_v2.tmp","save_v2.json")
	if error != OK:
		if not directory.file_exists("save_v2.json") and directory.file_exists("save_v2.previous.json"):
			_copy(PREVIOUS,PATH)
		last_error = "新セーブの確定に失敗しました。再試行できます。"
		return false
	return true
