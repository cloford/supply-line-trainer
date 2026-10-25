extends SceneTree

var checks := 0
var failures := 0

func _initialize()->void:
	if OS.get_environment("SLT_TEST_DATA") != "1" or not OS.get_user_data_dir().replace("\\","/").contains(".test-appdata-v2-core"):
		push_error("実セーブ保護: SLT_TEST_DATA=1 と専用 .test-appdata-v2-core APPDATA が必要です。")
		quit(2)
		return
	_measurements()
	_ledger()
	_combat()
	_storage()
	print("V2_CORE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(value:bool, message:String)->void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func measured(id:String = "example", weapon:int = 0, count:int = 4, p:float = 0.5, q:float = 0.75)->Dictionary:
	var collector := V2Measurement.new()
	collector.begin(weapon,V2Save.SETTING_DEFAULTS,17,id)
	for i in range(count):
		collector.shot(0.2 + float(i) * 59.6 / maxi(1,count), i < int(count*p),q,"target",Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-11),int(i/3),i%3)
	return collector.completed(60.0)

func ledger_record(id:String, credits:int = 20, elapsed:float = 60.0)->Dictionary:
	return {"id":id,"weapon":0,"difficulty":0,"duration":60,"elapsed":elapsed,"active":elapsed,"credits":credits,"scoring_version":4,"point_fraction":0.3}

func _measurements()->void:
	var record := measured()
	var profile := V2Profiles.from_record(record)
	check(profile.rpm == 4 and profile.p == 0.5 and profile.q == 0.75 and is_equal_approx(profile.c,0.225),"手計算 N4 H2 Q.75 RPM4 P.5 C.225")
	check(V2Profiles.from_record(measured("none",0,0)).is_empty(),"0発はプロフィール不可")
	var miss := V2Profiles.from_record(measured("miss",0,10,0))
	check(miss.p == 0 and miss.c == 0 and miss.q == 0,"全外れも有効、P/C/Q0")
	var all_hit := V2Profiles.from_record(measured("hit",1,10,1,1))
	check(all_hit.p == 1 and all_hit.c == 0.3,"全中心命中")
	check(V2Profiles.from_record(measured("edge",2,10,1,0)).c == 0,"端命中はC0")
	for key in ["interrupted","restored","settings_changed"]:
		var invalid := record.duplicate(true)
		invalid[key] = true
		check(V2Profiles.from_record(invalid).is_empty(),"無効条件 " + key)
	var free := record.duplicate(true)
	free.mode = "free"
	check(V2Profiles.from_record(free).is_empty(),"自由練習禁止")
	var collector := V2Measurement.new()
	collector.begin(2,{},2,"boundary")
	collector.target_event(0.0,"spawn","a",{"position":Vector3(1,2,-11)})
	check(not collector.shot(-0.01,true,1,"a",Vector3.ZERO,Vector3.FORWARD,Vector3.ZERO),"開始前を除外")
	check(collector.shot(59.99,true,1,"a",Vector3.ZERO,Vector3.FORWARD,Vector3.ZERO,9,0),"終端直前の弾を保存")
	collector.target_event(59.99,"destroy","a")
	collector.target_event(59.99,"spawn","b")
	check(not collector.shot(60.0,true,1,"a",Vector3.ZERO,Vector3.FORWARD,Vector3.ZERO,9,1),"60秒境界以後を除外")
	check(collector.snapshot(15).completed == false,"checkpointは未完了")
	var final := collector.completed(60)
	check(final.shots.size() == 1 and final.shots[0].burst_id == 9,"終了途中のバーストを実弾単位で保持")
	check(final.events[1].type == "shot" and final.events[2].type == "destroy" and final.events[3].type == "spawn","同時刻のshot→撃破→出現の順序")
	check(final.target_events[0].state.position == [1.0,2.0,-11.0],"Vector3をJSON配列化")
	for weapon in range(3):
		var basic := V2Profiles.basic(weapon)
		check(basic.timeline.size() == [60,300,180][weapon],"基礎兵士の60秒発射数 %d" % weapon)
		check(float(basic.timeline.back()) < 60,"基礎兵士終端 %d" % weapon)

