class_name PurchaseEffect
extends RefCounted

const DURATION := 2.6

# 実戦と同じDPS、変更直前の同じH。計算は入力・台帳・乱数・保存に触れない。
static func compare(before:Dictionary,after:Dictionary,kind:int,batch:int)->Dictionary:
	var h:=float(before.enemy_hp)
	var d0:=Balance.army_dps(before)
	var d1:=Balance.army_dps(after)
	var result:Dictionary={"front":int(before.front),"hp":h,"kind":kind,"batch":batch,"before_recruit":int(before.recruit),"after_recruit":int(after.recruit),"before_gear":int(before.gear),"after_gear":int(after.gear),"d0":d0,"d1":d1,"valid":false,"t0":0.0,"t1":0.0,"saved_seconds":0.0,"reduction":0.0}
	if not is_finite(h) or h<=0 or not is_finite(d0) or not is_finite(d1) or d0<=0 or d1<=0 or d1<d0:return result
	var t0:=h/d0;var t1:=h/d1
	if not is_finite(t0) or not is_finite(t1):return result
	result.valid=true;result.t0=t0;result.t1=t1;result.saved_seconds=maxf(0.0,t0-t1);result.reduction=clampf(1.0-d0/d1,0.0,1.0)
	return result

static func preview(data:Dictionary,kind:int,batch:int)->Dictionary:
	if kind not in [0,1] or batch not in [1,5,10]:return {}
	var after:=data.duplicate(true)
	var key:String=["recruit","gear"][kind]
	after[key]=int(after[key])+batch
	return compare(data,after,kind,batch)

static func reduction_text(effect:Dictionary)->String:
	if not bool(effect.get("valid",false)):return "突破時間の比較なし"
	var percent:=float(effect.reduction)*100.0
	if percent==0:return "突破時間の短縮なし"
	return "突破時間 約%s短縮"%("0.1%未満" if percent<0.1 else "%.1f%%"%percent)

static func seconds_text(seconds:float)->String:
	if not is_finite(seconds) or seconds<0:return "—"
	return "1秒未満" if seconds<1 else "%.1f秒"%seconds

static func presentation(effect:Dictionary,current_front:int)->Dictionary:
	if effect.is_empty():return {}
	var title:="増員 %d人 → %d人"%[Balance.soldier_count(int(effect.before_recruit)),Balance.soldier_count(int(effect.after_recruit))] if int(effect.kind)==0 else "部隊装備 Lv.%d → Lv.%d"%[int(effect.before_gear),int(effect.after_gear)]
	var model:Dictionary={"title":"購入前後の比較："+title+"（×%d）"%int(effect.batch),"headline":"この購入で"+reduction_text(effect),"timing":"","detail":""}
	if bool(effect.valid):
		model.detail="購入時の戦線%d・同じ敵残耐久で比較。DPS %.4f → %.4f。現在の突破見込み時間とは別の参考値です。"%[int(effect.front)+1,float(effect.d0),float(effect.d1)]
		if int(effect.front)==current_front:model.timing="購入時の同じ敵なら 約%s → 約%s（%s短縮）"%[seconds_text(float(effect.t0)),seconds_text(float(effect.t1)),seconds_text(float(effect.saved_seconds))]
	return model
