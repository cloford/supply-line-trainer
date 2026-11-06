class_name TrainingCatalog
extends RefCounted

const TITLES := ["単発エイム","トラッキング","複数標的エイム","3×3グリッド","弾道・範囲攻撃"]
const DESCRIPTIONS := ["一発ずつ狙いを合わせる","動く標的を追い続ける","3発ずつ狙い、標的を切り替える","9地点を偏りにくく巡り、一つずつ撃破","軌道ガイドを見て着弾と巻き込みを学ぶ"]
const NAMES := Progression.WEAPON_NAMES

# 保存済みの旧解放フラグは残すが、練習の使用条件にはしない。
static func available(id:int)->bool:return id>=0 and id<Balance.WEAPONS.size()
static func safe_index(value:Variant)->int:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:return 0
	if not is_finite(float(value)) or float(value)!=floor(float(value)) or not available(int(value)):return 0
	return int(value)
static func safe_difficulty(value:Variant)->int:
	return clampi(safe_index(value), 0, 2)
static func difficulty_text(weapon:int,difficulty:int)->String:
	if weapon == 3:return "固定3×3地点・同時に標的一つ ／ 兵士には採用できない自由練習"
	if weapon == 4:return "初速16m/s・重力9.8m/s²・爆風半径2.2m ／ 兵士には採用できない自由練習"
	var definition:Dictionary=Balance.DIFFICULTY[safe_difficulty(difficulty)]
	return "標的半径 %.2f m ／ 左右範囲 ±%.1f m ／ %s"%[definition.radius,definition.range,"動きの速さ %.1f"%definition.speed if weapon==1 else "静止標的"]
