class_name V2Diorama
extends SubViewportContainer

## 戦闘と記録再現の事実を消費して描画する独立した3Dジオラマ。
## 進行、ダメージ、命中判定、保存は担当しない。

const MAX_ALLIES := 3
const MAX_ENEMIES := 12
const MAX_EFFECTS := 24
const MAX_SEEN_KEYS := 512

var world_view:SubViewport
var camera:Camera3D
var stage:Node3D
var effect_root:Node3D
var _models:Dictionary = {}
var _model_kinds:Dictionary = {}
var _replay_targets:Dictionary = {}
var _effects:Array[Dictionary] = []
var _seen:Dictionary = {}
var _seen_order:Array[String] = []
var _targets:Dictionary = {}
var _replay_model:V2SoldierModel
var _preview := false
var _active := false
var _clock := 0.0
var _recoil_until:Dictionary = {}
var _last_replay_time := -1.0
var _effects_enabled := true
var _externally_clocked := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Stretch keeps the rendered texture inside the parent Control's real layout bounds.
	stretch = true
	_build_viewport()
	set_process(false)
	resized.connect(_resize_viewport)

func _build_viewport() -> void:
	world_view = SubViewport.new()
	world_view.name = "DioramaViewport"
	world_view.own_world_3d = true
	world_view.transparent_bg = false
	world_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world_view.msaa_3d = Viewport.MSAA_2X
	add_child(world_view)
	stage = Node3D.new()
	stage.name = "DioramaWorld"
	world_view.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("91aeb0")
	sky_material.sky_horizon_color = Color("d2cfb5")
	sky_material.ground_bottom_color = Color("475659")
	sky_material.ground_horizon_color = Color("b7aa8e")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4c2ba")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -28, 0)
	key.light_color = Color("fff0d8")
	key.light_energy = 0.82
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 32.0
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.5, 5.0, -4.0)
	fill.light_color = Color("a8d8d2")
	fill.light_energy = 0.32
	fill.omni_range = 13.0
	stage.add_child(fill)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("535e58")
	ground_material.roughness = 0.98
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(28, 18)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = ground_mesh
	ground.material_override = ground_material
	ground.position = Vector3(0, -0.08, 0)
	stage.add_child(ground)
	_add_terrain()
	_add_distant_landmarks()
	effect_root = Node3D.new()
	effect_root.name = "TransientEffects"
	stage.add_child(effect_root)
	camera = Camera3D.new()
	camera.name = "FixedDioramaCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.4
	camera.position = Vector3(0, 5.05, -11.8)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.35, 0), Vector3.UP)
	_resize_viewport()

func _add_terrain() -> void:
	var terrain_mat := StandardMaterial3D.new()
	terrain_mat.albedo_color = Color("77745d")
	terrain_mat.roughness = 1.0
	var ridge_mesh := BoxMesh.new()
	ridge_mesh.size = Vector3(27, 0.55, 0.42)
	var ridge := MeshInstance3D.new()
	ridge.name = "LowEarthenRidge"
	ridge.mesh = ridge_mesh
	ridge.material_override = terrain_mat
	ridge.position = Vector3(0, -0.08, 3.4)
	ridge.rotation.z = -0.015
	stage.add_child(ridge)
	# 前景の低い土嚢列。兵士の脚より低く、姿を隠さない。
	var bag_mat := StandardMaterial3D.new()
	bag_mat.albedo_color = Color("9b8a68")
	bag_mat.roughness = 0.96
	for index in 8:
		var bag_mesh := SphereMesh.new()
		bag_mesh.radius = 0.36
		bag_mesh.height = 0.42
		var bag := MeshInstance3D.new()
		bag.mesh = bag_mesh
		bag.material_override = bag_mat
		bag.scale = Vector3(1.25, 0.68, 0.82)
		bag.position = Vector3(-5.2 + index * 1.48, 0.13, 1.75)
		stage.add_child(bag)

