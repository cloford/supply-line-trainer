class_name V2SaveWorker
extends RefCounted

# 履歴と採用記録は射撃中に変化しない。開始前に複製しworkerだけへ渡す。
# mainはarchivesを参照せず、変更する操作はjoin後にcacheを作り直す。
const ARCHIVE_KEYS := ["training_history", "profiles", "previous_profiles"]
var _archives:Dictionary = {}
var _thread:Thread
var requested := 0
var durable := 0
var running_revision := 0
var last_dispatch_frame := -1
var retry_after := 0.0
var requests := 0
var writes := 0
var last_snapshot_us := 0
var last_write_us := 0
var error := ""
var _configured := false

func configure(data:Dictionary)->void:
	finish()
	_archives = {}
	for key in ARCHIVE_KEYS:
		_archives[key] = data[key].duplicate(true)
	_configured = true

func request()->void:
	requested += 1
	requests += 1

func pending()->bool:
	return requested > durable

func poll()->void:
	if not _thread or _thread.is_alive():
		return
	var result:Dictionary = _thread.wait_to_finish()
	_thread = null
	last_write_us = int(result.usec)
	error = str(result.error)
	if bool(result.okay):
		durable = running_revision
	else:
		retry_after = Time.get_ticks_msec() / 1000.0 + 1.0

func dispatch(data:Dictionary)->void:
	poll()
	var frame := Engine.get_process_frames()
	if _thread or not pending() or frame == last_dispatch_frame or Time.get_ticks_msec() / 1000.0 < retry_after:
		return
	if not _configured:
		configure(data)
	var started := Time.get_ticks_usec()
	var snapshot:Dictionary = {}
	for key in data:
		if key in ARCHIVE_KEYS:
			continue
		var value:Variant = data[key]
		snapshot[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	last_snapshot_us = Time.get_ticks_usec() - started
	running_revision = requested
	last_dispatch_frame = frame
	_thread = Thread.new()
	var status := _thread.start(_write.bind(snapshot))
	if status != OK:
		_thread = null
		error = "保存用処理を開始できません。再試行します。"
		retry_after = Time.get_ticks_msec() / 1000.0 + 1.0
	else:
		writes += 1

func _write(snapshot:Dictionary)->Dictionary:
	# snapshotもarchivesもworker専有。SceneTree/Node/ライブdataは扱わない。
	for key in ARCHIVE_KEYS:
		snapshot[key] = _archives[key]
	var started := Time.get_ticks_usec()
	var okay := V2Save.save_owned_snapshot(snapshot)
	return {"okay":okay,"error":V2Save.last_error,"usec":Time.get_ticks_usec()-started}

func finish()->void:
	if _thread:
		var result:Dictionary = _thread.wait_to_finish()
		_thread = null
		last_write_us = int(result.usec)
		error = str(result.error)
		if bool(result.okay):
			durable = running_revision

func mark_flushed()->void:
	durable = requested
	error = ""
	_configured = false
