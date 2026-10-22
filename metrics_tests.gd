extends SceneTree

var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func fixture(id:int,weapon:int=0,seconds:float=10,shots:int=10,q:float=5.0)->Dictionary:
	var m:=ShootingMetrics.begin(weapon,0,SaveManager.default_settings(),"指定なし",id)
	m.merge({"elapsed":seconds,"shots":shots,"hits":shots,"kills":shots if weapon!=1 else 0,"fire_time":minf(3,seconds),"track_time":minf(1.5,seconds),"q_sum":q,"q_time":minf(1.5,seconds),"complete":true},true)
	return {"id":str(id),"weapon":weapon,"difficulty":0,"status":"終了","metrics":m,"elapsed":seconds,"active":0.0,"duration":0,"credits":0,"point_fraction":0.0}
func _init()->void:
	for radius in [0.18,0.4,1.0]:
		for distance in [0.0,0.1,0.5,1.0,1.2]:
			var center:=Vector3(distance*radius,0,-10)
			var q:=Balance.center_quality(Vector3.ZERO,Vector3.FORWARD,center,radius)
			check(is_equal_approx(q,clampf(1-distance,0,1)),"ray normalized distance")
			check(is_equal_approx(Balance.center_precision(Vector3.ZERO,Vector3.FORWARD,center,radius),pow(q,1.5)),"original score precision changed")
	var now:=fixture(20)
	check(ShootingMetrics.values(fixture(1,0,10,10,10).metrics,0)[0]==100,"all center")
	check(ShootingMetrics.values(fixture(1,0,10,10,0).metrics,0)[0]==0,"all miss")
	check(ShootingMetrics.values(now.metrics,0)[0]==50,"mixed center and miss")
	var empty:=fixture(1,0,0,0,0)
	check(ShootingMetrics.values(empty.metrics,0)==[null,null],"zero denominator")
	for count in 5:
		var history:Array=[]
		for index in count:history.append(fixture(index+1))
		var comparison:=ShootingMetrics.comparison(now,history)
		check(comparison.count==mini(count,3),"baseline count %d"%count)
		if count>3:check(comparison.ids==["4","3","2"],"not latest three")
	var short:=fixture(1,0,9.999)
	check(ShootingMetrics.reason(short).contains("短い"),"10 second boundary")
	short=fixture(1,0,10,9);check(ShootingMetrics.reason(short).contains("短い"),"10 bullet boundary")
	short=fixture(1,1);short.metrics.fire_time=2.999;short.metrics.track_time=1.0;short.metrics.q_time=1.0
	check(ShootingMetrics.reason(short).contains("短い"),"3 fire second boundary")
	check(ShootingMetrics.reason(fixture(1,1)).is_empty(),"auto exact threshold")
	var previous:=fixture(1,0,10,10,10)
	var long:=fixture(2,0,30,30,0)
	var history:Array=[previous,long,previous,now,fixture(30),fixture(3,1)]
	var comp:=ShootingMetrics.comparison(now,history)
	check(comp.ids==["2","1"] and is_equal_approx(ShootingMetrics.values(comp.totals,0)[0],25.0),"weighted not mean, duplicate/current/future/weapon exclusions")
	for property in ["metrics_version","training_rules_version","setting_key","settings_changed","complete","q_sum"]:
		var other:=previous.duplicate(true)
		match property:
			"setting_key":other.metrics[property]="different"
			"settings_changed":other.metrics[property]=true
			"complete":other.metrics[property]=false
			"q_sum":other.metrics.erase(property)
			_:other.metrics[property]=99
		check(ShootingMetrics.comparison(now,[other]).count==0,"invalid exclusion "+property)
	var recovered:=previous.duplicate(true);recovered.status="中断復元"
	check(ShootingMetrics.comparison(now,[recovered]).count==0,"recovery included")
	check(ShootingMetrics.presentation({}).note=="比較データなし","legacy guessed metrics")
	var settings:=SaveManager.default_settings();var equivalent:=settings.duplicate(true)
	equivalent.sensitivity=1.0+0.000000001
	check(ShootingMetrics.setting_key(0,0,settings)==ShootingMetrics.setting_key(0,0,equivalent),"float normalization")
	equivalent.sensitivity_game=1;equivalent.sensitivity=Balance.effective_coefficient(0)/Balance.effective_coefficient(1)
	check(ShootingMetrics.setting_key(0,0,settings)==ShootingMetrics.setting_key(0,0,equivalent),"equivalent preset coefficients split baseline")
	for key in ["fov","sensitivity"]:
		var changed:=settings.duplicate(true);changed[key]+=1
		check(ShootingMetrics.setting_key(0,0,settings)!=ShootingMetrics.setting_key(0,0,changed),"settings key "+key)
	check(ShootingMetrics.setting_key(0,0,settings)!=ShootingMetrics.setting_key(0,1,settings),"difficulty key")
	var auto_values:Array=[]
	for hz in [60,120]:
		var raw:=ShootingMetrics.begin(1,0,settings,"指定なし",1)
		for step in hz*6:ShootingMetrics.tracking(raw,0.7 if step<hz*3 else 0.0,1.0/hz)
		raw.fire_time=6;raw.elapsed=10;raw.track_time=3
		auto_values.append(ShootingMetrics.values(raw,1))
	check(is_equal_approx(auto_values[0][0],auto_values[1][0]) and is_equal_approx(auto_values[0][0],35) and auto_values[0][1]==30,"auto time weighting 60/120Hz")
	var selective:=fixture(1,1,20);selective.metrics.fire_time=3;selective.metrics.q_time=3;selective.metrics.track_time=3
	var continuous:=fixture(2,1,20);continuous.metrics.fire_time=20;continuous.metrics.q_time=12;continuous.metrics.track_time=12
	check(ShootingMetrics.values(selective.metrics,1)==[100.0,15.0] and ShootingMetrics.values(continuous.metrics,1)==[60.0,60.0],"selective versus continuous distinction")
	now.shooting_comparison=comp
	var before:=ShootingMetrics.presentation(now)
	var round_trip:Dictionary=JSON.parse_string(JSON.stringify(now))
	check(ShootingMetrics.presentation(round_trip)==before,"saved baseline changed after reload/trim")
	check(ShootingMetrics._difference(50.1,50.0,true)=="ほぼ同じ" and ShootingMetrics._difference(10.01,10,false)=="ほぼ同じ","tiny differences exaggerated")
	var data:=SaveManager.defaults()
	TrainingLedger.checkpoint(data,now);TrainingLedger.checkpoint(data,now)
	TrainingLedger.finish(data,now,"終了");TrainingLedger.finish(data,now,"終了")
	check(data.training_history.size()==1 and data.practice_totals.sessions==1 and data.practice_totals.elapsed==10 and data.training_history[0].metrics.q_sum==5,"metrics checkpoint duplicated")
	TrainingLedger.checkpoint(data,fixture(21));TrainingLedger.recover(data)
	check(not ShootingMetrics.reason(data.training_history[0]).is_empty() and data.training_history[0].metrics.q_sum==5,"recovery facts/exclusion")
	if failures.is_empty():print("METRICS_TEST_OK: geometry, zero/miss/mix, thresholds, weighted history, versions, time integral, snapshot and ledger");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