func _add_distant_landmarks() -> void:
	var ridge_mat := StandardMaterial3D.new()
	ridge_mat.albedo_color = Color("677978")
	ridge_mat.roughness = 1.0
	for index in 5:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 1.0
		var hill := MeshInstance3D.new()
		hill.mesh = mesh
		hill.material_override = ridge_mat
		hill.scale = Vector3(2.1 + (index % 2) * 0.6, 0.75 + (index % 3) * 0.16, 0.42)
		hill.position = Vector3(-8.0 + index * 4.0, 0.32, 5.5)
		stage.add_child(hill)
	# 遠景の壊れた遮蔽物と細い標識。
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color("6f7771")
	for index in 3:
		var wall := MeshInstance3D.new()
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(0.75, 0.48 + index % 2 * 0.25, 0.25)
		wall.mesh = wall_mesh
		wall.material_override = wall_mat
		wall.position = Vector3(-6.5 + index * 6.2, wall_mesh.size.y * 0.5, 4.7)
		stage.add_child(wall)

func _resize_viewport() -> void:
	# With stretch enabled SubViewportContainer owns its size and scales the viewport
	# to the actual layout rectangle. Setting SubViewport.size here would bypass the
	# parent bounds and let the scene spill beyond the allocated army/replay panel.
	pass

func set_active(active:bool) -> void:
	_active = active
	if world_view != null:
		world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)

func set_preview(weapon:int, armor:bool) -> void:
	_preview = true
	_externally_clocked = false
	_clock = 0.0
	_clear_effects()
	_last_replay_time = -1.0
	for id in _models.keys():
		var model:Node = _models[id]
		model.queue_free()
	_models.clear()
	_model_kinds.clear()
	var model := V2SoldierModel.new()
	model.name = "PreviewSoldier"
	model.configure(weapon, armor)
	model.position = Vector3(3.6, 0.0, 0.0)
	stage.add_child(model)
	_replay_model = model
	_models["preview"] = model
	_model_kinds["preview"] = "ally-%d-%s" % [weapon, str(armor)]
	model.set_pose("aim", 0.0, weapon)
	_targets.clear()

func show_state(state:Dictionary) -> void:
	_preview = false
	_externally_clocked = true
	var allies:Array = state.get("allies", [])
	var enemies:Array = state.get("enemies", [])
	var keep:Dictionary = {}
	var living_allies:Array = []
	for actor in allies:
		if bool(actor.get("alive", false)) and living_allies.size() < MAX_ALLIES:
			living_allies.append(actor)
	var living_enemies:Array = []
	for enemy in enemies:
		if bool(enemy.get("alive", false)) and living_enemies.size() < MAX_ENEMIES:
			living_enemies.append(enemy)
	for index in living_allies.size():
		var actor:Dictionary = living_allies[index]
		var id := str(actor.get("id", "ally-%d" % index))
		keep[id] = true
		var model := _get_model(id, int(actor.get("weapon", 0)), bool(actor.get("armor", false)), "")
		model.position = Vector3(4.2 - index * 1.5, 0.0, -0.36 + index * 0.48)
		model.visible = true
		var state_name := str(state.get("status", "idle"))
		var pose := "aim" if state_name == "fighting" else "walk" if state_name == "marching" else "retreat" if state_name == "retreat" else "idle"
		if float(actor.get("hp", 1.0)) < float(actor.get("max_hp", 1.0)) * 0.30:
			pose = "hit"
		var recoil_left := maxf(0.0, float(_recoil_until.get(id, 0.0)) - _clock)
		if recoil_left > 0.0:
			pose = "fire"
		model.set_pose(pose, _clock + index * 0.31, int(actor.get("weapon", 0)), recoil_left / 0.17)
	for index in living_enemies.size():
		var enemy:Dictionary = living_enemies[index]
		var id := str(enemy.get("id", "enemy-%d" % index))
		keep[id] = true
		var kind := str(enemy.get("kind", "light"))
		var model := _get_model(id, -1, false, kind)
		var side := index % 3
		var row := floori(float(index) / 3.0)
		model.position = Vector3(-2.15 - side * 0.82 - row * 0.18, 0.0, -0.72 + row * 0.78)
		model.visible = true
		model.set_pose("aim", _clock + index * 0.2, -1)
	for id in _models.keys():
		if not keep.has(id):
			var retired:V2SoldierModel = _models[id]
			if _effects_enabled:
				retired.set_pose("retreat", _clock)
				_push_effect(retired, 0.30, "retire")
			else:
				retired.queue_free()
			_models.erase(id)
			_model_kinds.erase(id)
	_targets.clear()
	for enemy in living_enemies:
		_targets[str(enemy.get("id", ""))] = enemy
	_clock = float(state.get("time", 0.0))
	if str(state.get("status", "")) == "marching":
		stage.position.x = sin(_clock * 0.65) * 0.20
	else:
		stage.position.x = 0.0

