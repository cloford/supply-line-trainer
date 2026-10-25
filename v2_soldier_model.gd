class_name V2SoldierModel
extends Node3D

## 商用利用できるオリジナル形状を Godot の基本メッシュだけで構成した兵士。
## 射撃の判定や状態更新は持たず、渡されたポーズを見た目へ反映する。

const COLORS := {
	"ally": Color("287f79"), "ally_dark": Color("164e53"), "ally_light": Color("62b5a3"),
	"skin": Color("dca982"), "skin_shadow": Color("a96e50"), "metal": Color("35424a"),
	"metal_light": Color("839394"), "strap": Color("b17c42"), "enemy": Color("bd633a"),
	"enemy_dark": Color("713b31"), "enemy_light": Color("e79a57"), "enemy_armor": Color("665558"),
	"visor": Color("344047"), "eye": Color("302b2a")
}

var weapon_id := 0
var armor_enabled := false
var enemy_kind := ""
var pose_name := "idle"
var pose_time := 0.0
var recoil := 0.0
var _root: Node3D
var _head: Node3D
var _torso: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _weapon: Node3D
var _muzzle: Marker3D
var _armor_mesh: MeshInstance3D

func _ready() -> void:
	_build()

func configure(weapon:int, armor:bool, enemy:String = "") -> void:
	weapon_id = clampi(weapon, 0, 2)
	armor_enabled = armor
	enemy_kind = enemy
	if is_inside_tree():
		_build()

func _material(color:Color, metallic:float = 0.0, roughness:float = 0.76) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

