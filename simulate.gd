extends SceneTree

func _init()->void:
	var supply:=0.0
	var recruit:=0
	var gear:=0
	var front:=0
	var hp:float=Balance.front_hp(0)
	var unlock_auto:float=-1
	var unlock_burst:float=-1
	var seconds:=0
	while front<20 and seconds<7200:
		seconds+=1
		if seconds%60==0: supply+=105.0
		var costs:=[Balance.recruit_cost(recruit),Balance.gear_cost(gear)]
		var choice:=0 if recruit<=gear*2+2 else 1
		if supply>=costs[choice]:
			supply-=costs[choice]
			if choice==0: recruit+=1
			elif choice==1: gear+=1
		hp-=Balance.combat_power(recruit,gear)*0.18
		if hp<=0:
			front+=1
			if front==3: unlock_auto=seconds/60.0
			if front==7: unlock_burst=seconds/60.0
			hp=Balance.front_hp(front)
	print("SIM: auto=%.1f min burst=%.1f min front20=%.1f min soldiers=%d gear=%d credits=%.0f" % [unlock_auto,unlock_burst,seconds/60.0,Balance.soldier_count(recruit),gear,supply])
	quit(0)
