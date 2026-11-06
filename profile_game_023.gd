extends "res://next_game.gd"

var profile_enabled := false
var timings:Dictionary = {}

func track(key:String, started:int)->void:
	if profile_enabled:
		timings[key] = int(timings.get(key,0)) + Time.get_ticks_usec() - started

func _fire_shot()->void:
	var started := Time.get_ticks_usec()
	super._fire_shot()
	track("shot_us",started)

func _relocate_target(index:int)->void:
	var started := Time.get_ticks_usec()
	super._relocate_target(index)
	track("target_move_us",started)

func _checkpoint_training()->bool:
	var started := Time.get_ticks_usec()
	var okay := super._checkpoint_training()
	track("checkpoint_us",started)
	return okay

func _commit(candidate:Dictionary)->bool:
	var started := Time.get_ticks_usec()
	var okay := await super._commit(candidate)
	track("commit_save_us",started)
	return okay

func _update_progress_ui()->void:
	var started := Time.get_ticks_usec()
	super._update_progress_ui()
	track("notification_ui_us",started)

func _update_hud()->void:
	var started := Time.get_ticks_usec()
	super._update_hud()
	track("hud_us",started)

func _play_shot_sound()->void:
	var started := Time.get_ticks_usec()
	super._play_shot_sound()
	track("audio_shot_us",started)

func _play_hit_sound(combo:int,center_hit:bool=false)->void:
	var started := Time.get_ticks_usec()
	super._play_hit_sound(combo,center_hit)
	track("audio_hit_us",started)

func _process(delta:float)->void:
	var started := Time.get_ticks_usec()
	super._process(delta)
	track("frame_work_us",started)

func _open_pause()->void:
	var started := Time.get_ticks_usec()
	super._open_pause()
	track("pause_menu_checkpoint_us",started)

func _save_current()->bool:
	var started := Time.get_ticks_usec()
	var okay := super._save_current()
	track("save_current_us",started)
	return okay