func consume(events:Array) -> void:
	if _preview or not _effects_enabled:
		return
	for raw in events:
		if not raw is Dictionary:
			continue
		var event:Dictionary = raw
		var type := str(event.get("type", ""))
		if type not in ["ally_shot", "enemy_shot", "hit", "march", "section", "complete", "retreat"]:
			continue
		if not _mark_event(event):
			continue
		if type in ["ally_shot", "enemy_shot"]:
			_clock = maxf(_clock, float(event.get("time", _clock)))
			_render_combat_shot(event, type == "enemy_shot")
		elif type == "hit":
			_render_hit(event)
		elif type in ["march", "section"]:
			_clock = maxf(_clock, float(event.get("time", _clock)))
		elif type == "retreat":
			for model in _models.values():
				if model is V2SoldierModel and str(model.enemy_kind).is_empty():
					model.set_pose("retreat", _clock)
	# 8fpsを下回る急なまとめ更新も一度に過大な演出を出さない。
	while _effects.size() > MAX_EFFECTS:
		_remove_effect(0)

func _mark_event(event:Dictionary) -> bool:
	var key := "%s|%.5f|%s|%s|%s|%s" % [str(event.get("type", "")), float(event.get("time", 0.0)), str(event.get("actor_id", "")), str(event.get("target_id", "")), str(event.get("weapon", "")), str(event.get("sequence", ""))]
	if _seen.has(key):
		return false
	_seen[key] = true
	_seen_order.append(key)
	if _seen_order.size() > MAX_SEEN_KEYS:
		_seen.erase(_seen_order.pop_front())
	return true

func _render_combat_shot(event:Dictionary, enemy_shot:bool) -> void:
	var actor_id := str(event.get("actor_id", ""))
	var target_id := str(event.get("target_id", ""))
	var actor:Node = _models.get(actor_id)
	var target:Node = _models.get(target_id)
	if not enemy_shot and actor is V2SoldierModel:
		_recoil_until[actor_id] = float(event.get("time", _clock)) + 0.17
		actor.set_pose("fire", float(event.get("time", _clock)), int(event.get("weapon", 0)), 1.0)
		var muzzle:Vector3 = actor.muzzle_global_position()
		_add_flash(muzzle, Color("ffdc86"), 0.11, 0.13)
		var end_point:Vector3 = target.global_position + Vector3(0.0, 1.55, -0.1) if target is Node3D and bool(event.get("hit", false)) else _miss_endpoint(muzzle, target, event)
		_add_beam(muzzle, end_point, bool(event.get("hit", false)), bool(event.get("critical", false)))
		if bool(event.get("hit", false)):
			_add_flash(end_point, Color("fff0bc") if bool(event.get("critical", false)) else Color("f4ad76"), 0.16 if bool(event.get("critical", false)) else 0.10, 0.20)
	elif enemy_shot and actor is Node3D:
		var muzzle:Vector3 = actor.global_position + Vector3(-0.35, 1.55, -0.05)
		var end_point:Vector3 = target.global_position + Vector3(0.0, 1.05, -0.05) if target is Node3D else muzzle + Vector3(-2.2, -0.2, 0.0)
		_add_beam(muzzle, end_point, true, false, true)
		_add_flash(end_point, Color("d7a690"), 0.09, 0.18)

