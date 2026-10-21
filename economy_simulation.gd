extends SceneTree

# 物理入力を省いた決定的な経済シミュレーション。実機プレイの代わりにはならない。
func _init()->void:
	var comparisons:Dictionary={18000:[],27000:[]}
	for weapon in 3:
		var rng:=RandomNumberGenerator.new();rng.seed=20261022
		var stats:Dictionary={"base_points":0.0,"center_bonus":0.0,"speed_bonus":0.0,"streak_bonus":0.0,"shots":0,"hits":0,"track_time":0.0,"fire_time":0.0}
		var recruit:=0;var gear:=0;var wallet:=0;var granted:=0;var streak:=0;var progress:=0;var last_kill:=-99.0;var auto_streak:=0.0
		var first_recruit:=-1;var first_gear:=-1
		for tick in 27000:
			var seconds:=float(tick+1)/10.0
			if weapon==1:
				stats.fire_time+=0.1
				if tick%10<7:
					stats.track_time+=0.1;stats.base_points+=10.0;stats.center_bonus+=5.0;auto_streak+=0.1
					if auto_streak>1.0:stats.streak_bonus+=0.5
				else:auto_streak=maxf(0.0,auto_streak-0.2)
			elif tick%10==0:
				for shot in (3 if weapon==2 else 1):
					stats.shots+=1
					if rng.randf()>=0.7:streak=0;continue
					stats.hits+=1
					if weapon==0:
						stats.base_points+=45.0;stats.center_bonus+=22.5;stats.speed_bonus+=7.2;streak+=1;stats.streak_bonus+=minf(8.0,float(streak-1)*1.5)
					else:
						stats.base_points+=15.0;stats.center_bonus+=7.5;progress+=1
						if progress>=3:
							stats.base_points+=20.0;stats.center_bonus+=10.0;progress=0
							var switch_time:=seconds-last_kill
							if last_kill>=0:stats.speed_bonus+=10.0*clampf(1.0-switch_time/2.2,0.0,1.0)
							streak=streak+1 if switch_time<4.0 else 1;stats.streak_bonus+=minf(6.0,float(streak-1));last_kill=seconds
			var result:=Balance.score_and_reward(weapon,0,stats,0,0,seconds)
			if first_recruit<0 and result.score>=70:first_recruit=int(ceil(seconds))
			if first_gear<0 and result.score>=120:first_gear=int(ceil(seconds))
			if (tick+1)%600==0:
				wallet+=result.score-granted;granted=result.score
				while wallet>=mini(int(Balance.recruit_cost(recruit)),int(Balance.gear_cost(gear))):
					var rc:=int(Balance.recruit_cost(recruit));var gc:=int(Balance.gear_cost(gear))
					var recruit_value:=(Balance.combat_power(recruit+1,gear)-Balance.combat_power(recruit,gear))/rc
					var gear_value:=(Balance.combat_power(recruit,gear+1)-Balance.combat_power(recruit,gear))/gc
					if wallet>=rc and (wallet<gc or recruit_value>=gear_value):wallet-=rc;recruit+=1
					else:wallet-=gc;gear+=1
			if tick+1 in [18000,27000]:
				comparisons[tick+1].append(int(result.score))
				print("ECONOMY_SIM weapon=",Balance.WEAPONS[weapon]," minutes=",int(seconds/60)," points=",result.score," recruit=",recruit," gear=",gear," remainder=",wallet," first_recruit_seconds=",first_recruit," first_gear_seconds=",first_gear)
	for elapsed in comparisons:
		var scores:Array=comparisons[elapsed]
		if float(scores.max())/float(scores.min())>1.25:
			push_error("同一習熟度モデルの武器間ポイント差が25%を超えています。");quit(1);return
	print("ECONOMY_SIM_OK: 30/45 minute baseline weapon spread within 25 percent")
	quit(0)
