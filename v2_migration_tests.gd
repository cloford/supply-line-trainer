extends SceneTree

func _initialize()->void:
	var source := OS.get_environment("SLT_SOURCE_SAVE")
	if OS.get_environment("SLT_TEST_DATA") != "1" or source.is_empty() or ProjectSettings.globalize_path(V2Save.LEGACY).replace("\\", "/") == source.replace("\\", "/"):
		push_error("read-only source and isolated APPDATA required")
		quit(1)
		return
	var hash_before := FileAccess.get_sha256(source)
	var original:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var data := V2Save.load_data()
	var okay := not bool(data.get("migration_failed", false))
	okay = okay and data.credits == "0" and data.lifetime_credits == "0" and int(data.front) == 0
	okay = okay and int(data.practice_totals.sessions) == 0 and data.training_history.is_empty() and data.active_training.is_empty()
	okay = okay and data.profiles == [{}, {}, {}] and data.measurement_counts == [0, 0, 0]
	okay = okay and data.settings == V2Save.validate_settings(original.settings)
	okay = okay and FileAccess.get_sha256(str(data.legacy_backup)) == hash_before
	data.credits = "37"
	data.names[0] = "再起動確認"
	okay = okay and V2Save.save_data(data)
	var reloaded := V2Save.load_data()
	okay = okay and reloaded.credits == "37" and reloaded.names[0] == "再起動確認"
	okay = okay and FileAccess.get_sha256(source) == hash_before and FileAccess.get_sha256(V2Save.LEGACY) == hash_before
	if okay:
		print("V2_REAL_COPY_MIGRATION_OK: settings allowlist only, no old progress/history, once, durable, source+legacy hashes unchanged")
		quit(0)
	else:
		push_error("v2 real-copy migration invariant failed")
		quit(1)
