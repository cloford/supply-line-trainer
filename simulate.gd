extends SceneTree

func _init()->void:
	var supply:=90.0
	var recruit:=0
	var gear:=0
	var depot:=0
	var front:=0
	var hp:float=Balance.front_hp(0)
	var unlock_auto:float=-1
	var unlock_burst:float=-1
	var seconds:=0
	while front<20 and seconds<7200:
		seconds+=1
		supply+=Balance.passive_rate(depot)
		if seconds%60==0: supply+=105.0
		var costs:=[Balance.recruit_cost(recruit),Balance.gear_cost(gear),Balance.depot_cost(depot)]
		var choice:=0 if recruit<=gear else 1
		if depot<3 and seconds>240 and seconds%300<60: choice=2
		if supply>=costs[choice]:
			supply-=costs[choice]
			if choice==0: recruit+=1
			elif choice==1: gear+=1
			else: depot+=1
		hp-=Balance.combat_power(recruit,gear)*0.18
		if hp<=0:
			front+=1
			if front==3: unlock_auto=seconds/60.0
			if front==7: unlock_burst=seconds/60.0
			hp=Balance.front_hp(front)
	print("SIM: auto=%.1f min burst=%.1f min front20=%.1f min upgrades R%d/G%d/D%d" % [unlock_auto,unlock_burst,seconds/60.0,recruit,gear,depot])
	quit(0)
