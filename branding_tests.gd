extends SceneTree

func _init()->void:
	_run.call_deferred()

func _run()->void:
	assert(OS.get_environment("SLT_TEST_DATA")=="1")
	assert(ProjectSettings.get_setting("application/config/name")=="Aim Runner")
	assert(SupplyLineUpdater.current_version()=="0.22")
	var expected:=OS.get_environment("APPDATA").replace("\\","/").path_join("Godot/app_userdata/Supply Line Trainer")
	assert(OS.get_user_data_dir().replace("\\","/")==expected,"Name change must retain exact Windows save directory")
	var game=load("res://main.tscn").instantiate()
	game.is_test_mode=true
	root.add_child(game)
	game.set_process(false)
	await process_frame
	assert(_contains_label(game,"AIM RUNNER  /  0.22"))
	game._open_settings_from_screen()
	await process_frame
	assert(_contains_label(game,"Aim Runner — 実行中 v0.22"))
	assert(game.feedback_url.ends_with("/discussions/14"))
	game.queue_free()
	await process_frame
	print("BRANDING_OK: Aim Runner 0.22, preparation/settings, unchanged exact Windows user directory, Discussion 14")
	quit(0)

func _contains_label(node:Node,text:String)->bool:
	if node is Label and node.text==text:return true
	for child in node.get_children():
		if _contains_label(child,text):return true
	return false
