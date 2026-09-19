extends SceneTree

var failures:Array[String]=[]

func check(condition:bool,message:String)->void:
	if not condition: failures.append(message)

func inside(inner:Rect2,outer:Rect2)->bool:
	return inner.position.x>=outer.position.x-1 and inner.position.y>=outer.position.y-1 and inner.end.x<=outer.end.x+1 and inner.end.y<=outer.end.y+1

func _init()->void:
	call_deferred("_run")

func _run()->void:
	var scene:PackedScene=load("res://main.tscn")
	var main=scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size=dimensions
		await process_frame
		await process_frame
		main._start_training()
		main._open_pause()
		await process_frame
		var viewport_rect:=Rect2(Vector2.ZERO,Vector2(dimensions))
		check(inside(main.pause_card.get_global_rect(),viewport_rect),"pause card outside %s"%dimensions)
		check(main.pause_card.get_global_rect().position.y>=20,"pause margin missing %s"%dimensions)
		main._close_pause()
		main.result_panel.show(); await process_frame; check(inside(main.result_card.get_global_rect(),viewport_rect),"result card outside %s"%dimensions); main.result_panel.hide()
		check(main.crosshair.size.round()==main.hud.size.round(),"crosshair not HUD-sized %s"%dimensions)
		check((main.crosshair.get_global_rect().get_center()-main.hud.get_global_rect().get_center()).length()<1.0,"crosshair center mismatch %s"%dimensions)
		main._show_prep()
	main._start_training()
	main.mode=main.Mode.TRAINING
	var paused_time:float=main.time_left
	var hp_before:float=float(main.data.enemy_hp)
	main._show_army()
	await process_frame
	await process_frame
	check(is_equal_approx(main.time_left,paused_time),"training timer advanced on army screen")
	check(float(main.data.enemy_hp)<hp_before,"battle did not continue on army screen")
	main._leave_army()
	check(main.mode==main.Mode.TRAINING,"training state did not restore")
	check(main.mouse_blocked,"return input was not blocked")
	var esc:=InputEventKey.new(); esc.physical_keycode=KEY_ESCAPE; esc.pressed=true
	main._unhandled_input(esc); check(main.mode==main.Mode.PAUSED,"Esc did not open pause once")
	var echo:=InputEventKey.new(); echo.physical_keycode=KEY_ESCAPE; echo.pressed=true; echo.echo=true
	main._unhandled_input(echo); check(main.mode==main.Mode.PAUSED,"Esc key repeat toggled pause")
	var release:=InputEventKey.new(); release.physical_keycode=KEY_ESCAPE; release.pressed=false; main._unhandled_input(release)
	main._unhandled_input(esc); check(main.mode==main.Mode.TRAINING,"second Esc press did not close pause")
	main._on_focus_lost(); check(main.mode==main.Mode.PAUSED and main.mouse_blocked,"focus loss did not pause and clear input")
	var focus_time:float=main.time_left; await process_frame; await process_frame; check(is_equal_approx(main.time_left,focus_time),"timer advanced after focus loss")
	check(main.battle_view.visible_soldiers(999)==main.battle_view.MAX_ALLIES,"soldier display cap")
	check(Balance.visual_tier(0)==0 and Balance.visual_tier(2)==1 and Balance.visual_tier(5)==2,"visual tiers")
	var valid:Dictionary=SaveManager.defaults().settings.duplicate(true); valid.crosshair_color="000000"; SaveManager._sanitize_settings(valid); check(valid.crosshair_color=="000000","valid black setting overwritten")
	var invalid:Dictionary=SaveManager.defaults().settings.duplicate(true); invalid.crosshair_color="not-a-color"; invalid.crosshair_size=-10; SaveManager._sanitize_settings(invalid); check(invalid.crosshair_color=="66e8ff" and float(invalid.crosshair_size)==4.0,"invalid crosshair fallback")
	main.crosshair.set_appearance("000000",10); check(main.crosshair.line_color==Color("000000"),"black crosshair setting not applied")
	if failures.is_empty():
		print("UI_TEST_OK: layouts, transitions, battle continuity, crosshair settings, visual tiers")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