func _render_hit(event:Dictionary) -> void:
	# ally_shot / enemy_shot が演出の唯一の発火源。hit は状態通知なので再描画しない。
	return

func _miss_endpoint(start:Vector3, target:Node, event:Dictionary) -> Vector3:
	if target is Node3D:
		var offset := Vector3(0.0, 0.0, -0.65) if int(float(event.get("time", 0.0)) * 10.0) % 2 == 0 else Vector3(0.0, -0.25, -0.4)
		return target.global_position + Vector3(0, 1.45, 0) + offset
	return start + Vector3(2.8, -0.15, 0.0)

func show_replay(record:Dictionary, time:float, targets:Dictionary, pose:Dictionary) -> void:
	_preview = true
	_externally_clocked = true
	if _last_replay_time >= 0.0 and time + 0.001 < _last_replay_time:
		_clear_effects()
	_last_replay_time = time
	_clock = time
	var weapon := clampi(int(record.get("weapon", 0)), 0, 2)
	if not _replay_model is V2SoldierModel:
		_clear_models()
		_replay_model = V2SoldierModel.new()
		_replay_model.name = "RecordedSoldier"
		_replay_model.configure(weapon, bool(record.get("armor", false)))
		_replay_model.position = Vector3(3.6, 0, 0)
		stage.add_child(_replay_model)
		_models["replay"] = _replay_model
		_model_kinds["replay"] = "ally-%d-%s" % [weapon, str(bool(record.get("armor", false)))]
	elif _model_kinds.get("replay", "") != ("ally-%d-%s" % [weapon, str(bool(record.get("armor", false))) ]):
		_clear_models()
		_replay_model = V2SoldierModel.new()
		_replay_model.configure(weapon, bool(record.get("armor", false)))
		_replay_model.position = Vector3(3.6, 0, 0)
		stage.add_child(_replay_model)
		_models["replay"] = _replay_model
		_model_kinds["replay"] = "ally-%d-%s" % [weapon, str(bool(record.get("armor", false)))]
	_replay_model.set_pose("aim", time, weapon)
	if pose.has("rotation") and pose.rotation is Array and pose.rotation.size() >= 2:
		_replay_model.rotation.y = PI * 0.5 + clampf(float(pose.rotation[1]), -0.45, 0.45)
	var keep:Dictionary = {"replay":true}
	for id in _replay_targets.keys():
		if not targets.has(id):
			_replay_targets[id].queue_free()
			_replay_targets.erase(id)
	for id in targets.keys():
		if _replay_targets.size() >= MAX_ENEMIES and not _replay_targets.has(str(id)):
			break
		var state:Variant = targets[id]
		if not state is Dictionary:
			continue
		var point:Array = state.get("position", [])
		if point.size() < 3:
			continue
		var model := _get_replay_target(str(id))
		var world_position := _project_replay_point(point, pose.get("origin", []))
		model.position = world_position
		model.visible = true
		var radius := clampf(float(state.get("radius", 0.32)), 0.12, 0.42)
		model.scale = Vector3.ONE * radius * 2.0
		keep[str(id)] = true
	for id in _replay_targets.keys():
		if not keep.has(str(id)):
			_replay_targets[id].queue_free()
			_replay_targets.erase(id)
	for id in _models.keys():
		if not keep.has(str(id)):
			_models[id].queue_free()
			_models.erase(id)
			_model_kinds.erase(id)

