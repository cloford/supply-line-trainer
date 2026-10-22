class_name ShootingMetrics
extends RefCounted

# 採点とは独立した射撃事実。閾値は極端に短い記録を除くためだけに使う。
const VERSION := 1
const RULES_VERSION := 1
const MIN_ELAPSED := 10.0
const MIN_SHOTS := 10
const MIN_FIRE_TIME := 3.0
const MAX_BASELINE := 3
const RAW_FIELDS := ["elapsed","shots","hits","kills","fire_time","track_time","q_sum","q_time"]
const EXPLANATION := "中心への近さは外れも含む射線と中心の距離の指標で、命中率とは異なります。自由移動・標的配置・訓練の長さによる疲労やばらつきは除去していません。上達の確定判定ではありません。"

static func setting_key(weapon:int,difficulty:int,settings:Dictionary)->String:
	return "%d|%d|%d|%d|%d|%d"%[weapon,difficulty,roundi(float(settings.fov)*10000.0),roundi(Balance.effective_coefficient(int(settings.sensitivity_game))*float(settings.sensitivity)*100000000.0),VERSION,RULES_VERSION]

static func begin(weapon:int,difficulty:int,settings:Dictionary,intention:String,order:int)->Dictionary:
	return {"metrics_version":VERSION,"training_rules_version":RULES_VERSION,"setting_key":setting_key(weapon,difficulty,settings),"fov":float(settings.fov),"effective_sensitivity":Balance.effective_coefficient(int(settings.sensitivity_game))*float(settings.sensitivity),"order":order,"intention":intention,"settings_changed":false,"complete":false,"comparison_eligible":false,"comparison_reason":"中断・未確定の記録のため比較なし","q_sum":0.0,"q_time":0.0}

static func bullet(metrics:Dictionary,q:float)->void:
	metrics.q_sum=float(metrics.q_sum)+clampf(q,0.0,1.0)

static func tracking(metrics:Dictionary,q:float,delta:float)->void:
	metrics.q_time=float(metrics.q_time)+clampf(q,0.0,1.0)*maxf(0.0,delta)

static func snapshot(metrics:Dictionary,stats:Dictionary,elapsed:float)->Dictionary:
	var raw:=metrics.duplicate(true)
	raw.elapsed=elapsed
	for key in ["shots","hits","kills","fire_time","track_time"]:raw[key]=stats.get(key,0)
	return raw

static func complete_raw(record:Dictionary)->bool:
	var raw=record.get("metrics",{})
	if typeof(raw)!=TYPE_DICTIONARY or raw.is_empty():return false
	for key in RAW_FIELDS:
		if not raw.has(key) or typeof(raw[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(raw[key])) or float(raw[key])<0:return false
	for key in ["metrics_version","training_rules_version","setting_key","order","intention","settings_changed","complete","fov","effective_sensitivity"]:
		if not raw.has(key):return false
	for key in ["metrics_version","training_rules_version","order","fov","effective_sensitivity"]:
		if typeof(raw[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(raw[key])):return false
	if typeof(raw.setting_key)!=TYPE_STRING or str(raw.setting_key).is_empty():return false
	if not is_finite(float(raw.fov)) or not is_finite(float(raw.effective_sensitivity)):return false
	return float(raw.hits)<=float(raw.shots) and float(raw.kills)<=float(raw.hits) and float(raw.track_time)<=float(raw.fire_time)+0.0001 and float(raw.fire_time)<=float(raw.elapsed)+0.0001 and float(raw.q_sum)<=float(raw.shots)+0.0001 and float(raw.q_time)<=float(raw.fire_time)+0.0001

static func reason(record:Dictionary)->String:
	if not complete_raw(record):return "比較データなし"
	var raw:Dictionary=record.metrics
	if int(raw.metrics_version)!=VERSION or int(raw.training_rules_version)!=RULES_VERSION:return "計測仕様が異なるため比較なし"
	if str(record.get("status",""))!="終了" or not bool(raw.complete):return "中断・未確定の記録のため比較なし"
	if bool(raw.settings_changed):return "訓練中に設定を変更したため比較なし"
	if float(raw.elapsed)<MIN_ELAPSED or (float(raw.fire_time)<MIN_FIRE_TIME if int(record.weapon)==1 else int(raw.shots)<MIN_SHOTS):return "短い記録のため比較なし"
	return ""

# 終了時の基準集計を保存し、履歴200件の切り捨て後も当時の比較を再現する。
# この関数は入力履歴・現在記録・射撃や報酬を変更しない。
static func comparison(record:Dictionary,history:Array)->Dictionary:
	var excluded:=reason(record)
	var result:Dictionary={"metrics_version":VERSION,"reason":excluded,"count":0,"ids":[],"totals":{}}
	if not excluded.is_empty():return result
	var candidates:Array[Dictionary]=[]
	var seen:Dictionary={str(record.get("id","")):true}
	for value in history:
		if typeof(value)!=TYPE_DICTIONARY:continue
		var entry:Dictionary=value
		var id:=str(entry.get("id",""))
		if id.is_empty() or seen.has(id):continue
		seen[id]=true
		if not reason(entry).is_empty():continue
		if entry.metrics.setting_key!=record.metrics.setting_key or int(entry.metrics.order)>=int(record.metrics.order):continue
		candidates.append(entry)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.metrics.order)>int(b.metrics.order))
	var totals:Dictionary={}
	for key in RAW_FIELDS:totals[key]=0.0
	for index in mini(MAX_BASELINE,candidates.size()):
		var entry:Dictionary=candidates[index]
		result.ids.append(str(entry.id))
		for key in RAW_FIELDS:totals[key]+=float(entry.metrics[key])
	result.count=result.ids.size();result.totals=totals
	return result

