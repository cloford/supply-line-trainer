extends SceneTree
const Analysis=preload("res://reward_analysis.gd")
var failures:Array[String]=[]
class ReplayTrainer extends "res://main.gd":
	var replay_q:=1.0
	var replay_hit:=true
	func _ray_hit()->Dictionary:
		return {"index":0,"q":replay_q,"precision":pow(replay_q,1.5)} if replay_hit else {}

func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _init()->void:call_deferred("_run")
func _run()->void:
	check(Balance.SCORING_VERSION==4 and ShootingMetrics.VERSION==1 and ShootingMetrics.RULES_VERSION==1,"unchanged rules versions were bumped")
	check(not is_equal_approx((pow(0.0,1.5)+pow(1.0,1.5))/2.0,pow(0.5,1.5)),"average q must not reconstruct per-hit scoring")
	for weapon in 3:
		for difficulty in 3:
			for candidate in 3:
				var previous:=-1.0
				for q in [0.0,0.1,0.25,0.5,0.75,1.0]:
					var s:Dictionary={"base_points":1000.0,"center_bonus":1000.0*pow(q,1.5),"speed_bonus":99.0,"streak_bonus":99.0,"shots":30,"hits":30,"fire_time":10.0,"track_time":10.0}
					var result:Dictionary=Analysis.evaluate(weapon,difficulty,s,candidate)
					check(is_finite(result.exact_points) and result.exact_points>=previous and result.score>=0,"finite/nonnegative/center monotonicity")
					check(result.score==result.base+result.center+result.speed+result.streak,"component sum")
					previous=result.exact_points
				var idle:Dictionary={"base_points":0.0,"center_bonus":0.0,"speed_bonus":0.0,"streak_bonus":0.0}
				check(Analysis.evaluate(weapon,difficulty,idle,candidate).score==0,"idle/miss earned points")
	# 同じ総採点前集計を分けても丸め利益を作らない。台帳の頻度も変える。
	for sessions in [1,4,40]:
		for frequency in [1,7,15]:
			var data:=SaveManager.defaults();data.credits="12345678901234567890";data.credit_fraction=0.375
			for session in sessions:
				var carry:float=data.credit_fraction
				for tick in range(1,31):
					var fraction:float=float(tick)/30.0/sessions
					var raw:Dictionary={"base_points":1000*fraction,"center_bonus":500*fraction,"speed_bonus":80*fraction,"streak_bonus":20*fraction}
					var result:=Balance.score_and_reward(0,0,raw,0,0,120.0/sessions,carry)
					var record:Dictionary={"id":"s%d"%session,"elapsed":120.0*fraction,"active":100.0*fraction,"duration":0,"score":result.score,"credits":result.supply,"point_fraction":result.fraction,"scoring_version":4,"scoring_raw":ScoringCapture.snapshot(raw)}
					if tick%frequency==0:TrainingLedger.checkpoint(data,record);TrainingLedger.checkpoint(data,record)
					if tick==30:TrainingLedger.finish(data,record,"終了");TrainingLedger.finish(data,record,"終了")
			var expected:=Balance.score_and_reward(0,0,{"base_points":1000.0,"center_bonus":500.0,"speed_bonus":80.0,"streak_bonus":20.0},0,0,120,0.375)
			check(data.credits==BigUInt.add("12345678901234567890",str(expected.score)) and is_equal_approx(data.credit_fraction,expected.fraction),"split/checkpoint frequency changed points or large balance")
	# 実際の訓練処理へ固定したレイ結果を再生。物理操作試験とは区別する。
	var game:=ReplayTrainer.new();game.is_test_mode=true;root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game.data.unlocked=[true,true,true];game.data.settings.shot_sound=3;game.data.settings.hit_sound=3
	game.selected_weapon=2;game._start_training();game._process(3.1)
	game._fire_shot();game._fire_shot();var partial:Dictionary=game._training_result()
	check(game.stats.kills==0 and game.stats.shots==2 and game.shooting_metrics.q_sum==2,"burst partial actual facts")
	game._fire_shot();check(game.stats.kills==1 and game.shooting_metrics.q_sum==3 and game._training_result().score>partial.score,"burst kill reward/q independent")
	game.training_elapsed=10;game._finish_training(false);check(game.data.training_history[0].scoring_raw.base_points==65,"preweight raw missing from normal record")
	var outputs:Array=[]
	for hz in [60,120]:
		game.selected_weapon=1;game._start_training();game._process(3.1);game.mouse_blocked=false;Input.action_press("shoot")
		for frame in hz*6:
			game.replay_q=0.7;game.replay_hit=frame<hz*3;game.training_elapsed+=1.0/hz;game._process_weapon(1.0/hz)
		Input.action_release("shoot");outputs.append({"points":game._training_result().exact_points,"values":ShootingMetrics.values(ShootingMetrics.snapshot(game.shooting_metrics,game.stats,game.training_elapsed),1)})
	check(absf(outputs[0].points-outputs[1].points)<0.02,"auto frame integration diverged")
	check(is_equal_approx(outputs[0].values[0],outputs[1].values[0]) and is_equal_approx(outputs[0].values[1],outputs[1].values[1]),"metrics changed across Hz")
	game.queue_free();for frame in 4:await process_frame
	if failures.is_empty():print("REWARD_TEST_OK: current+2 candidates, monotonicity, miss/idle, split/checkpoint/rounding, big balances, burst raw, 60/120Hz replay");quit(0)
	else:
		for message in failures:push_error(message)
		quit(1)