func _get_replay_target(id:String) -> Node3D:
	if _replay_targets.has(id):
		return _replay_targets[id] as Node3D
	var root := Node3D.new()
	root.name = "RecordedTarget_%s" % id
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.5
	sphere_mesh.height = 1.0
	var sphere := MeshInstance3D.new()
	sphere.mesh = sphere_mesh
	var sphere_material := StandardMaterial3D.new()
	sphere_material.albedo_color = Color("dda95c")
	sphere_material.roughness = 0.58
	sphere.material_override = sphere_material
	root.add_child(sphere)
	var center_material := StandardMaterial3D.new()
	center_material.albedo_color = Color("fbefd0")
	center_material.emission_enabled = true
	center_material.emission = Color("c8a461")
	center_material.emission_energy_multiplier = 0.25
	for dimensions in [Vector3(0.50, 0.045, 0.045), Vector3(0.045, 0.50, 0.045)]:
		var mark := MeshInstance3D.new()
		var mark_mesh := BoxMesh.new()
		mark_mesh.size = dimensions
		mark.mesh = mark_mesh
		mark.material_override = center_material
		mark.position.z = -0.49
		root.add_child(mark)
	stage.add_child(root)
	_replay_targets[id] = root
	return root

func _project_replay_point(point:Array, origin:Array) -> Vector3:
	var ox := float(origin[0]) if origin.size() > 0 else 0.0
	var oy := float(origin[1]) if origin.size() > 1 else 0.0
	var oz := float(origin[2]) if origin.size() > 2 else 0.0
	# 射場の奥行き(-Z)を側面ジオラマの横軸へ、垂直偏差を高さへ写す。
	var dx := float(point[0]) - ox
	var dy := float(point[1]) - oy
	var dz := float(point[2]) - oz
	return Vector3(clampf(-1.35 + dz * 0.18, -5.0, 0.25), clampf(1.60 + dy * 0.20, 0.65, 3.25), clampf(dx * 0.09, -0.65, 0.65))

func consume_replay(events:Array) -> void:
	if not _effects_enabled:
		return
	for raw in events:
		if not raw is Dictionary:
			continue
		var event:Dictionary = raw
		if str(event.get("type", "")) != "shot" or not _mark_event(event):
			continue
		var origin:Array = event.get("origin", [])
		var end:Array = event.get("end", [])
		if origin.size() < 3 or end.size() < 3:
			continue
		var start_point := _project_replay_point(origin, origin)
		start_point.x = 2.9
		start_point.y = 1.75
		var end_point := _project_replay_point(end, origin)
		var hit := bool(event.get("hit", event.get("q", 0.0) > 0.0))
		var q := clampf(float(event.get("q", 0.0)), 0.0, 1.0)
		_recoil_until["replay"] = _clock + 0.17
		if is_instance_valid(_replay_model):
			_replay_model.set_pose("fire", _clock, _replay_model.weapon_id, 1.0)
		_add_flash(start_point, Color("ffdc86"), 0.10, 0.12)
		_add_beam(start_point, end_point, hit, false, false, q)
		# 再現データにあるhitとendだけを使用。乱数やクリティカルを追加しない。
		if hit:
			_add_flash(end_point, Color("e6d0a2"), 0.075 + q * 0.06, 0.16)

func _get_model(id:String, weapon:int, armor:bool, enemy:String) -> V2SoldierModel:
	var kind := "enemy-%s" % enemy if not enemy.is_empty() else "ally-%d-%s" % [clampi(weapon, 0, 2), str(armor)]
	if _models.has(id) and _model_kinds.get(id, "") == kind:
		return _models[id] as V2SoldierModel
	if _models.has(id):
		_models[id].queue_free()
	var model := V2SoldierModel.new()
	model.name = "Soldier_%s" % id
	model.configure(weapon, armor, enemy)
	stage.add_child(model)
	_models[id] = model
	_model_kinds[id] = kind
	return model

