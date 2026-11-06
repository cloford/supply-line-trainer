class_name TrainingExtras
extends RefCounted

# FPS自由練習だけの条件。部隊・兵士プロフィールには使用しない。
const GRID_X := [-3.0, 0.0, 3.0]
const GRID_Y := [1.0, 2.5, 4.0]
const GRID_Z := -8.0
const GRID_INTERVAL := 0.24
const GRENADE_SPEED := 16.0
const GRENADE_LIFT := 3.8
const GRAVITY := Vector3(0, -9.8, 0)
const BLAST_RADIUS := 2.2
const BLAST_DAMAGE := 100.0
const TARGET_HP := 100.0
const GRENADE_INTERVAL := 0.8
const MAX_PROJECTILES := 3
const MAX_EFFECTS := 12
const GRENADE_POSITIONS := [Vector3(-2.4, 0.62, -7.5), Vector3(-0.8, 0.62, -7.5), Vector3(-1.6, 0.62, -9.1), Vector3(-4.0, 0.62, -9.3), Vector3(0.8, 0.62, -9.3)]

static func grid_position(cell:int)->Vector3:
	return Vector3(GRID_X[cell % 3], GRID_Y[cell / 3], GRID_Z)

static func next_cell(bag:Array[int], previous:int, rng:RandomNumberGenerator)->int:
	if bag.is_empty():
		for cell in 9:
			bag.append(cell)
		for index in range(8, 0, -1):
			var other := rng.randi_range(0, index)
			var value := bag[index]
			bag[index] = bag[other]
			bag[other] = value
		if bag[0] == previous:
			var other := rng.randi_range(1, 8)
			var value := bag[0]
			bag[0] = bag[other]
			bag[other] = value
	return bag.pop_front()

static func launch(origin:Vector3, direction:Vector3, id:int)->Dictionary:
	return {"id":id, "position":origin, "velocity":direction.normalized() * GRENADE_SPEED + Vector3.UP * GRENADE_LIFT, "age":0.0}

static func segment_sphere(start:Vector3, end:Vector3, center:Vector3, radius:float)->float:
	var motion := end - start
	var length_squared := motion.length_squared()
	if length_squared <= 0.00000001:
		return 0.0 if start.distance_squared_to(center) <= radius * radius else INF
	var offset := start - center
	if offset.length_squared() <= radius * radius:
		return 0.0
	var b := 2.0 * offset.dot(motion)
	var c := offset.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * length_squared * c
	if discriminant < 0:
		return INF
	var time := (-b - sqrt(discriminant)) / (2.0 * length_squared)
	return time if time >= 0.0 and time <= 1.0 else INF

static func advance(projectile:Dictionary, delta:float, positions:Array[Vector3], target_radius:float)->Dictionary:
	var remaining := maxf(0.0, delta)
	while remaining > 0.00000001:
		var step := minf(remaining, 1.0 / 120.0)
		var start:Vector3 = projectile.position
		var end:Vector3 = start + Vector3(projectile.velocity) * step + GRAVITY * 0.5 * step * step
		var first := INF
		var direct := -1
		for index in positions.size():
			var fraction := segment_sphere(start, end, positions[index], target_radius)
			if fraction < first:
				first = fraction
				direct = index
		# 射場の床・後壁・側壁。最初の衝突だけを確定する。
		for boundary in [{"axis":1,"value":0.06,"below":true}, {"axis":2,"value":-11.8,"below":true}, {"axis":0,"value":-9.8,"below":true}, {"axis":0,"value":9.8,"below":false}]:
			var axis:int = boundary.axis
			var value:float = boundary.value
			var crosses:bool = (end[axis] <= value and start[axis] > value) if boundary.below else (end[axis] >= value and start[axis] < value)
			if crosses:
				var fraction := (value - start[axis]) / (end[axis] - start[axis])
				var contact := start.lerp(end, fraction)
				# 見えている面の範囲だけ。壁より上・床より外に無限の面を作らない。
				var on_surface := absf(contact.x) <= 10.1 and absf(contact.z) <= 12.1 if axis == 1 else (contact.y >= -0.1 and contact.y <= 5.1 and (absf(contact.x) <= 10.1 if axis == 2 else absf(contact.z) <= 12.1))
				if not on_surface:
					continue
				if fraction < first:
					first = fraction
					direct = -1
		if first <= 1.0:
			projectile.position = start.lerp(end, first)
			projectile.age = float(projectile.age) + step * first
			return {"position":projectile.position, "direct_index":direct}
		projectile.position = end
		projectile.velocity = Vector3(projectile.velocity) + GRAVITY * step
		projectile.age = float(projectile.age) + step
		remaining -= step
		if float(projectile.age) >= 4.0:
			return {"position":end, "direct_index":-1, "expired":true}
	return {}

static func victims(position:Vector3, targets:Array[Vector3], direct_index:int)->Array[int]:
	var result:Array[int] = []
	for index in targets.size():
		if index == direct_index or position.distance_to(targets[index]) <= BLAST_RADIUS:
			result.append(index)
	return result

static func predict(origin:Vector3, direction:Vector3, targets:Array[Vector3] = [], radius:float = 0.0)->PackedVector3Array:
	var projectile := launch(origin, direction, -1)
	var result := PackedVector3Array([origin])
	for step in 80:
		var impact := advance(projectile, 0.05, targets, radius)
		result.append(projectile.position)
		if not impact.is_empty():
			break
	return result
