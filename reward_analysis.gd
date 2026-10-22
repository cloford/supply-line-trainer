extends SceneTree

# 開発専用の合成射撃。人物や実際の標的移動を再現するモデルではない。
# qを各命中で累乗してから集計する。平均qや表示点からの逆算は禁止。
const PROFILES := [
	{"name":"低精度","hit":0.35,"q":0.35,"clicks":0.65,"fire":1.0},
	{"name":"中程度","hit":0.70,"q":0.65,"clicks":1.0,"fire":1.0},
	{"name":"高精度・高ペース","hit":0.90,"q":0.90,"clicks":1.7,"fire":1.0},
	{"name":"中心を丁寧に狙う","hit":0.95,"q":0.95,"clicks":0.70,"fire":0.60},
	{"name":"精度を落としテンポ","hit":0.55,"q":0.40,"clicks":2.2,"fire":1.0}]
const ELAPSED := 120.0

static func evaluate(weapon:int,difficulty:int,stats:Dictionary,candidate:int=0,carry:float=0.0)->Dictionary:
	var sample:=stats.duplicate(true)
	if candidate==1 and weapon==0:
		# 候補A：HG係数0.105→0.100と等価な同次スケール。製品の係数は変えない。
		for key in ["base_points","center_bonus","speed_bonus","streak_bonus"]:sample[key]*=0.100/0.105
	if candidate==2:
		# 候補B：速度＋連続の上限だけ基本点の20%→10%。
		var total:float=sample.speed_bonus+sample.streak_bonus
		var scale:=minf(1.0,float(sample.base_points)*0.10/maxf(0.001,total))
		sample.speed_bonus*=scale;sample.streak_bonus*=scale
	return Balance.score_and_reward(weapon,difficulty,sample,0,0,ELAPSED,carry)

static func simulate(weapon:int,profile:Dictionary)->Dictionary:
	var rng:=RandomNumberGenerator.new();rng.seed=2026102217
	var s:Dictionary={"base_points":0.0,"center_bonus":0.0,"speed_bonus":0.0,"streak_bonus":0.0,"shots":0,"hits":0,"kills":0,"fire_time":0.0,"track_time":0.0}
	var q_sum:=0.0;var q_time:=0.0;var streak:=0;var auto_streak:=0.0;var last_success:=-99.0;var spawned:=0.0
	if weapon==1:
		# 同一の100ms区間を使用し、非射撃区間もELAPSEDから除かない。
		for tick in int(ELAPSED*10):
			var fired:=float(tick%20)/20.0<float(profile.fire)
			if not fired:continue
			s.fire_time+=0.1;s.shots+=1
			if rng.randf()>=float(profile.hit):auto_streak=maxf(0,auto_streak-0.2);continue
			var q:=clampf(float(profile.q)+rng.randf_range(-0.1,0.1),0.0,1.0)
			s.hits+=1;s.track_time+=0.1;s.base_points+=10.0;s.center_bonus+=10.0*pow(q,1.5);q_time+=q*0.1;auto_streak+=0.1
			if auto_streak>1:s.streak_bonus+=0.5
	else:
		var shots:=int(floor(ELAPSED*float(profile.clicks)))*(3 if weapon==2 else 1)
		var progress:=[0,0,0];var precision:=[0.0,0.0,0.0]
		for index in shots:
			var t:float=(float(index/3)/float(profile.clicks)+(index%3)*0.085) if weapon==2 else float(index)/float(profile.clicks)
			if t>=ELAPSED:break
			s.shots+=1
			var target:=0
			if bool(profile.get("partial",false)):
				while target<3 and progress[target]>=2:target+=1
			var hit:=rng.randf()<float(profile.hit) and target<3
			if not hit:streak=0;continue
			var q:=clampf(float(profile.q)+rng.randf_range(-0.1,0.1),0.0,1.0)
			var p:=pow(q,1.5);s.hits+=1;q_sum+=q
			if weapon==0:
				s.base_points+=45.0;s.center_bonus+=45.0*p;s.kills+=1
				s.speed_bonus+=12.0*clampf(1.0-(t-spawned)/2.5,0.0,1.0)
				streak=streak+1 if t-last_success<4 else 1;s.streak_bonus+=minf(8,float(streak-1)*1.5);last_success=t;spawned=t
			else:
				s.base_points+=15.0;s.center_bonus+=15.0*p;progress[target]+=1;precision[target]+=p
				if progress[target]>=3:
					s.base_points+=20.0;s.center_bonus+=20.0*precision[target]/3.0;s.kills+=1;progress[target]=0;precision[target]=0
					var gap:=t-last_success
					if last_success>=0:s.speed_bonus+=10.0*clampf(1-gap/2.2,0.0,1.0)
					streak=streak+1 if gap<4 else 1;s.streak_bonus+=minf(6,float(streak-1));last_success=t
	return {"stats":s,"q_sum":q_sum,"q_time":q_time,"elapsed":ELAPSED}

