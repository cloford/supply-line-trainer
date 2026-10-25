class_name V2Combat
extends RefCounted

const EPSILON := 0.00000001
var state:Dictionary = {}
var _data:Dictionary = {}
var _seed := 1
var _rngs:Array[RandomNumberGenerator] = []
var _continued := false
var _march_left := 0.0
var _paused := false

func configure(data:Dictionary, seed_value:int = 1)->void:
	_data = data.duplicate(true)
	_seed = seed_value
	_continued = bool(data.get("expedition_complete",false))
	_march_left = 0.0
	_paused = false
	_rngs.clear()
	for weapon in range(3):
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed + weapon * 104729
		_rngs.append(rng)
	state = {"status":str(data.get("battle_status","fighting")), "section":maxi(0,int(data.get("front",0))), "time":0.0, "allies":[], "enemies":[], "expedition_complete":_continued}
	if state.status not in ["retreat","complete"]:
		state.status = "fighting"
	_begin_section(false)

func start(data:Dictionary, seed_value:int = 1)->void:
	configure(data,seed_value)

func set_data(data:Dictionary)->void:
	_data = data.duplicate(true)

func set_paused(paused:bool)->void:
	_paused = paused

func _begin_section(preserve:bool)->void:
	var old:Array = state.allies
	var allies:Array[Dictionary] = []
	for weapon in range(3):
		if not V2Profiles.unlocked(_data,weapon) or not bool(_data.deployed[weapon]):
			continue
		var profile := V2Profiles.current(_data,weapon)
		var actor := {"id":"ally-%d" % weapon,"weapon":weapon,"profile":profile,"armor":bool(_data.armor[weapon]),"protection":int(_data.protection[weapon]),"name":str(_data.names[weapon]),"hp":V2Profiles.hp(_data,weapon),"max_hp":V2Profiles.hp(_data,weapon),"alive":true,"attack_clock":0.0,"phase":0.0,"shot_index":0,"cycle":0,"shots":0,"hits":0,"criticals":0}
		if preserve:
			for previous in old:
				if int(previous.weapon) == weapon and bool(previous.alive) and str(previous.profile.record_id) == str(profile.record_id):
					for key in ["attack_clock","phase","shot_index","cycle","shots","hits","criticals"]:
						actor[key] = previous[key]
		allies.append(actor)
	state.allies = allies
	var enemies:Array[Dictionary] = []
	var group := V2Rules.enemy_group(int(state.section))
	for i in range(group.size()):
		var definition:Dictionary = group[i]
		enemies.append({"id":"enemy-%d-%d" % [state.section,i], "kind":definition.kind, "max_hp":definition.max_hp, "hp":definition.max_hp, "damage":definition.damage, "interval":definition.interval, "next_shot":float(definition.interval) + i * 0.13, "alive":true})
	state.enemies = enemies
	if allies.is_empty() and state.status == "fighting":
		state.status = "idle"

func _next_shot(actor:Dictionary)->float:
	var times:Array = actor.profile.timeline
	if times.is_empty():
		return INF
	return int(actor.cycle) * V2Rules.DURATION + float(times[int(actor.shot_index)]) - float(actor.attack_clock)

func _step_cursor(actor:Dictionary)->void:
	actor.shot_index += 1
	if int(actor.shot_index) >= actor.profile.timeline.size():
		actor.shot_index = 0
		actor.cycle += 1

func _living(items:Array)->Dictionary:
	for item in items:
		if bool(item.alive):
			return item
	return {}

func _event(kind:String, values:Dictionary = {})->Dictionary:
	var result := values.duplicate(true)
	result["type"] = kind
	result["time"] = float(state.time)
	result["section"] = int(state.section)
	return result

static func roll(rng:RandomNumberGenerator, p:float, c:float)->Dictionary:
	var hit := rng.randf() < clampf(p,0.0,1.0)
	return {"hit":hit,"critical":hit and rng.randf() < clampf(c,0.0,1.0)}

func _ally_fire(actor:Dictionary, events:Array[Dictionary])->void:
	var target := _living(state.enemies)
	if target.is_empty():
		return
	_step_cursor(actor)
	var outcome := roll(_rngs[int(actor.weapon)],float(actor.profile.p),float(actor.profile.c))
	var damage := float(V2Rules.DAMAGE[int(actor.weapon)]) * (V2Rules.CRITICAL_MULTIPLIER if outcome.critical else 1.0) if outcome.hit else 0.0
	target.hp = maxf(0.0,float(target.hp)-damage)
	target.alive = float(target.hp) > EPSILON
	actor.shots += 1
	actor.hits += 1 if outcome.hit else 0
	actor.criticals += 1 if outcome.critical else 0
	var values := {"actor_id":actor.id,"weapon":actor.weapon,"target_id":target.id,"hit":outcome.hit,"critical":outcome.critical,"damage":damage,"target_hp":target.hp,"target_alive":target.alive}
	events.append(_event("ally_shot",values))
	if outcome.hit:
		events.append(_event("hit",values))

