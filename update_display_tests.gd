extends SceneTree
var failures:Array[String]=[]
func _init()->void:call_deferred("_run")
func _run()->void:
	if "--boot-flow" in OS.get_cmdline_user_args():
		await _boot_flow()
		return
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
			for choice in game.weapon_buttons:
				if choice.is_visible_in_tree():failures.append("weapon selector exposed on non-training page")
			if game.difficulty_row.is_visible_in_tree():failures.append("legacy difficulty exposed on non-training page")
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

func _boot_problem(message:String)->void:
	if not message in failures:failures.append(message)

func _boot_flow()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1" or DisplayServer.get_name()=="headless":quit(2);return
	var output:=OS.get_environment("SLT_CAPTURE_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	var summaries:Array=[]
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size=dimensions;root.content_scale_size=dimensions
		if dimensions.x!=1280:
			var fixture:=V2Save.load_data()
			Progression.apply_record(fixture,{"weapon":0,"progress_kills":1500})
			for item in Progression.pending_notifications(fixture):Progression.mark_seen(fixture,item.id)
			fixture.selected_weapon=1 if dimensions.x==1920 else 2;fixture.selected_measurement=true
			fixture.intro_seen=true;fixture.guidance_credited=true
			fixture.credits="321";fixture.lifetime_credits="999"
			fixture.settings.fov=95.0
			if not V2Save.save_data(fixture):_boot_problem("existing boot fixture save failed")
		var game=load("res://main.tscn").instantiate()
		game.is_test_mode=false
		root.add_child(game)
		# Keep OS focus under test control; real OS focus loss is exercised separately.
		game.get_viewport().focus_exited.disconnect(game._on_focus_lost)
		game.app_focused=true
		var camera_pose:Transform3D=game.camera.global_transform
		var target_pose:Vector3=game.targets[0].global_position
		var fov:float=game.camera.fov
		var progress_before:int=Progression.total(game.data)
		var guidance_sent:=false
		var miss_sent:=false
		var transitions:Array=[]
		var phase_previous:=""
		var started:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-started<12000:
			await RenderingServer.frame_post_draw
			if game.prep_panel.is_visible_in_tree():_boot_problem("preparation appeared during normal boot")
			if not game.targets[0].is_visible_in_tree():_boot_problem("boot target hidden")
			if not game.crosshair.is_visible_in_tree():_boot_problem("boot crosshair hidden")
			if game.camera.global_transform!=camera_pose or game.targets[0].global_position!=target_pose or game.camera.fov!=fov:_boot_problem("boot camera/target/FOV jumped")
			var phase:String=("guide" if game.iris_intro.waiting else "iris") if game.intro_session else (str(game.countdown_display.number_label.text) if game.countdown_display.is_visible_in_tree() else "training")
			if phase!=phase_previous:
				transitions.append({"phase":phase,"ms":Time.get_ticks_msec()-started})
				phase_previous=phase
				if not output.is_empty():root.get_texture().get_image().save_png(output.path_join("normal-boot-%s-%dx%d.png"%[phase,dimensions.x,dimensions.y]))
			if game.mode==game.Mode.COUNTDOWN and (game.training_elapsed!=0.0 or game.stats.shots!=0 or game.stats.hits!=0):_boot_problem("presentation changed training facts")
			if game.iris_intro.waiting and not miss_sent and Time.get_ticks_msec()-started>250:
				var previous_rotation:Vector3=game.player.rotation
				game.player.rotation.y+=0.8
				_boot_mouse_click()
				await process_frame
				game.player.rotation=previous_rotation
				miss_sent=true
				if not game.iris_intro.waiting:_boot_problem("miss advanced guidance")
			if game.iris_intro.waiting and not guidance_sent and Time.get_ticks_msec()-started>500:
				_boot_mouse_click()
				guidance_sent=true
			if game.mode==game.Mode.TRAINING:break
		game.set_process(false)
		var sequence:Array=[]
		for transition in transitions:sequence.append(transition.phase)
		if sequence!=["guide","iris","3","2","1","training"]:_boot_problem("normal boot phase order: "+str(sequence))
		if transitions.size()==6:
			for index in range(2,5):
				var duration:int=int(transitions[index+1].ms)-int(transitions[index].ms)
				if duration<800 or duration>1400:_boot_problem("countdown not about one second: "+str(duration))
		var expected_weapon:int=0 if dimensions.x==1280 else (1 if dimensions.x==1920 else 2)
		if game.training_weapon!=expected_weapon or game.training_measurement or game.stats.shots!=0 or game.training_elapsed>0.15:_boot_problem("normal boot did not enter last unlocked free practice")
		if Progression.total(game.data)!=progress_before+(1 if dimensions.x==1280 else 0):_boot_problem("guidance progression was lost or granted again")
		if game.spawn_audio.play_count!=1:_boot_problem("normal boot pop was not exactly once")
		if dimensions.x!=1280:
			if not Progression.unlocked(game.data,4) or game.data.credits!="321" or game.data.settings.fov!=95.0:_boot_problem("existing boot state was reset")
			if not game.progression_view._notification_queue.is_empty() or not game.progression_view._active_notification.is_empty():_boot_problem("old achievement notified again")
		summaries.append({"size":str(dimensions),"transitions":transitions,"pop_count":game.spawn_audio.play_count,"weapon":game.training_weapon,"measurement":game.training_measurement})
		game.tab_held=true
		game._open_tab()
		await process_frame
		if not game.tab_panel.is_visible_in_tree():_boot_problem("Tab panel missing")
		for weapon in game.tab_weapons.size():
			if game.tab_weapons[weapon].button_pressed!=(weapon==game.training_weapon):_boot_problem("current weapon selection not represented")
		_boot_bounds(game.tab_panel,dimensions)
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("tab-%dx%d.png"%[dimensions.x,dimensions.y]))
		game._open_target_editor()
		for risk in [0.0,0.5,1.0]:
			game.target_slider.value=risk
			await process_frame
			if not game.target_editor.is_visible_in_tree():_boot_problem("target editor missing")
			_boot_bounds(game.target_editor,dimensions)
			if not output.is_empty():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("target-%s-%dx%d.png"%[str(risk),dimensions.x,dimensions.y]))
		game._cancel_target_edit()
		game.tab_held=false
		game._close_tab()
		await game._finish_training(false)
		game.queue_free()
		for frame in 5:await process_frame
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("normal-boot-timings.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(summaries,"  "))
	if failures.is_empty():print("NORMAL_BOOT_GPU_OK: ",JSON.stringify(summaries));quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)

func _boot_mouse_click()->void:
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.position=root.get_visible_rect().get_center()
	click.pressed=true
	Input.parse_input_event(click)
	click=click.duplicate()
	click.pressed=false
	Input.parse_input_event(click)

func _boot_bounds(panel:Control,dimensions:Vector2i)->void:
	var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
	for control in panel.find_children("*","Control",true,false):
		if control.is_visible_in_tree() and (control is Button or control is HSlider):
			if not bounds.encloses(control.get_global_rect()):_boot_problem("interactive control outside viewport: "+str(control.name))