func _init()->void:
	var output:=OS.get_environment("SLT_ANALYSIS_OUTPUT")
	if output.is_empty():push_error("SLT_ANALYSIS_OUTPUT required");quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	var results:Array=[]
	var markdown:="# 報酬の合成条件比較\n\n全行が固定乱数の合成条件、各120秒。人間の試遊や、難度別の実現成績ではない。クリック数/秒は単発・バーストの入力頻度、オートは時間積分。各qを累乗して集計し、全計測時間を分母にした。候補AはHG係数0.100、候補Bは速度＋連続上限10%。\n\n|条件|武器/難度|現行P/分|候補A|変化|候補B|変化|命中/追従率|中心への近さ|体/分または有効追従|初回増員/装備まで秒（現行）|\n|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
	for weapon in 3:
		var profiles:=PROFILES.duplicate(true)
		if weapon==0:profiles.append({"name":"外れを増やす連打","hit":0.10,"q":0.35,"clicks":6.0,"fire":1.0})
		if weapon==2:profiles.append({"name":"部分命中止め（3標的を各2発まで）","hit":0.95,"q":0.9,"clicks":1.0,"fire":1.0,"partial":true})
		if weapon==1:profiles.append({"name":"追いやすい瞬間だけ射撃","hit":0.95,"q":0.95,"clicks":1.0,"fire":0.35})
		for profile in profiles:
			var raw:=simulate(weapon,profile)
			for difficulty in 3:
				var baseline:=evaluate(weapon,difficulty,raw.stats)
				var a:=evaluate(weapon,difficulty,raw.stats,1);var b:=evaluate(weapon,difficulty,raw.stats,2)
				var ppm:float=baseline.exact_points/ELAPSED*60
				var ap:float=a.exact_points/ELAPSED*60;var bp:float=b.exact_points/ELAPSED*60
				var center:float=(raw.q_time/raw.stats.fire_time if weapon==1 else raw.q_sum/maxi(1,raw.stats.shots))*100
				var pace:float=raw.stats.track_time/ELAPSED*100 if weapon==1 else raw.stats.kills/ELAPSED*60
				var entry:Dictionary={"type":"synthetic","profile":profile,"weapon":weapon,"difficulty":difficulty,"elapsed":ELAPSED,"raw":raw,"scoring_version":Balance.SCORING_VERSION,"ppm":ppm,"candidate_a":ap,"candidate_b":bp,"accuracy":baseline.accuracy,"center":center,"pace":pace}
				results.append(entry)
				markdown+="|%s|%s/%s|%.1f|%.1f|%+.1f%%|%.1f|%+.1f%%|%.1f%%|%.1f|%.1f|%.1f / %.1f|\n"%[profile.name,Balance.WEAPONS[weapon],Balance.DIFFICULTY[difficulty].name,ppm,ap,(ap/ppm-1)*100 if ppm>0 else 0,bp,(bp/ppm-1)*100 if ppm>0 else 0,baseline.accuracy*100,center,pace,70.0/ppm*60 if ppm>0 else 0,120.0/ppm*60 if ppm>0 else 0]
	var file:=FileAccess.open(output.path_join("reward-analysis.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close()
	file=FileAccess.open(output.path_join("reward-comparison.md"),FileAccess.WRITE);file.store_string(markdown);file.close()
	print("REWARD_ANALYSIS_OK: ",results.size()," synthetic cases; per-hit preweight aggregates, current + 2 candidates; ",output)
	quit(0)