func _ledger()->void:
	var data := V2Save.defaults()
	var record := ledger_record("one")
	V2Ledger.checkpoint(data,record)
	V2Ledger.checkpoint(data,record)
	check(data.credits == "20" and data.lifetime_credits == "20","checkpoint差分と累計の一意性")
	V2Ledger.finish(data,record,"完了",measured("one"))
	V2Ledger.finish(data,record,"完了",measured("one"))
	check(data.measurement_counts == [1,0,0] and data.credits == "20","結果連打で重複しない")
	for id in ["two","three","four"]:
		V2Ledger.finish(data,ledger_record(id),"完了",measured(id,0,2,0))
	check(data.measurement_counts[0] == 4 and data.armor[0],"不採用・全外れを含む3回防具と4回目")
	var restored := ledger_record("restore",9,30)
	restored.measurement = measured("restore")
	V2Ledger.checkpoint(data,restored)
	V2Ledger.recover(data)
	check(data.measurement_counts[0] == 4 and data.training_history[0].measurement.restored,"復元途中を完了へ格上げしない")
	V2Profiles.adopt(data,measured("adopt-a"))
	V2Profiles.adopt(data,measured("adopt-b"))
	var lifetime := str(data.lifetime_credits)
	for i in range(205):
		V2Ledger.finish(data,ledger_record("history-%d" % i,1),"終了")
	check(data.training_history.size() == 200 and data.profiles[0].record.record_id == "adopt-b" and data.previous_profiles[0].record.record_id == "adopt-a","履歴200超でも採用元と直前を独立保全")
	var before := str(data.credits)
	V2Ledger.finish(data,record,"完了",measured("one"))
	check(data.credits == before and data.measurement_counts[0] == 4,"切捨済IDの再登録も重複しない")
	V2Profiles.revert(data,0)
	V2Profiles.revert(data,0)
	check(data.credits == before and data.measurement_counts[0] == 4,"採用・取消で報酬なし")
	data.credits = "5000"
	data.lifetime_credits = "3000"
	check(V2Profiles.purchase(data,1) and data.credits == "4750" and data.lifetime_credits == "3000" and V2Profiles.squad_level(data) == 3,"購入は累計/兵種を減らさない")
	check(is_equal_approx(V2Profiles.hp(data,0),120) and is_equal_approx(V2Profiles.hp(data,1),110),"測定防具と防護のHP式")
	var locked := V2Save.defaults()
	check(not V2Profiles.purchase(locked,1) and not V2Profiles.set_deployed(locked,2,true),"未解放の購入・配置不可")
	check(BigUInt.compare(str(data.lifetime_credits),lifetime) > 0,"累計は独立文字列")

func _simulation(fps:int, seed_value:int = 123)->Array:
	var data := V2Save.defaults()
	V2Profiles.adopt(data,measured("timeline",0,7,0.6,0.7))
	var sim := V2Combat.new()
	sim.configure(data,seed_value)
	for enemy in sim.state.enemies:
		enemy.hp = 1000000.0
		enemy.damage = 0.0
	var sequence:Array = []
	for frame in range(fps * 121):
		for event in sim.advance(1.0/fps):
			if event.type == "ally_shot":
				sequence.append([snappedf(float(event.time),0.000001),event.actor_id,event.hit,event.critical])
	return sequence

