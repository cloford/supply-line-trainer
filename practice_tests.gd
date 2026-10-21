extends SceneTree

var failures:Array[String]=[]

func check(condition:bool,message:String)->void:
	if not condition:failures.append(message)

func fixture(id:String,elapsed:float,result:Dictionary)->Dictionary:
	return {"id":id,"started":"2026-10-22 12:00:00","weapon":0,"difficulty":0,"duration":0,"elapsed":elapsed,"active":elapsed*0.5,"score":result.score,"credits":result.supply,"point_fraction":result.fraction,"accuracy":result.accuracy,"base":result.base,"center":result.center,"speed":result.speed,"streak":result.streak,"scoring_version":4}

func _init()->void:
	check(Balance.TRAINING_DURATIONS==[0],"timed training remains selectable")
	check(is_equal_approx(Balance.center_precision(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-10),1),1.0),"center ray not full precision")
	check(Balance.center_precision(Vector3.ZERO,Vector3.FORWARD,Vector3(0.9,0,-10),1)<0.04,"edge ray too precise")
	for weapon in 3:
		for difficulty in 3:
			check(Balance.score_and_reward(weapon,difficulty,{},0,0,36000,0.9).score==0,"idle gained points")
			for amount in [0.01,1.0,9.5,45.0,1000.0]:
				var stats:Dictionary={"base_points":amount,"center_bonus":amount*9,"speed_bonus":amount*100,"streak_bonus":amount*100}
				var result:=Balance.score_and_reward(weapon,difficulty,stats,0,0,1.0,0.99)
				check(result.score==result.supply and result.score==int(floor(result.exact_points+0.99+0.000000001)),"points must equal cumulative floor")
				check(result.score==result.base+result.center+result.speed+result.streak,"integer component sum")
				check(result.center<=result.base and result.speed+result.streak<=floor(result.base*0.2),"integer cap exceeded")
			var sample:Dictionary={"base_points":1000.0,"center_bonus":730.0,"speed_bonus":90.0,"streak_bonus":45.0}
			var expected:=int(floor(1865.0*Balance.POINT_WEIGHTS[weapon]*float(Balance.DIFFICULTY[difficulty].reward)+0.000000001))
			check(Balance.score_and_reward(weapon,difficulty,sample,0,0,1).score==expected,"weapon point weighting changed")
	# 端数をセッション間で保持し、チェックポイントと復元の再実行では加算しない。
	var data:=SaveManager.defaults()
	for index in 100:
		var start_fraction:=float(data.credit_fraction)
		var first:=Balance.score_and_reward(0,0,{"base_points":0.5},0,0,0.5,start_fraction)
		TrainingLedger.checkpoint(data,fixture("split_%d"%index,0.5,first))
		TrainingLedger.checkpoint(data,fixture("split_%d"%index,0.5,first))
		var result:=Balance.score_and_reward(0,0,{"base_points":1.0},0,0,1.0,start_fraction)
		var record:=fixture("split_%d"%index,1.0,result)
		TrainingLedger.finish(data,record,"終了")
		TrainingLedger.finish(data,record,"終了")
	var combined:=Balance.score_and_reward(0,0,{"base_points":100.0},0,0,100)
	check(data.credits==str(combined.score) and is_equal_approx(float(data.credit_fraction),float(combined.fraction)),"short sessions lost or created points")
	check(data.practice_totals.sessions==100 and data.practice_totals.elapsed==100.0 and data.practice_totals.active==50.0,"checkpoint duplicated totals")
	var pending:=Balance.score_and_reward(0,0,{"base_points":45.0},0,0,3,float(data.credit_fraction))
	TrainingLedger.checkpoint(data,fixture("recover",3,pending))
	var earned:String=data.credits;var fraction:float=data.credit_fraction
	check(TrainingLedger.recover(data) and not TrainingLedger.recover(data),"pending recovery not idempotent")
	check(data.credits==earned and data.credit_fraction==fraction and data.practice_totals.sessions==101,"recovery reawarded points")
	TrainingLedger.finish(data,fixture("zero",0,combined),"終了")
	check(data.practice_totals.sessions==101,"countdown counted as practice")
	for index in 205:TrainingLedger.finish(data,fixture("history_%d"%index,1,Balance.score_and_reward(0,0,{},0,0,1)),"終了")
	check(data.training_history.size()==200 and data.practice_totals.sessions==306 and data.practice_totals.elapsed==308.0,"history trimming lost totals")
	if failures.is_empty():print("PRACTICE_TEST_OK: economy, cumulative rounding, integer caps, checkpoint/recovery, history totals");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
