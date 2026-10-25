class_name V2Rules
extends RefCounted

const SAVE_VERSION := 2
const MEASUREMENT_VERSION := 1
const PROFILE_VERSION := 1
const DURATION := 60.0
const COUNTDOWN := 3.0
const WEAPON_IDS := ["handgun", "auto_rifle", "burst_rifle"]
const WEAPON_NAMES := ["ハンドガン", "アサルトライフル", "バーストライフル"]
const CRITICAL_SCALE := 0.30
const CRITICAL_MULTIPLIER := 1.5
const BASE_HP := 100.0
const DAMAGE := [10.0, 2.0, 4.0]
const ARMOR_BONUS := 0.20
const PROTECTION_BONUS := 0.10
const PROTECTION_COSTS := [250, 500, 900, 1400, 2000]
const UNLOCK_CREDITS := ["0", "1000", "3000"]
const HISTORY_LIMIT := 200
const MAX_FRAME_DELTA := 0.25
const MARCH_SECONDS := 1.2
const FIRST_EXPEDITION := 12
const MAX_COMBAT_ENEMIES := 12
const CONTINUATION_MAX_HEAVY := 8
const CONTINUATION_HEAVY_EVERY := 3
const FLAVOR_MIN_SHOTS := 10
const FLAVOR_STABLE_CV := 0.20
const FLAVOR_BURST_CV := 0.90
const FLAVOR_CAREFUL_Q := 0.80
const FLAVOR_CAREFUL_MAX_SHOTS := 90
const FLAVOR_HIGH_SHOTS := 240
const MEASUREMENT_CONDITIONS := {"radius":0.42, "distance":11.0, "distance_z":-11.0, "player_origin":[0.0,1.6,0.0], "range":3.8, "speed":1.8, "fixed_position":true, "auto_interval":0.1, "burst_interval":0.085, "burst_count":3, "near_fraction":0.5, "near_min":1.2, "near_max":3.0, "far_min":3.0, "far_max":6.5, "seed_rule":"rng-seeded-balanced-near-far-v1"}

static func valid_weapon(weapon:int)->bool:
	return weapon >= 0 and weapon < 3

static func enemy_group(section:int)->Array[Dictionary]:
	# 初期3区間は基礎ハンドガンでも体験可能。以後は数と混成で負荷を増す。
	var groups := [[2,0],[3,0],[4,0],[3,1],[5,1],[4,2],[7,1],[6,2],[5,3],[8,2],[7,3],[8,4]]
	var index := clampi(section, 0, 11)
	var composition:Array = groups[index]
	var extra := maxi(0, section - 11)
	if section >= FIRST_EXPEDITION:
		var heavy := mini(CONTINUATION_MAX_HEAVY, 4 + (section - FIRST_EXPEDITION) / CONTINUATION_HEAVY_EVERY)
		composition = [MAX_COMBAT_ENEMIES - heavy, heavy]
	var result:Array[Dictionary] = []
	for i in range(int(composition[0])):
		result.append({"kind":"light", "max_hp":10.0, "damage":3.0 + mini(extra,10), "interval":2.8})
	for i in range(int(composition[1])):
		result.append({"kind":"heavy", "max_hp":50.0, "damage":7.0 + mini(extra,10), "interval":3.4})
	return result