static func values(raw:Dictionary,weapon:int)->Array:
	var denominator:=float(raw.fire_time) if weapon==1 else float(raw.shots)
	var numerator:=float(raw.q_time) if weapon==1 else float(raw.q_sum)
	var center:Variant=numerator/denominator*100.0 if denominator>0 else null
	var secondary:Variant=null
	if float(raw.elapsed)>0:secondary=float(raw.track_time)/float(raw.elapsed)*100.0 if weapon==1 else float(raw.kills)/float(raw.elapsed)*60.0
	return [center,secondary]

static func _difference(value:float,baseline:float,percent:bool)->String:
	var difference:=roundi(value-baseline) if percent else roundi((value-baseline)*10.0)
	if difference==0:return "ほぼ同じ"
	return ("%+dポイント"%difference) if percent else ("%+.1f体/分"%(float(difference)/10.0))

# 表示データの作成も一か所。UIには計測・基準選択・計算式を持たせない。
static func presentation(record:Dictionary)->Dictionary:
	var model:Dictionary={"title":"%s　%s / %s　%s"%[str(record.get("started","")),Balance.WEAPONS[clampi(int(record.get("weapon",0)),0,2)],Balance.DIFFICULTY[clampi(int(record.get("difficulty",0)),0,2)].name,str(record.get("status",""))],"heading":"同じ設定での参考比較","lines":[],"note":"比較データなし","conditions":"","explanation":EXPLANATION}
	if not complete_raw(record):return model
	var raw:Dictionary=record.metrics
	if int(raw.metrics_version)!=VERSION:
		model.note="計測仕様が異なるため比較データなし";return model
	var weapon:=int(record.weapon)
	var current:=values(raw,weapon)
	var saved:Dictionary=record.get("shooting_comparison",{}) if typeof(record.get("shooting_comparison",{}))==TYPE_DICTIONARY else {}
	var count:=int(saved.get("count",0))
	var baseline:Array=[]
	var valid_totals:=typeof(saved.get("totals"))==TYPE_DICTIONARY
	if valid_totals:
		for key in RAW_FIELDS:
			if not saved.totals.has(key) or typeof(saved.totals[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(saved.totals[key])) or float(saved.totals[key])<0:valid_totals=false;break
	if reason(record).is_empty() and count>0 and count<=MAX_BASELINE and valid_totals and int(saved.get("metrics_version",0))==VERSION:
		baseline=values(saved.totals,weapon)
	var names:=["中心への近さ","有効追従" if weapon==1 else "標的処理ペース"]
	for index in 2:
		var value:Variant=current[index]
		var percent:=index==0 or weapon==1
		var text:String=names[index]+"　—" if value==null else names[index]+("　%d / 100"%roundi(value) if index==0 else ("　%d%%"%roundi(value) if percent else "　%.1f体/分"%value))
		if not baseline.is_empty() and value!=null and baseline[index]!=null:text+="　過去%d回より %s"%[count,_difference(value,baseline[index],percent)]
		model.lines.append(text)
	var excluded:=reason(record)
	model.note=excluded if not excluded.is_empty() else ("今回の記録を次回から比較に使います" if count==0 and not saved.is_empty() else ("直近の過去%d回を発射数・時間で加重した基準"%count if not baseline.is_empty() else "当時の比較情報がありません"))
	model.conditions="計測 %s　実発射 %d　命中 %d　撃破 %d\n射撃 %.1f秒　命中追従 %.1f秒\nFOV %.1f　実効感度 %.8f°/count　計測v%d / ルールv%d\n意識項目：%s"%[Balance.clock_text(float(raw.elapsed)),int(raw.shots),int(raw.hits),int(raw.kills),float(raw.fire_time),float(raw.track_time),float(raw.fov),float(raw.effective_sensitivity),int(raw.metrics_version),int(raw.training_rules_version),str(raw.intention)]
	model.explanation=("有効追従は計測時間全体に対する命中追従の割合です。従来の追従率（射撃時間が分母）とは異なります。" if weapon==1 else "標的処理ペースは撃破数÷計測時間×60で、反応速度ではありません。")+"\n"+EXPLANATION
	return model
