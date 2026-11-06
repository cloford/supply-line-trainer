class_name V2SaveWorker
extends RefCounted

# archive cacheはworker専有。main側は参照planだけを作り、ライブrecordを渡さない。
const ARCHIVE_KEYS := ["training_history", "profiles", "previous_profiles"]
var _archives:Dictionary = {}
# main専用の参照対応表。workerはこのDictionaryへ触れない。
var _archive_refs:Dictionary = {}
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
	assert(not _thread)
	_archives = {}
	for key in ARCHIVE_KEYS:
		_archives[key] = data[key].duplicate(true)
	accept_refs(data)
	_configured = true

func configured()->bool:
	return _configured

func accept_refs(data:Dictionary)->void:
	_archive_refs = {}
	for key in ARCHIVE_KEYS:
		_archive_refs[key] = data[key].duplicate()

func _small_snapshot(data:Dictionary)->Dictionary:
	var snapshot:Dictionary = {}
	for key in data:
		if key in ARCHIVE_KEYS:continue
		var value:Variant = data[key]
		snapshot[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return snapshot

func start_transaction(candidate:Dictionary)->void:
	assert(not _thread and _configured)
	var started := Time.get_ticks_usec()
	var snapshot := _small_snapshot(candidate)
	var plan:Dictionary = {}
	for key in ARCHIVE_KEYS:
		plan[key] = []
		for record in candidate[key]:
			var source_key := ""
			var source_index := -1
			for cached_key in ARCHIVE_KEYS:
				for index in _archive_refs[cached_key].size():
					if is_same(record,_archive_refs[cached_key][index]):
						source_key = cached_key
						source_index = index
						break
				if source_index >= 0:break
			plan[key].append({"source":source_key,"index":source_index} if source_index >= 0 else {"value":record.duplicate(true)})
	snapshot["_archive_plan"] = plan
	last_snapshot_us = Time.get_ticks_usec()-started
	start_owned(snapshot)

func request()->void:
	requested += 1
	requests += 1

func pending()->bool:
	return requested > durable

func running()->bool:
	return _thread != null

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

func start_owned(snapshot:Dictionary)->void:
	assert(not _thread)
	running_revision = requested
	_thread = Thread.new()
	var status := _thread.start(_write.bind(snapshot))
	if status != OK:
		_thread = null
		error = "保存用処理を開始できません。再試行します。"
		retry_after = Time.get_ticks_msec() / 1000.0 + 1.0
	else:
		writes += 1

func dispatch(data:Dictionary)->void:
	poll()
	var frame := Engine.get_process_frames()
	if _thread or not pending() or frame == last_dispatch_frame or Time.get_ticks_msec() / 1000.0 < retry_after:
		return
	if not _configured:
		configure(data)
	var started := Time.get_ticks_usec()
	var snapshot := _small_snapshot(data)
	last_snapshot_us = Time.get_ticks_usec() - started
	last_dispatch_frame = frame
	start_owned(snapshot)

func _write(snapshot:Dictionary)->Dictionary:
	# snapshot/plan/new records/cacheはworker専有。SceneTree/Node/ライブdataを渡さない。
	var archives := _archives
	var transaction := snapshot.has("_archive_plan")
	if transaction:
		archives = {}
		var plan:Dictionary = snapshot["_archive_plan"]
		for key in ARCHIVE_KEYS:
			archives[key] = []
			for row in plan[key]:
				archives[key].append(_archives[str(row.source)][int(row.index)] if row.has("source") else row.value)
		snapshot.erase("_archive_plan")
	for key in ARCHIVE_KEYS:
		snapshot[key] = archives[key]
	var started := Time.get_ticks_usec()
	var okay := V2Save.save_owned_snapshot(snapshot)
	if okay and transaction:
		_archives = archives
	return {"okay":okay,"error":V2Save.last_error,"usec":Time.get_ticks_usec()-started}

# teardown専用。通常UI操作はpoll/await process_frameで待つ。
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
