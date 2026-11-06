extends SceneTree

func _initialize()->void:
	var source := OS.get_environment("SLT_SOURCE_SAVE")
	if OS.get_environment("SLT_TEST_DATA") != "1" or source.is_empty() or ProjectSettings.globalize_path(V2Save.PATH).replace("\\", "/") == source.replace("\\", "/"):
		quit(2)
		return
	var digest := FileAccess.get_sha256(source)
	var before:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var data := V2Save.load_data()
	var okay := not bool(data.get("migration_failed", false))
	for key in ["credits","lifetime_credits","profiles","previous_profiles","measurement_counts","armor","protection","names","deployed","front"]:
		okay = okay and data.get(key) == before.get(key)
	okay = okay and data.settings == V2Save.validate_settings(before.settings)
	okay = okay and Progression.valid(data.progression)
	var total := Progression.total(data)
	var counts:Dictionary = data.progression.achievements.duplicate(true)
	okay = okay and V2Save.save_data(data)
	var restored := V2Save.load_data()
	okay = okay and Progression.total(restored) == total and restored.progression.achievements == counts
	okay = okay and FileAccess.get_sha256(source) == digest
	if okay:
		print("MIGRATION_021_OK: real-save copy preserved credits/profile/armor/protection/settings and original hash; once-only progression, durable reload")
		quit(0)
	else:
		push_error("0.21 real-save copy migration failed; original was not written")
		quit(1)