func _mesh(parent:Node3D, mesh:PrimitiveMesh, color:Color, position:Vector3, scale:Vector3 = Vector3.ONE, material:Material = null, rotation:Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = position
	item.scale = scale
	item.rotation = rotation
	item.material_override = material if material != null else _material(color)
	parent.add_child(item)
	return item

func _sphere(parent:Node3D, color:Color, position:Vector3, scale:Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	return _mesh(parent, mesh, color, position, scale)

func _capsule(parent:Node3D, color:Color, a:Vector3, b:Vector3, radius:float) -> MeshInstance3D:
	var length := a.distance_to(b)
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(length + radius * 2.0, radius * 2.1)
	var item := _mesh(parent, mesh, color, (a + b) * 0.5)
	var direction := (b - a).normalized()
	item.quaternion = Quaternion(Vector3.UP, direction)
	return item

func _box(parent:Node3D, color:Color, position:Vector3, dimensions:Vector3, bevel_color:Color = Color.TRANSPARENT) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var item := _mesh(parent, mesh, color, position)
	if bevel_color != Color.TRANSPARENT:
		var trim_mesh := BoxMesh.new()
		trim_mesh.size = Vector3(dimensions.x * 1.04, 0.045, dimensions.z * 1.05)
		var trim := _mesh(parent, trim_mesh, bevel_color, position + Vector3(0, dimensions.y * 0.25, 0))
		trim.rotation = item.rotation
	return item

func _pivot(parent:Node3D, name:String, at:Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = name
	pivot.position = at
	parent.add_child(pivot)
	return pivot

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_root = Node3D.new()
	_root.name = "ArticulatedSoldier"
	add_child(_root)
	var ally := enemy_kind.is_empty()
	var primary:Color = COLORS.ally if ally else COLORS.enemy
	var dark:Color = COLORS.ally_dark if ally else COLORS.enemy_dark
	var light:Color = COLORS.ally_light if ally else COLORS.enemy_light
	var skin:Color = COLORS.skin
	var helmet := _material(dark, 0.08, 0.66)
	var cloth := _material(primary, 0.0, 0.92)
	var vest := _material(COLORS.ally_dark if ally else COLORS.enemy_armor, 0.0, 0.84)
	var gun := _material(COLORS.metal, 0.42, 0.45)
	var trim := _material(light, 0.12, 0.62)
	var foot := _material(Color("303b3d"), 0.04, 0.82)

	# 頭を大きく、胴を短くして3〜4頭身の輪郭を作る。
	var body_width := 0.84 if enemy_kind == "heavy" else 0.72
	var torso_height := 0.95 if enemy_kind == "heavy" else 0.88
	var shoulder_y := 1.82 if enemy_kind == "heavy" else 1.72
	_torso = _pivot(_root, "Torso", Vector3(0, shoulder_y, 0))
	_mesh(_torso, CapsuleMesh.new(), primary, Vector3(0, -0.34, 0), Vector3(body_width, torso_height, 0.44), cloth)
	# 腰帯と胸部ベスト、ポケット、ストラップで胴体の面を仕上げる。
	_box(_torso, dark, Vector3(0, -0.62, -0.005), Vector3(body_width * 1.08, 0.18, 0.49))
	_box(_torso, COLORS.strap, Vector3(0.015, -0.28, -0.245), Vector3(0.13, 0.68, 0.035))
	_box(_torso, vest.albedo_color, Vector3(0, -0.22, -0.24), Vector3(body_width * 0.82, 0.52, 0.10))
	for side in [-1.0, 1.0]:
		_box(_torso, light, Vector3(side * 0.21, -0.42, -0.306), Vector3(0.22, 0.20, 0.055))
		_box(_torso, dark, Vector3(side * 0.21, -0.42, -0.337), Vector3(0.035, 0.11, 0.018))
	# 首と顔。目・鼻梁・頬の色差を正面斜めから読める配置にする。
	_capsule(_root, COLORS.skin_shadow, Vector3(0, 1.67, 0), Vector3(0, 1.88, 0), 0.13)
	_head = _pivot(_root, "Head", Vector3(0, 2.32, 0))
	_sphere(_head, skin, Vector3(0, 0, -0.005), Vector3(0.60, 0.66, 0.53))
	_sphere(_head, skin, Vector3(0, -0.15, -0.247), Vector3(0.41, 0.34, 0.13))
	_sphere(_head, COLORS.skin_shadow, Vector3(0, -0.23, -0.296), Vector3(0.24, 0.12, 0.055))
	for side in [-1.0, 1.0]:
		_sphere(_head, skin, Vector3(side * 0.29, -0.01, 0.0), Vector3(0.15, 0.22, 0.18))
		_sphere(_head, COLORS.eye, Vector3(side * 0.105, 0.015, -0.263), Vector3(0.048, 0.060, 0.035))
		_box(_head, skin, Vector3(side * 0.105, 0.075, -0.265), Vector3(0.105, 0.035, 0.045))
	# 丸みのある防護ヘルメット、ひさし、側面レール。
	_sphere(_head, dark, Vector3(0, 0.245, 0.02), Vector3(0.73, 0.48, 0.66))
	_box(_head, light, Vector3(0, 0.045, -0.305), Vector3(0.73, 0.075, 0.20))
	_box(_head, dark, Vector3(0, -0.04, -0.33), Vector3(0.52, 0.12, 0.055))
	_box(_head, COLORS.visor, Vector3(0, -0.045, -0.362), Vector3(0.40, 0.058, 0.028))
	_sphere(_head, light, Vector3(0, 0.27, -0.316), Vector3(0.14, 0.11, 0.035))

	# 腕は肩から手首の階層で動かし、手を武器グリップまで延ばす。
	_left_arm = _pivot(_torso, "SupportArm", Vector3(-body_width * 0.40, -0.02, 0))
	_right_arm = _pivot(_torso, "TriggerArm", Vector3(body_width * 0.40, -0.02, 0))
	for pair in [[_left_arm, -1.0], [_right_arm, 1.0]]:
		var arm:Node3D = pair[0]
		var side:float = pair[1]
		_capsule(arm, primary, Vector3(0, -0.08, 0), Vector3(side * 0.12, -0.42, -0.05), 0.16)
		_sphere(arm, light, Vector3(side * 0.12, -0.43, -0.05), Vector3(0.21, 0.20, 0.22))
		_capsule(arm, primary, Vector3(side * 0.12, -0.43, -0.05), Vector3(side * 0.04, -0.69, -0.27), 0.125)
		_capsule(arm, skin, Vector3(side * 0.04, -0.69, -0.27), Vector3(0.0, -0.76, -0.39), 0.105)
	# 太腿、膝当て、すね、ブーツ。
	_left_leg = _pivot(_root, "LeftLeg", Vector3(-0.22, 1.17, 0))
	_right_leg = _pivot(_root, "RightLeg", Vector3(0.22, 1.17, 0))
	for pair in [[_left_leg, -1.0], [_right_leg, 1.0]]:
		var leg:Node3D = pair[0]
		var side:float = pair[1]
		_capsule(leg, primary, Vector3.ZERO, Vector3(0, -0.48, 0.02), 0.17)
		_sphere(leg, dark, Vector3(0, -0.46, -0.165), Vector3(0.25, 0.20, 0.08))
		_capsule(leg, dark, Vector3(0, -0.48, 0.02), Vector3(0, -0.92, -0.04), 0.13)
		_box(leg, foot.albedo_color, Vector3(0.03, -0.99, -0.10), Vector3(0.34, 0.16, 0.47))
	# 防具は明確な胸甲と肩装甲。解放・プレビュー時だけ表示。
	_armor_mesh = _box(_torso, COLORS.metal_light, Vector3(0, -0.16, -0.315), Vector3(body_width * 0.72, 0.37, 0.075))
	_armor_mesh.visible = armor_enabled
	for side in [-1.0, 1.0]:
		var pad := _mesh(_torso, SphereMesh.new(), COLORS.metal_light, Vector3(side * body_width * 0.44, -0.05, -0.02), Vector3(0.30, 0.23, 0.34))
		pad.visible = armor_enabled
	# 脚のホルスターと通信パック。
	_box(_root, dark, Vector3(0.34, 0.86, -0.02), Vector3(0.27, 0.39, 0.28))
	_box(_root, light, Vector3(-0.35, 1.48, 0.32), Vector3(0.42, 0.52, 0.28))

	# 武器の識別可能なシルエット: ピストル、AK風レシーバー、三発バースト用光学照準器。
	_weapon = _pivot(_right_arm, "Weapon", Vector3(0, -0.69, -0.39))
	_build_weapon(gun, trim)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0, -1.06 if weapon_id == 0 else -1.48)
	_weapon.add_child(_muzzle)

func _build_weapon(gun:Material, trim:Material) -> void:
	var team_dark:Color = COLORS.ally_dark if enemy_kind.is_empty() else COLORS.enemy_dark
	var team_light:Color = COLORS.ally_light if enemy_kind.is_empty() else COLORS.enemy_light
	var receiver := BoxMesh.new()
	receiver.size = Vector3(0.20, 0.19, 0.58) if weapon_id == 0 else Vector3(0.24, 0.22, 0.74)
	_mesh(_weapon, receiver, COLORS.metal, Vector3(0, 0, -0.24), Vector3.ONE, gun)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.045
	barrel.bottom_radius = 0.045
	barrel.height = 0.64 if weapon_id == 0 else 1.14
	var barrel_mesh := _mesh(_weapon, barrel, COLORS.metal_light, Vector3(0, 0.01, -0.78 if weapon_id == 0 else -1.03), Vector3.ONE, trim)
	barrel_mesh.rotation.x = PI * 0.5
	if weapon_id == 0:
		var grip := BoxMesh.new()
		grip.size = Vector3(0.15, 0.31, 0.16)
		_mesh(_weapon, grip, team_dark, Vector3(0, 0.18, 0.01), Vector3.ONE, gun, Vector3(0.34, 0, 0))
		var slide := BoxMesh.new()
		slide.size = Vector3(0.24, 0.10, 0.32)
		_mesh(_weapon, slide, COLORS.metal_light, Vector3(0, -0.01, -0.28), Vector3.ONE, trim)
	else:
		var magazine := BoxMesh.new()
		magazine.size = Vector3(0.15, 0.37, 0.22)
		_mesh(_weapon, magazine, team_dark, Vector3(0, 0.26, -0.22), Vector3.ONE, gun, Vector3(0.27, 0, 0))
		var stock := BoxMesh.new()
		stock.size = Vector3(0.16, 0.20, 0.36)
		_mesh(_weapon, stock, team_dark, Vector3(0, 0.03, 0.36), Vector3.ONE, gun)
		var optic := BoxMesh.new()
		optic.size = Vector3(0.16, 0.16, 0.22) if weapon_id == 2 else Vector3(0.12, 0.08, 0.18)
		_mesh(_weapon, optic, team_light, Vector3(0, -0.17, -0.23), Vector3.ONE, trim)
		var handguard := BoxMesh.new()
		handguard.size = Vector3(0.28, 0.15, 0.43)
		_mesh(_weapon, handguard, team_dark, Vector3(0, 0.02, -0.67), Vector3.ONE, gun)
		if weapon_id == 2:
			# バーストライフルは三つの薬室リブと短いマズルブレーキ。
			for index in 3:
				_box(_weapon, COLORS.metal_light, Vector3(0, -0.12, -0.39 - index * 0.16), Vector3(0.08, 0.035, 0.05))
	var hand := SphereMesh.new()
	var glove := _mesh(_weapon, hand, COLORS.skin_shadow, Vector3(0, 0.02, -0.20), Vector3(0.17, 0.13, 0.18))
	glove.material_override = _material(Color("b77d61"))

func muzzle_global_position() -> Vector3:
	return _muzzle.global_position if is_instance_valid(_muzzle) else global_position + Vector3(0, 1.8, -0.8)

func set_pose(kind:String, elapsed:float, weapon:int = -1, active_recoil:float = 0.0) -> void:
	pose_name = kind
	pose_time = elapsed
	recoil = clampf(active_recoil, 0.0, 1.0)
	if not is_instance_valid(_root):
		return
	var swing := sin(elapsed * 7.3) * 0.38 if kind == "walk" else 0.0
	var breathe := sin(elapsed * 2.6) * 0.012 if kind in ["idle", "aim"] else 0.0
	_root.position.y = breathe + (0.045 * sin(elapsed * 13.0) if kind == "fire" else 0.0)
	_head.rotation.x = -0.08 if kind in ["aim", "fire", "hit"] else 0.0
	_torso.rotation.x = 0.06 + recoil * 0.12 if kind in ["aim", "fire"] else (-0.20 if kind == "hit" else 0.0)
	_left_leg.rotation.x = swing if kind == "walk" else (0.20 if kind == "retreat" else 0.0)
	_right_leg.rotation.x = -swing if kind == "walk" else (-0.20 if kind == "retreat" else 0.0)
	_left_arm.rotation.x = -0.52 - recoil * 0.17 if kind in ["aim", "fire", "idle"] else swing * 0.65
	_right_arm.rotation.x = -0.43 - recoil * 0.24 if kind in ["aim", "fire", "idle"] else -swing * 0.55
	_right_arm.rotation.y = -0.05 if kind in ["aim", "fire"] else 0.0
	_weapon.position.z = -0.39 + recoil * 0.10
	if kind == "hit":
		_torso.rotation.z = sin(elapsed * 28.0) * 0.12
	else:
		_torso.rotation.z = 0.0
	if kind == "retreat":
		rotation.y = -PI * 0.5
	elif enemy_kind.is_empty():
		rotation.y = PI * 0.5
	else:
		rotation.y = -PI * 0.5
