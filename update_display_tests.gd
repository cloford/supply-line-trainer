extends SceneTree
var failures:Array[String]=[]
func _init()->void:call_deferred("_run")
func _run()->void:
	var game=load("res://main.tscn").instantiate();game.is_test_mode=true;root.add_child(game);game.set_process(false)
	var updater:=SupplyLineUpdater.new();game.add_child(updater);game.updater=updater
	updater.status_changed.connect(game._update_status)
	updater._auto_download=false;updater._phase="check"
	if "--live" in OS.get_cmdline_user_args():
		updater._request.request(SupplyLineUpdater.RELEASE_API,["Accept: application/vnd.github+json","User-Agent: SupplyLineTrainer-Test"])
		var deadline:=Time.get_ticks_msec()+25000
		while not updater._phase.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	else:
		updater._completed(HTTPRequest.RESULT_SUCCESS,200,[],JSON.stringify({"tag_name":"v"+SupplyLineUpdater.current_version(),"draft":false,"prerelease":false,"assets":[]}).to_utf8_buffer())
	var expected:=SupplyLineUpdater.running_version_text()+"　最新公開版 v"+SupplyLineUpdater.current_version()+" と同じです"
	for label in game.update_labels:
		if label.text!=expected:failures.append("version status mismatch: "+label.text)
	for button in game.update_buttons:
		if not button.disabled:failures.append("same version enabled apply")
	var output:=OS.get_environment("SLT_CAPTURE_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;root.content_scale_size=dimensions
		for settings in [false,true]:
			game._show_prep()
			if settings:game._open_settings_from_screen();game._select_settings_tab(3)
			await process_frame;await process_frame
			var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
			for label in game.update_labels:
				if label.is_visible_in_tree() and not bounds.encloses(label.get_global_rect()):failures.append("version label outside window")
			if not output.is_empty():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(("settings" if settings else "preparation")+"-%dx%d.png"%[dimensions.x,dimensions.y]))
	game.queue_free();for frame in 5:await process_frame
	if failures.is_empty():print("UPDATE_DISPLAY_OK: ",expected,"; 2 resolutions, preparation/settings, apply disabled");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