func _add_flash(position:Vector3, color:Color, radius:float, duration:float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var effect := MeshInstance3D.new()
	effect.mesh = mesh
	effect.material_override = material
	effect.scale = Vector3.ONE * radius
	effect.position = position
	effect_root.add_child(effect)
	_push_effect(effect, duration, "flash")

func _add_beam(start:Vector3, finish:Vector3, hit:bool, critical:bool, enemy:bool = false, q:float = 0.0) -> void:
	var delta := finish - start
	if delta.length_squared() < 0.0001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.009 if not critical else 0.017
	mesh.bottom_radius = 0.016 if not critical else 0.026
	mesh.height = delta.length()
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.position = (start + finish) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, delta.normalized())
	var material := StandardMaterial3D.new()
	var color := Color("f0bf68") if enemy else Color("e9f0cb") if hit else Color("c6c8b4")
	if critical:
		color = Color("fff0a3")
	if q > 0.0:
		color = color.lerp(Color("fff4ca"), q * 0.42)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.7 if critical else 0.35
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = material
	effect_root.add_child(beam)
	_push_effect(beam, 0.10 if not critical else 0.15, "beam")

func _push_effect(node:Node3D, duration:float, kind:String) -> void:
	_effects.append({"node":node, "left":duration, "duration":duration, "kind":kind})
	while _effects.size() > MAX_EFFECTS:
		_remove_effect(0)

func _remove_effect(index:int) -> void:
	if index < 0 or index >= _effects.size():
		return
	var data:Dictionary = _effects[index]
	var node:Node = data.get("node")
	if is_instance_valid(node):
		node.queue_free()
	_effects.remove_at(index)

func _clear_effects() -> void:
	for index in range(_effects.size() - 1, -1, -1):
		_remove_effect(index)
	_seen.clear()
	_seen_order.clear()
	_recoil_until.clear()

func reset_timeline()->void:
	_clear_effects()
	_clock = 0.0
	_last_replay_time = -1.0

func set_effects_enabled(enabled:bool)->void:
	if _effects_enabled == enabled:
		return
	_effects_enabled = enabled
	if not enabled:
		_clear_effects()

func _clear_models() -> void:
	for node in _models.values():
		if is_instance_valid(node):
			node.queue_free()
	_models.clear()
	_model_kinds.clear()
	for node in _replay_targets.values():
		if is_instance_valid(node):
			node.queue_free()
	_replay_targets.clear()
	_replay_model = null

func _process(delta:float) -> void:
	if not _active:
		return
	if not _externally_clocked:
		_clock += minf(delta, 0.1)
	for index in range(_effects.size() - 1, -1, -1):
		var effect:Dictionary = _effects[index]
		effect.left = float(effect.left) - delta
		var node:Node3D = effect.node
		if not is_instance_valid(node) or float(effect.left) <= 0.0:
			_remove_effect(index)
			continue
		if str(effect.kind) == "flash":
			var fraction := clampf(float(effect.left) / float(effect.duration), 0.0, 1.0)
			node.scale *= Vector3.ONE + Vector3.ONE * delta * (0.8 if fraction > 0.65 else -2.0)
		elif str(effect.kind) == "retire":
			node.position.y -= delta * 0.8
			node.rotation.z += delta * 1.2
	if _models.has("preview") and _models["preview"] is V2SoldierModel:
		var preview_model:V2SoldierModel = _models["preview"]
		preview_model.set_pose("aim", _clock, preview_model.weapon_id, maxf(0.0, float(_recoil_until.get("preview", 0.0)) - _clock) / 0.17)
	if _replay_model is V2SoldierModel and _models.has("replay"):
		var recoil_left := maxf(0.0, float(_recoil_until.get("replay", 0.0)) - _clock)
		_replay_model.set_pose("fire" if recoil_left > 0.0 else "aim", _clock, _replay_model.weapon_id, recoil_left / 0.17)
