class_name SupplyLineUpdater
extends Node

signal status_changed(message: String)
signal ready_changed(ready: bool)

const RELEASE_API := "https://api.github.com/repos/cloford/supply-line-trainer/releases/latest"
const DOWNLOAD_PREFIX := "https://github.com/cloford/supply-line-trainer/releases/download/"
const MAX_ARCHIVE_BYTES := 268435456
const MAX_ENTRIES := 128
const PAYLOAD := ["SupplyLineTrainer.exe", "SupplyLineTrainer.pck"]

var ready_to_apply := false
var release_version := ""
var status := "更新は未確認です"
var _request: HTTPRequest
var _phase := ""
var _asset: Dictionary = {}
var _auto_download := true
var _stage := ""
var _redirects := 0
var _applying := false
var _verification_thread: Thread

static func available() -> bool:
	return OS.get_name() == "Windows" and OS.has_feature("template") and not OS.has_feature("editor") and OS.get_executable_path().get_file() == PAYLOAD[0]

static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

static func running_version_text() -> String:
	var version := current_version()
	return "実行中 v%s" % version if version_parts(version).size() == 3 else "実行中の版番号は不明です"

static func version_parts(value: String) -> Array[int]:
	var regex := RegEx.new()
	regex.compile("^v?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\z")
	var matched := regex.search(value)
	var parts: Array[int] = []
	if matched:
		for index in range(1, 4):
			var part := matched.get_string(index)
			if part.length() > 9: return []
			parts.append(int(part))
	return parts

static func newer(candidate: String, current: String) -> bool:
	var left := version_parts(candidate)
	var right := version_parts(current)
	if left.size() != 3 or right.size() != 3: return false
	for index in 3:
		if left[index] != right[index]: return left[index] > right[index]
	return false

static func valid_asset(asset: Dictionary, tag: String) -> bool:
	if version_parts(tag).size() != 3: return false
	var version := tag.trim_prefix("v")
	var expected := "SupplyLineTrainer_Windows_v%s.zip" % version
	var digest_regex := RegEx.new()
	digest_regex.compile("^sha256:[0-9a-f]{64}\\z")
	return asset.get("name", "") == expected and asset.get("browser_download_url", "") == DOWNLOAD_PREFIX + tag + "/" + expected and int(asset.get("size", 0)) > 0 and int(asset.get("size", 0)) <= MAX_ARCHIVE_BYTES and digest_regex.search(str(asset.get("digest", ""))) != null

static func valid_redirect(url: String) -> bool:
	return url.begins_with("https://release-assets.githubusercontent.com/") and not "\\" in url and not "\n" in url and not "\r" in url

static func safe_archive_name(name: String) -> bool:
	if name.is_empty() or "\\" in name or ":" in name or name.begins_with("/") or name.length() > 240: return false
	for part in name.trim_suffix("/").split("/"):
		if part.is_empty() or part == "." or part == ".." or part.ends_with(".") or part.ends_with(" "): return false
	return true

static func archive_payload(names: PackedStringArray) -> Dictionary:
	if names.is_empty() or names.size() > MAX_ENTRIES: return {}
	var root := ""
	var exe_found := false
	for name in names:
		if not safe_archive_name(name): return {}
		if name.ends_with("/" + PAYLOAD[0]) or name == PAYLOAD[0]:
			if exe_found: return {}
			root = name.trim_suffix(PAYLOAD[0])
			exe_found = true
	if not exe_found or root.trim_suffix("/").contains("/"): return {}
	var found: Dictionary = {}
	var seen: Dictionary = {}
	for name in names:
		if name.ends_with("/"):
			if root != "" and name == root: continue
			return {}
		if not name.begins_with(root): return {}
		var relative := name.trim_prefix(root)
		if relative.contains("/"): return {}
		var lower := relative.to_lower()
		if seen.has(lower): return {}
		seen[lower] = true
		if relative in PAYLOAD:
			found[relative] = name
		elif not (lower.ends_with(".txt") or lower.ends_with(".md")):
			return {}
	return found if found.size() == 2 else {}

