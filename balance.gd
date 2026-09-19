class_name Balance
extends RefCounted

const TRAINING_SECONDS := 60.0
const DIFFICULTY := [
	{"name":"初級", "radius":0.62, "speed":2.3, "range":5.0, "reward":1.0},
	{"name":"中級", "radius":0.46, "speed":3.4, "range":6.5, "reward":1.08},
	{"name":"上級", "radius":0.34, "speed":4.6, "range":8.0, "reward":1.16}
]
const WEAPONS := ["ハンドガン", "オートライフル", "バーストライフル"]
const FRONT_HP := [70.0, 110.0, 165.0, 240.0, 340.0, 470.0, 640.0, 850.0, 1100.0, 1400.0, 1760.0, 2180.0]
const FRONT_NAMES := ["外縁ゲート", "通信塔", "資材集積所", "峡谷監視所", "中継基地", "防空陣地", "軌道倉庫", "精製区画", "中央要塞", "司令区画", "最終防壁", "中枢制圧"]
const SCORE_BASE := [22.0, 22.0, 26.0]

static func recruit_cost(level:int)->int: return int(round(85.0 * pow(1.48, level)))
static func gear_cost(level:int)->int: return int(round(110.0 * pow(1.56, level)))
static func depot_cost(level:int)->int: return int(round(140.0 * pow(1.62, level)))
static func soldiers(level:int)->int: return 6 + level * 2
static func gear_multiplier(level:int)->float: return 1.0 + level * 0.22
static func combat_power(recruit:int, gear:int)->float: return soldiers(recruit) * gear_multiplier(gear)
static func passive_rate(depot:int)->float: return 0.08 + depot * 0.12
static func offline_cap(front:int)->float: return 150.0 + min(front, 11) * 28.0
static func visual_tier(level:int)->int:
	if level >= 5: return 2
	if level >= 2: return 1
	return 0

static func score_and_reward(weapon:int, difficulty:int, stats:Dictionary, front:int)->Dictionary:
	var main := 0.0
	var accuracy := 0.0
	if weapon == 0:
		main = float(stats.kills)
		accuracy = float(stats.hits) / max(1.0, float(stats.shots))
	elif weapon == 1:
		main = float(stats.track_time)
		accuracy = float(stats.track_time) / max(0.001, float(stats.fire_time))
	else:
		main = float(stats.kills) + float(stats.hits) * 0.22
		accuracy = float(stats.hits) / max(1.0, float(stats.shots))
	var normalized:float = main / float(SCORE_BASE[weapon])
	var score:int = int(round(1000.0 * normalized * (0.78 + 0.22 * accuracy)))
	var supply:int = int(round((38.0 + 72.0 * normalized) * (0.82 + 0.18 * accuracy) * float(DIFFICULTY[difficulty].reward) * (1.0 + mini(front, 11) * 0.025)))
	return {"score":max(0, score), "supply":max(0, supply), "accuracy":accuracy}