func _enemy_fire(enemy:Dictionary, events:Array[Dictionary])->void:
	var target := _living(state.allies)
	if target.is_empty():
		return
	enemy.next_shot += float(enemy.interval)
	var damage := float(enemy.damage)
	target.hp = maxf(0.0,float(target.hp)-damage)
	target.alive = float(target.hp) > EPSILON
	var values := {"actor_id":enemy.id,"weapon":-1,"target_id":target.id,"hit":true,"critical":false,"damage":damage,"target_hp":target.hp,"target_alive":target.alive}
	events.append(_event("enemy_shot",values))
	events.append(_event("hit",values))

func _boundary(events:Array[Dictionary])->bool:
	if _living(state.enemies).is_empty():
		state.section += 1
		if int(state.section) == V2Rules.FIRST_EXPEDITION and not _continued:
			state.status = "complete"
			state.expedition_complete = true
			events.append(_event("complete",{"front":state.section,"expedition_complete":true}))
		else:
			state.status = "marching"
			_march_left = V2Rules.MARCH_SECONDS
			events.append(_event("march",{"front":state.section,"duration":V2Rules.MARCH_SECONDS}))
		return true
	if _living(state.allies).is_empty():
		state.status = "retreat"
		events.append(_event("retreat",{"front":state.section}))
		return true
	return false

func advance(delta:float)->Array[Dictionary]:
	var events:Array[Dictionary] = []
	if state.is_empty() or _paused or not is_finite(delta) or delta <= 0.0 or delta > V2Rules.MAX_FRAME_DELTA:
		return events
	var remaining := delta
	var guard := 0
	while remaining > EPSILON and guard < 10000:
		guard += 1
		if state.status == "marching":
			var step := minf(remaining,_march_left)
			_march_left -= step
			remaining -= step
			state.time += step
			if _march_left <= EPSILON:
				state.status = "fighting"
				_begin_section(true)
				events.append(_event("section",{"front":state.section}))
			continue
		if state.status != "fighting":
			break
		if _boundary(events):
			continue
		var until := remaining
		for actor in state.allies:
			if bool(actor.alive):
				until = minf(until,maxf(0.0,_next_shot(actor)))
		for enemy in state.enemies:
			if bool(enemy.alive):
				until = minf(until,maxf(0.0,float(enemy.next_shot)))
		state.time += until
		remaining -= until
		for actor in state.allies:
			if bool(actor.alive):
				actor.attack_clock += until
				actor.phase = fposmod(float(actor.attack_clock),V2Rules.DURATION)
		for enemy in state.enemies:
			if bool(enemy.alive):
				enemy.next_shot -= until
		# 同時刻は固定枠順の味方→生存敵。死亡を即時確定し、最後の敵撃破を先に判定。
		for actor in state.allies:
			if bool(actor.alive) and _next_shot(actor) <= EPSILON and not _living(state.enemies).is_empty():
				_ally_fire(actor,events)
		if _boundary(events):
			continue
		for enemy in state.enemies:
			if bool(enemy.alive) and float(enemy.next_shot) <= EPSILON and not _living(state.allies).is_empty():
				_enemy_fire(enemy,events)
		_boundary(events)
	return events

func snapshot()->Dictionary:
	return state.duplicate(true)

# UI retry/continue may be committed only after durable saving. Clone all runtime
# cursors and independent RNG states, not just the displayed snapshot.
func copy_runtime()->V2Combat:
	var copy := V2Combat.new()
	copy.state = state.duplicate(true)
	copy._data = _data.duplicate(true)
	copy._seed = _seed
	copy._continued = _continued
	copy._march_left = _march_left
	copy._paused = _paused
	for rng in _rngs:
		var cloned := RandomNumberGenerator.new()
		cloned.seed = rng.seed
		cloned.state = rng.state
		copy._rngs.append(cloned)
	return copy

func retry(data:Dictionary = {})->Array[Dictionary]:
	var events:Array[Dictionary] = []
	if state.is_empty() or state.status not in ["retreat","idle"]:
		return events
	if not data.is_empty():
		set_data(data)
	for weapon in range(3):
		_rngs[weapon].seed = _seed + weapon * 104729
	state.status = "fighting"
	_begin_section(false)
	events.append(_event("retry",{"front":state.section}))
	return events

func continue_expedition(data:Dictionary = {})->Array[Dictionary]:
	var events:Array[Dictionary] = []
	if state.is_empty() or state.status != "complete":
		return events
	if not data.is_empty():
		set_data(data)
	_continued = true
	state.expedition_complete = true
	state.status = "fighting"
	_begin_section(true)
	events.append(_event("section",{"front":state.section}))
	return events

func persistent_state()->Dictionary:
	return {"front":int(state.get("section",0)),"battle_status":str(state.get("status","fighting")),"expedition_complete":bool(state.get("expedition_complete",false))}