static func acknowledge_update() -> void:
	if not available(): return
	var args := OS.get_cmdline_user_args()
	var token_index := args.find("--supply-line-update-token")
	var ack_index := args.find("--supply-line-update-ack")
	if token_index < 0 or ack_index < 0 or token_index + 1 >= args.size() or ack_index + 1 >= args.size(): return
	var token := args[token_index + 1]
	var ack := args[ack_index + 1].replace("\\", "/")
	var expected := ProjectSettings.globalize_path("user://updates/").replace("\\", "/")
	if token.length() != 32 or not token.is_valid_hex_number(false): return
	if ack != expected.path_join(token).path_join("started.json"): return
	var file := FileAccess.open(ack, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"token": token, "version": current_version()}))
		file.close()

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.use_threads = true
	_request.max_redirects = 0
	_request.timeout = 30.0
	add_child(_request)
	_request.request_completed.connect(_completed)
	if not available(): _set_status("自動更新はWindows配布版で利用できます")

func _exit_tree() -> void:
	if _verification_thread and _verification_thread.is_started(): _verification_thread.wait_to_finish()

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)

func _fail(message: String) -> void:
	_phase = ""
	_set_status(message)

func is_applying() -> bool:
	return _applying

func check(auto_download: bool = true) -> void:
	if not available() or not _phase.is_empty() or _applying: return
	if ready_to_apply:
		_set_status("v%s を適用できます。再起動して更新してください" % release_version)
		return
	_auto_download = auto_download
	_phase = "check"
	_request.download_file = ""
	_request.body_size_limit = 1048576
	_request.timeout = 20.0
	_set_status("更新を確認中…")
	if _request.request(RELEASE_API, ["Accept: application/vnd.github+json", "User-Agent: SupplyLineTrainer"]) != OK:
		_fail("更新を確認できませんでした。あとで再試行できます")

func download() -> void:
	if not available() or _asset.is_empty() or not _phase.is_empty() or _applying or ready_to_apply: return
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	_stage = ProjectSettings.globalize_path("user://updates/" + token)
	if DirAccess.make_dir_recursive_absolute(_stage) != OK:
		_fail("更新用フォルダーを作成できませんでした")
		return
	_phase = "download"
	_redirects = 0
	_request.download_file = _stage.path_join("release.zip")
	_request.body_size_limit = int(_asset.size)
	_request.timeout = 180.0
	_set_status("v%s をバックグラウンドで取得中…（練習を続けられます）" % release_version)
	_request_asset(str(_asset.browser_download_url))

func _request_asset(url: String) -> void:
	if _request.request(url, ["User-Agent: SupplyLineTrainer"]) != OK:
		_fail("更新の取得に失敗しました。あとで再試行できます")

func _completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _phase not in ["check", "download"]: return
	if _phase == "download" and code in [301, 302, 303, 307, 308]:
		var location := ""
		for header in headers:
			if header.to_lower().begins_with("location:"): location = header.substr(9).strip_edges()
		if _redirects >= 3 or not valid_redirect(location):
			_fail("安全な配布先を確認できないため、更新を中止しました")
			return
		_redirects += 1
		_request_asset.call_deferred(location)
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("更新を取得できませんでした（通信または配布先のエラー）。あとで再試行できます")
		return
	if _phase == "check":
		_phase = ""
		var parser := JSON.new()
		var parsed := parser.parse(body.get_string_from_utf8())
		var data = parser.data if parsed == OK else null
		if not data is Dictionary or data.get("draft", true) or data.get("prerelease", true):
			_fail("正式版の更新情報を確認できませんでした")
			return
		var tag := str(data.get("tag_name", ""))
		if version_parts(tag).size() != 3:
			_fail("正式版のバージョン番号を確認できませんでした")
			return
		var current := current_version()
		if version_parts(current).size() != 3:
			_fail("実行中のバージョン番号を確認できないため、更新を中止しました")
			return
		if not newer(tag, current):
			if version_parts(tag) == version_parts(current):
				_set_status("最新公開版 v%s と同じです" % tag.trim_prefix("v"))
			else:
				_set_status("最新公開版は v%s（実行中の方が新しい版です）" % tag.trim_prefix("v"))
			return
		_asset = {}
		for item in data.get("assets", []):
			if item is Dictionary and valid_asset(item, tag):
				_asset = item
				break
		if _asset.is_empty():
			_fail("検証可能なWindows配布ファイルがありません。あとで再試行できます")
			return
		release_version = tag.trim_prefix("v")
		_set_status("v%s が利用できます" % release_version)
		if _auto_download: download.call_deferred()
	elif _phase == "download":
		_phase = "verify"
		_set_status("v%s の安全性をバックグラウンドで確認中…" % release_version)
		_verification_thread = Thread.new()
		if _verification_thread.start(_verify_worker.bind(_stage.path_join("release.zip"), int(_asset.size), str(_asset.digest).trim_prefix("sha256:"))) != OK:
			_fail("更新ファイルの検証を開始できませんでした")

