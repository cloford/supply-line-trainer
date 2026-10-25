class_name V2Replay
extends RefCounted

# This player consumes recorded facts. It never runs a ray, RNG, ledger or battle.
var record:Dictionary = {}
var start_time := 0.0
var end_time := 8.0
var time := 0.0
var playing := false
var cursor := 0
var targets:Dictionary = {}
var pose_state:Dictionary = {}
var emitted:Array[Dictionary] = []

func start(source:Dictionary)->void:
	record = source.duplicate(true)
	var shots:Array = record.get("shots", [])
	start_time = clampf(float(shots[0].time) - 0.5, 0.0, 52.0) if not shots.is_empty() else 0.0
	end_time = minf(60.0, start_time + 8.0)
	time = start_time
	playing = true
	cursor = 0
	targets.clear()
	emitted.clear()
	var events:Array = record.get("events", [])
	while cursor < events.size() and float(events[cursor].time) < start_time:
		_apply(events[cursor])
		cursor += 1
	_sample_pose()

func advance(delta:float)->Array[Dictionary]:
	var result:Array[Dictionary] = []
	if not playing or delta < 0.0 or delta > 0.25:
		return result
	var next_time := minf(end_time, time + delta)
	var events:Array = record.get("events", [])
	while cursor < events.size() and float(events[cursor].time) <= next_time:
		var event:Dictionary = events[cursor]
		if float(event.time) < end_time:
			_apply(event)
			result.append(event.duplicate(true))
			if str(event.type) == "shot":
				emitted.append(event.duplicate(true))
		cursor += 1
	time = next_time
	playing = time < end_time
	_sample_pose()
	return result

func _apply(event:Dictionary)->void:
	var kind := str(event.get("type", ""))
	var id := str(event.get("target_id", ""))
	if kind in ["spawn", "target_spawn", "move", "target_move"]:
		targets[id] = event.get("state", {}).duplicate(true)
	elif kind in ["kill", "destroy", "target_kill"]:
		targets.erase(id)

func _sample_pose()->void:
	var poses:Array = record.get("poses", [])
	if poses.is_empty():
		pose_state = {}
		return
	var before:Dictionary = poses[0]
	var after:Dictionary = poses[-1]
	for pose in poses:
		if float(pose.time) <= time:
			before = pose
		else:
			after = pose
			break
	var weight := clampf((time - float(before.time)) / maxf(0.00001, float(after.time) - float(before.time)), 0.0, 1.0)
	pose_state = {"origin": [], "rotation": []}
	for key in ["origin", "rotation"]:
		for axis in 3:
			var a := float(before[key][axis])
			var b := float(after[key][axis])
			pose_state[key].append(lerp_angle(a, b, weight) if key == "rotation" else lerpf(a, b, weight))
