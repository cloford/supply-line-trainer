class_name ScoringCapture
extends RefCounted

# 任意の追加領域。過去の整数内訳から推測しない。新たな報酬付与経路ではない。
const VERSION := 1
const FIELDS := ["base_points","center_bonus","speed_bonus","streak_bonus"]
static func snapshot(stats:Dictionary)->Dictionary:
	var result:Dictionary={"version":VERSION,"scoring_version":Balance.SCORING_VERSION}
	for key in FIELDS:result[key]=float(stats.get(key,0.0))
	return result