static func verified_archive_error(path: String, expected_size: int, expected_digest: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() != expected_size:
		return "配布ファイルのサイズが一致しません。更新を中止しました"
	file.close()
	if FileAccess.get_sha256(path) != expected_digest:
		return "配布ファイルのSHA-256が一致しません。更新を中止しました"
	var zip := ZIPReader.new()
	if zip.open(path) != OK: return "配布ファイルを開けませんでした"
	var payload := archive_payload(zip.get_files())
	zip.close()
	if payload.is_empty(): return "配布ファイルの構成が安全ではないため、更新を中止しました"
	return ""

func _verify_worker(path: String, expected_size: int, expected_digest: String) -> void:
	var error := verified_archive_error(path, expected_size, expected_digest)
	_verification_complete.call_deferred(error)

func _verification_complete(error: String) -> void:
	if _verification_thread and _verification_thread.is_started(): _verification_thread.wait_to_finish()
	if not error.is_empty():
		_fail(error)
		return
	_phase = ""
	ready_to_apply = true
	ready_changed.emit(true)
	_set_status("v%s の準備ができました。再起動して更新できます" % release_version)

func apply_update() -> void:
	if not available() or not ready_to_apply or _applying: return
	_applying = true
	var helper_source := FileAccess.get_file_as_string("res://update_apply.ps1")
	var helper := FileAccess.open(_stage.path_join("apply.ps1"), FileAccess.WRITE)
	if helper_source.is_empty() or not helper:
		_applying = false
		_fail("更新プログラムを準備できませんでした")
		return
	helper.store_buffer(PackedByteArray([0xef, 0xbb, 0xbf]))
	helper.store_string(helper_source)
	helper.close()
	var token := _stage.get_file()
	var manifest := {"token": token, "pid": OS.get_process_id(), "executable": OS.get_executable_path(), "sha256": str(_asset.digest).trim_prefix("sha256:"), "size": int(_asset.size), "version": release_version}
	var file := FileAccess.open(_stage.path_join("manifest.json"), FileAccess.WRITE)
	if not file:
		_applying = false
		_fail("更新情報を保存できませんでした")
		return
	file.store_string(JSON.stringify(manifest))
	file.close()
	var powershell := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var helper_pid := OS.create_process(powershell, ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", _stage.path_join("apply.ps1"), "-ManifestPath", _stage.path_join("manifest.json")])
	if helper_pid <= 0:
		_applying = false
		_fail("更新プログラムを起動できませんでした")
		return
	_set_status("保存を完了し、更新のため再起動します…")
	for attempt in 300:
		await get_tree().create_timer(0.05).timeout
		if FileAccess.file_exists(_stage.path_join("helper-ready.txt")) and FileAccess.get_file_as_string(_stage.path_join("helper-ready.txt")) == token:
			var confirmation := FileAccess.open(_stage.path_join("apply-confirmed.txt"), FileAccess.WRITE)
			if not confirmation: break
			confirmation.store_string(token)
			confirmation.close()
			get_tree().quit()
			return
	_applying = false
	ready_to_apply = false
	ready_changed.emit(false)
	_fail("更新の起動を確認できませんでした。現在のゲームを続けられます")
