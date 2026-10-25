extends SceneTree

const CAPTURE_PATH := "../../outputs/v2-art-preview.png"
var failures:Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var diorama := V2Diorama.new()
	diorama.custom_minimum_size = Vector2(430, 240)
	root.add_child(diorama)
	await process_frame
	await process_frame
	_check(diorama.world_view != null and diorama.world_view.own_world_3d, "viewport owns an isolated world")
	_check(diorama.mouse_filter == Control.MOUSE_FILTER_IGNORE, "diorama does not consume input")
	diorama.size = Vector2(430, 240)
	diorama._resize_viewport()
	_check(diorama.world_view.size == Vector2i(430, 240), "minimum viewport size is supported")
	for weapon in range(3):
		var soldier := V2SoldierModel.new()
		soldier.configure(weapon, weapon == 1)
		root.add_child(soldier)
		await process_frame
		_check(soldier.get_child_count() > 0, "weapon %d produces an articulated model" % weapon)
		_check(soldier._armor_mesh.visible == (weapon == 1), "armor state is visible for weapon %d" % weapon)
		var initial := soldier._left_leg.rotation.x
		soldier.set_pose("walk", 0.31, weapon)
		_check(soldier._left_leg.rotation.x != initial, "walk pose animates legs for weapon %d" % weapon)
		soldier.queue_free()
	diorama.set_preview(2, true)
	diorama.set_active(true)
	var battle_state := {"status":"fighting", "time":0.0, "allies":[
		{"id":"ally-0", "weapon":0, "armor":true, "alive":true, "hp":100, "max_hp":100},
		{"id":"ally-1", "weapon":1, "armor":false, "alive":true, "hp":100, "max_hp":100},
		{"id":"ally-2", "weapon":2, "armor":true, "alive":true, "hp":100, "max_hp":100}], "enemies":[
		{"id":"enemy-0-0", "kind":"light", "alive":true, "hp":10, "max_hp":10},
		{"id":"enemy-0-1", "kind":"heavy", "alive":true, "hp":50, "max_hp":50}]}
	diorama.show_state(battle_state)
	await process_frame
	var shot := {"type":"ally_shot", "time":0.1, "actor_id":"ally-0", "target_id":"enemy-0-0", "weapon":0, "hit":true, "critical":false}
	diorama.consume([shot])
	var first_effect_count := diorama._effects.size()
	diorama.consume([shot.duplicate(true)])
	_check(diorama._effects.size() == first_effect_count, "repeated event does not duplicate effects")
	var many:Array = []
	for index in 14:
		many.append({"type":"ally_shot", "time":0.2 + index * 0.011, "actor_id":"ally-0", "target_id":"enemy-0-0", "weapon":0, "hit":index % 2 == 0, "critical":index % 5 == 0})
	diorama.consume(many)
	_check(diorama._effects.size() <= V2Diorama.MAX_EFFECTS, "combat effects remain bounded")
	diorama.set_active(false)
	_check(diorama.world_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "inactive viewport rendering is disabled")
	_check(not diorama.is_processing(), "inactive animation processing is stopped")
	diorama.set_active(true)
	diorama.set_preview(2, true)
	diorama.show_replay({"record_id":"art-test", "weapon":2, "armor":true}, 1.0, {"target-A":{"position":[0.0, 0.0, -4.0], "radius":0.35}}, {"origin":[0.0, 1.0, 0.0], "rotation":[0.0, 0.0, 0.0]})
	var target_node:Node3D = diorama._replay_targets.get("target-A")
	var target_instance_id := target_node.get_instance_id()
	_check(target_node.get_child_count() == 3, "recorded target is a sphere with a center mark")
	diorama.show_replay({"record_id":"art-test", "weapon":2, "armor":true}, 1.05, {"target-A":{"position":[0.0, 0.0, -4.1], "radius":0.35}}, {"origin":[0.0, 1.0, 0.0], "rotation":[0.0, 0.0, 0.0]})
	_check(diorama._replay_targets["target-A"].get_instance_id() == target_instance_id, "recorded target model is reused across frames")
	var replay_shot := {"type":"shot", "time":1.1, "sequence":1, "hit":true, "q":0.9, "origin":[0.0, 1.0, 0.0], "direction":[0.0, 0.0, -1.0], "end":[0.0, 1.0, -4.0]}
	diorama.consume_replay([replay_shot])
	var replay_effects := diorama._effects.size()
	diorama.consume_replay([replay_shot.duplicate(true)])
	_check(diorama._effects.size() == replay_effects, "recorded shot is rendered once")
	diorama.show_replay({"record_id":"art-test", "weapon":2, "armor":true}, 0.5, {}, {})
	diorama.consume_replay([replay_shot])
	_check(diorama._effects.size() > 0, "restarting replay clears old event keys")
	diorama.show_state(battle_state)
	diorama.consume([{"type":"ally_shot", "time":0.3, "actor_id":"ally-0", "target_id":"enemy-0-0", "weapon":0, "hit":true, "critical":true}])
	diorama.size = Vector2(1280, 720)
	diorama._resize_viewport()
	_check(diorama.world_view.size == Vector2i(1280, 720), "720p viewport size is supported")
	await process_frame
	await process_frame
	_capture(diorama)
	diorama.size = Vector2(1920, 1080)
	diorama._resize_viewport()
	_check(diorama.world_view.size == Vector2i(1920, 1080), "1080p viewport size is supported")
	await process_frame
	await process_frame
	if failures.is_empty():
		print("V2 art tests: PASS")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _capture(diorama:V2Diorama) -> void:
	var texture := diorama.world_view.get_texture()
	if OS.get_environment("SLT_SKIP_CAPTURE").is_empty() and texture != null:
		var image := texture.get_image()
		if image != null and not image.is_empty():
			var capture_path := OS.get_environment("SLT_CAPTURE_OUTPUT")
			if capture_path.is_empty():
				capture_path = ProjectSettings.globalize_path("res://" + CAPTURE_PATH)
			DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
			var save_error := image.save_png(capture_path)
			print("V2 art capture: %s (error=%d)" % [capture_path, save_error])
		_check(image != null and not image.is_empty(), "3D viewport rendered an image")

func _check(condition:bool, message:String) -> void:
	if not condition:
		failures.append(message)