func _combat()->void:
	var sequence30 := _simulation(30)
	check(sequence30 == _simulation(60) and sequence30 == _simulation(120),"30/60/120fpsの発射数・時刻・判定順一致")
	check(sequence30 != _simulation(60,125),"異なるseedは結果が異なる")
	check(sequence30.size() == 15 and is_equal_approx(sequence30[0][0],0.2) and is_equal_approx(sequence30[7][0],60.2),"60秒周期に初発前/末尾の休止を含む")
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var hits := 0
	var crits := 0
	for i in range(100000):
		var outcome := V2Combat.roll(rng,0.6,0.2)
		hits += 1 if outcome.hit else 0
		crits += 1 if outcome.critical else 0
	check(absf(hits/100000.0-0.6) < 0.006 and absf(crits/float(hits)-0.2) < 0.008,"10万試行 P.6 条件付きC.2の統計")
	var data := V2Save.defaults()
	data.lifetime_credits = "3000"
	var sim := V2Combat.new()
	sim.configure(data,3)
	check(sim.state.allies.size() == 3,"武器ごとに1固定枠/最大3人")
	var initial := sim.snapshot()
	check(sim.advance(8).is_empty() and sim.snapshot() == initial,"大deltaは時計も発射も凍結")
	sim.set_paused(true)
	check(sim.advance(0.1).is_empty() and sim.snapshot() == initial,"一時停止で凍結")
	sim.set_paused(false)
	for enemy in sim.state.enemies:
		enemy.hp = 1000000.0
		enemy.damage = 0.0
	for i in range(10):
		sim.advance(0.1)
	var phase := float(sim.state.allies[0].attack_clock)
	V2Profiles.adopt(data,measured("pending",1))
	sim.set_data(data)
	check(sim.state.allies[1].profile.basic,"交戦中の採用は固定")
	for enemy in sim.state.enemies:
		enemy.alive = false
	sim.advance(0.1)
	check(sim.state.status == "marching" and float(sim.state.allies[0].attack_clock) == phase,"敵不在と歩行で時計凍結")
	for i in range(13):
		sim.advance(0.1)
	check(sim.state.section == 1 and not sim.state.allies[1].profile.basic and float(sim.state.allies[1].attack_clock) < 0.31,"次区間で採用反映/差替位相0")
	check(float(sim.state.allies[0].attack_clock) >= phase,"生存し差替えない兵士の位相維持")
	# 区間内に倒れた兵士は次区間で復帰し位相を0へ戻す。
	sim.state.allies[1].alive = false
	sim.state.allies[1].hp = 0.0
	for enemy in sim.state.enemies:
		enemy.alive = false
	sim.advance(0.1)
	for i in range(12):
		sim.advance(0.1)
	check(sim.state.allies[1].alive and float(sim.state.allies[1].attack_clock) < 0.2 and sim.state.allies[1].hp == sim.state.allies[1].max_hp,"区間戦闘不能兵の復帰は全回復/位相0")
	for actor in sim.state.allies:
		actor.alive = false
	sim.advance(0.1)
	check(sim.state.status == "retreat","全滅は手動待ち")
	var retreat := sim.snapshot()
	sim.advance(0.1)
	check(sim.snapshot() == retreat,"自動再挑戦なし")
	sim.retry(data)
	check(sim.state.status == "fighting" and sim.state.allies[0].attack_clock == 0 and sim.state.enemies[0].hp == sim.state.enemies[0].max_hp,"再挑戦で敵全回復・味方位相0")
	# 同時刻の最後の射撃は味方固定枠順が先。撃破された敵の予約射撃は出さない。
	var lethal := V2Save.defaults()
	V2Profiles.adopt(lethal,measured("lethal",0,1,1,0))
	var duel := V2Combat.new()
	duel.configure(lethal,7)
	duel.state.allies[0].hp = 1.0
	duel.state.enemies.resize(1)
	duel.state.enemies[0].hp = 10.0
	duel.state.enemies[0].next_shot = 0.2
	var duel_events := duel.advance(0.2)
	var ally_shots := 0
	var enemy_shots := 0
	for event in duel_events:
		ally_shots += 1 if event.type == "ally_shot" else 0
		enemy_shots += 1 if event.type == "enemy_shot" else 0
	check(ally_shots == 1 and enemy_shots == 0 and duel.state.status == "marching", "同時刻最後の敵撃破で敵射撃/撤退を二重処理しない")
	var base_front := -1
	for scenario in ["basic","low","medium","high","three"]:
		var balance := V2Save.defaults()
		if scenario != "basic":
			V2Profiles.adopt(balance,measured(scenario,0,60,{"low":0.2,"medium":0.6,"high":0.9,"three":0.6}[scenario],0.7))
		if scenario == "three":
			balance.lifetime_credits = "3000"
		var battle := V2Combat.new()
		battle.configure(balance,55)
		for frame in range(60*600):
			battle.advance(1.0/60.0)
			if battle.state.status in ["retreat","complete"]:
				break
		print("BALANCE %s front=%d status=%s time=%.2f" % [scenario,battle.state.section,battle.state.status,battle.state.time])
		if scenario == "basic":
			base_front = int(battle.state.section)
			check(int(battle.state.section) >= 3,"初期基礎兵士で最初の数区間を突破")
	var defense := V2Save.defaults()
	defense.armor[0] = true
	defense.protection[0] = 5
	var protected := V2Combat.new()
	protected.configure(defense,55)
	for frame in range(60*600):
		protected.advance(1.0/60.0)
		if protected.state.status in ["retreat","complete"]:
			break
	print("BALANCE protection5_armor front=%d status=%s time=%.2f" % [protected.state.section,protected.state.status,protected.state.time])
	check(int(protected.state.section) > base_front,"射撃性能を変えず防具/防護で突破余地が増える")

func _write(path:String, value:String)->void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _clean_test_files()->void:
	var directory := DirAccess.open("user://")
	for name in directory.get_files():
		if name.begins_with("save_v"):
			directory.remove(name)

