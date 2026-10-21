extends SceneTree

var failures:Array[String]=[]

func check(condition:bool,message:String)->void:
	if not condition:failures.append(message)

func _init()->void:call_deferred("_run")

func _run()->void:
	var battle:=BattleView.new()
	battle.size=Vector2(1280,720)
	root.add_child(battle)
	await process_frame
	check(battle.visible_soldiers(-2)==1 and battle.visible_soldiers(0)==1,"visible soldier minimum is not clamped")
	check(battle.visible_soldiers(48)==48 and battle.visible_soldiers(200)==48,"visible soldier maximum is not clamped")

	var initial:Dictionary={"soldiers":6,"soldier_label":"6人","gear":0,"front":0,"enemy_hp":70.0,"enemy_max":70.0,"running":true}
	battle.set_state(initial)
	check(is_equal_approx(float(initial.enemy_hp),70.0),"set_state mutated caller HP")
	check(battle.fire_effect_count(6)==0,"firing started without observed damage")
	battle.damage_age=0.0
	check(battle.fire_effect_count(6)==2,"active recent damage did not produce troop-scaled effects")
	battle._process(0.1)
	check(is_equal_approx(float(battle.state.enemy_hp),70.0),"BattleView animation mutated simulated enemy HP")
	check(is_equal_approx(float(initial.enemy_hp),70.0),"BattleView animation mutated input HP")

	var paused:Dictionary=initial.duplicate(true)
	paused["active"]=false
	battle.set_state(paused)
	battle.anim_time=1.0;battle.march=0.3;battle.world_scroll=12.0;battle.damage_age=0.1;battle.hit_pulse=0.1
	battle.fallen=[{"index":0,"life":0.5}]
	var frozen_fallen_life:float=float(battle.fallen[0].life)
	battle._process(0.5)
	check(is_equal_approx(battle.anim_time,1.0) and is_equal_approx(battle.march,0.3) and is_equal_approx(battle.world_scroll,12.0),"paused battle animation or march advanced")
	check(is_equal_approx(float(battle.fallen[0].life),frozen_fallen_life),"paused effects advanced")
	check(battle.hit_pulse==0.0 and battle.damage_age==99.0 and battle.fire_effect_count(6)==0,"paused combat effects were not stopped")
	check(is_equal_approx(float(battle.state.enemy_hp),70.0),"pause changed simulated HP")

	var old_front:Dictionary={"soldiers":12,"soldier_label":"12人","gear":0,"front":0,"enemy_hp":30.0,"enemy_max":100.0,"running":true}
	battle.set_state(old_front)
	check(battle.defeated==3,"enemy retirement count did not track damage state")
	var fallen_before:int=battle.fallen.size()
	var new_front:Dictionary={"soldiers":12,"soldier_label":"12人","gear":0,"front":1,"enemy_hp":100.0,"enemy_max":100.0,"running":true}
	battle.set_state(new_front)
	check(battle.defeated==0 and is_zero_approx(battle.march),"breakthrough did not reset defeated count and march")
	check(battle.fallen.size()==fallen_before+2,"breakthrough did not retire remaining frontline enemies")
	check(int(battle.state.front)==1 and is_equal_approx(float(battle.state.enemy_hp),100.0),"next frontline state was not applied")
	check(is_equal_approx(float(old_front.enemy_hp),30.0) and is_equal_approx(float(new_front.enemy_hp),100.0),"front transition mutated simulated HP")

	for troop_count in [1,6,48]:
		var effect_count:=battle.fire_effect_count(troop_count)
		battle.state["active"]=true
		battle.damage_age=0.0;battle.march=1.0
		effect_count=battle.fire_effect_count(troop_count)
		check(effect_count<=BattleView.MAX_FIRE_EFFECTS,"fire effect density exceeded cap for %d troops"%troop_count)
		var covered:Dictionary={}
		var cycle_count:=ceili(float(troop_count)/float(maxi(1,effect_count)))
		for cycle in cycle_count:
			var participants:=BattleView.fire_participants_for_cycle(cycle,troop_count,effect_count)
			var unique:Dictionary={}
			for participant in participants:
				unique[participant]=true
				covered[participant]=true
			check(unique.size()==participants.size(),"same cycle selected duplicate soldiers (%d troops, cycle %d)"%[troop_count,cycle])
		check(covered.size()==troop_count,"round-robin did not cover every soldier in a full firing cycle (%d troops)"%troop_count)
	check(BattleView.fire_participants_for_cycle(0,0,1).is_empty(),"zero soldiers produced firing participants")
	battle.damage_age=0.49
	check(battle.fire_effect_count(48)==0,"firing continued after damage window expired")
	battle.state["active"]=false
	battle.damage_age=0.0
	check(battle.fire_effect_count(48)==0,"firing continued while inactive")

	battle.queue_free()
	if failures.is_empty():
		print("BATTLE_TEST_OK: state-only display, bounds, pause freeze, breakthrough retirement, capped round-robin effects")
		quit(0);return
	for failure in failures:push_error(failure)
	quit(1)