func _storage()->void:
	_clean_test_files()
	_write(V2Save.LEGACY,JSON.stringify({"credits":"99999999","lifetime_credits":"99999999","front":80,"recruit":100,"gear":10,"training_history":[{"id":"legacy"}],"active_training":{"id":"legacy-active"},"settings":{"sensitivity":2.3,"fov":98,"dpi":1600,"volume":0.4,"credits":"555","surprise":true}}))
	var legacy_hash := FileAccess.get_sha256(V2Save.LEGACY)
	for failure in ["backup","settings_read","temp","rename"]:
		V2Save.test_fail_step = failure
		var failed := V2Save.load_data()
		check(failed.get("migration_failed",false) and failed.get("retry_possible",false) and not FileAccess.file_exists(V2Save.PATH),"初回移行の失敗保護 " + failure)
		check(FileAccess.get_sha256(V2Save.LEGACY) == legacy_hash,"旧原本ハッシュ不変 " + failure)
	V2Save.test_fail_step = ""
	var data := V2Save.load_data()
	check(not data.get("migration_failed",false) and data.settings.sensitivity == 2.3 and data.settings.fov == 98,"設定移行と失敗後再試行")
	check(data.credits == "0" and data.lifetime_credits == "0" and data.front == 0 and data.training_history.is_empty() and data.active_training.is_empty(),"旧進行・履歴・途中記録は引継がない")
	check(not data.settings.has("credits") and not data.settings.has("surprise"),"設定allowlistの未知key拒否")
	var safe := V2Save.validate_settings({"sensitivity":"malformed","fov":INF,"dpi":NAN,"volume":-5,"shot_sound":{},"crosshair_outline":"false","crosshair_color":"bad!!"})
	check(safe.sensitivity == 1 and safe.fov == 90 and safe.dpi == 800 and safe.volume == 0 and safe.shot_sound == 0 and safe.crosshair_outline == true,"キー単位の型・有限値検証")
	V2Ledger.finish(data,ledger_record("persist",40),"完了",measured("persist"))
	V2Profiles.adopt(data,measured("persist"))
	check(V2Save.save_data(data),"台帳・採用元記録を同一保存")
	var loaded := V2Save.load_data()
	check(loaded.credits == "40" and loaded.lifetime_credits == "40" and loaded.measurement_counts[0] == 1 and loaded.profiles[0].record.record_id == "persist","JSON再読込で整合性保持")
	var tampered := data.duplicate(true)
	tampered.profiles[0].profile.p = 0.99
	check(not V2Save.save_data(tampered),"元記録と異なる保存プロフィール値を拒否")
	var malformed := data.duplicate(true)
	malformed.profiles[0].record.shots[0].time = {"bad":true}
	check(not V2Save.save_data(malformed),"破損shot型を例外なしに拒否")
	for i in range(201):
		V2Ledger.finish(data,ledger_record("saved-history-%d" % i,1),"終了")
	V2Profiles.adopt(data,measured("persist-second"))
	check(V2Save.save_data(data),"履歴上限後の採用元/直前を保存")
	var trimmed := V2Save.load_data()
	check(trimmed.training_history.size() == 200 and trimmed.profiles[0].record.record_id == "persist-second" and trimmed.previous_profiles[0].record.record_id == "persist","履歴上限後の採用元/直前を再読込")
	var saved_credits := str(data.credits)
	for failure in ["temp","previous","rename"]:
		V2Save.test_fail_step = failure
		var candidate := data.duplicate(true)
		candidate.credits = "999"
		check(not V2Save.save_data(candidate),"更新失敗を返す " + failure)
		V2Save.test_fail_step = ""
		check(V2Save.load_data().credits == saved_credits,"更新失敗で既存セーブ維持 " + failure)
	_write(V2Save.LEGACY,JSON.stringify({"settings":{"sensitivity":8}}))
	check(V2Save.load_data().settings.sensitivity == 2.3,"新セーブ成功後は旧設定を再移行しない")
	_write(V2Save.PATH,"{corrupt")
	var recovered := V2Save.load_data()
	check(not recovered.get("migration_failed",false) and recovered.has("recovery_notice"),"破損原本を別保全しprevious復旧")
	_write(V2Save.PATH,"{corrupt")
	_write(V2Save.PREVIOUS,"{corrupt-too")
	var corrupt := V2Save.load_data()
	check(corrupt.get("migration_failed",false) and not V2Save.save_data(corrupt),"両方破損は上書きせず再試行表示")
	_clean_test_files()
