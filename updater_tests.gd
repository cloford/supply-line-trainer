extends SceneTree

const Updater = preload("res://updater.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	check(Updater.newer("v1.4.0", "1.3.0"), "normal update")
	check(Updater.newer("1.10.0", "1.9.99"), "numeric semantic comparison")
	check(not Updater.newer("1.4.0", "1.4.0"), "equal release")
	check(not Updater.newer("1.3.9", "1.4.0"), "no downgrade")
	for version in ["1.4.0-beta", "1.4.0+dev", "01.4.0", "1.4", "1.4.0\n", "https://bad", "9999999999999999999.0.0"]:
		check(Updater.version_parts(version).is_empty(), "invalid stable version " + version)
	var asset := {"name": "SupplyLineTrainer_Windows_v1.4.0.zip", "browser_download_url": Updater.DOWNLOAD_PREFIX + "v1.4.0/SupplyLineTrainer_Windows_v1.4.0.zip", "size": 40000000, "digest": "sha256:" + "a".repeat(64)}
	check(Updater.valid_asset(asset, "v1.4.0"), "trusted GitHub release asset")
	for field in ["name", "browser_download_url", "digest"]:
		var invalid: Dictionary = asset.duplicate()
		invalid[field] = "https://evil.invalid/asset.zip"
		check(not Updater.valid_asset(invalid, "v1.4.0"), "untrusted " + field)
	for size in [0, -1, Updater.MAX_ARCHIVE_BYTES + 1]:
		var invalid: Dictionary = asset.duplicate()
		invalid.size = size
		check(not Updater.valid_asset(invalid, "v1.4.0"), "oversized or empty archive")
	check(Updater.valid_redirect("https://release-assets.githubusercontent.com/github-production-release-asset/123?token=abc"), "GitHub CDN redirect")
	for url in ["http://release-assets.githubusercontent.com/a", "https://release-assets.githubusercontent.com.evil.invalid/a", "https://release-assets.githubusercontent.com@evil.invalid/a", "https://evil.invalid/a"]:
		check(not Updater.valid_redirect(url), "unsafe redirect " + url)
	check(Updater.archive_payload(PackedStringArray(["SupplyLineTrainer.exe", "SupplyLineTrainer.pck", "README.txt"])).size() == 2, "flat archive")
	check(Updater.archive_payload(PackedStringArray(["SupplyLineTrainer_Windows/", "SupplyLineTrainer_Windows/SupplyLineTrainer.exe", "SupplyLineTrainer_Windows/SupplyLineTrainer.pck", "SupplyLineTrainer_Windows/GODOT_LICENSE.txt"])).size() == 2, "single root archive")
	for extra in ["../escape.txt", "C:/escape.txt", "/absolute.txt", "sub/../../escape.txt", "evil.dll", "evil.ps1", "README.txt:payload", "folder\\evil.txt", "SUPPLYLINETRAINER.EXE", "README.txt."]:
		check(Updater.archive_payload(PackedStringArray(["SupplyLineTrainer.exe", "SupplyLineTrainer.pck", extra])).is_empty(), "unsafe archive " + extra)
	check(Updater.archive_payload(PackedStringArray(["SupplyLineTrainer.exe"])).is_empty(), "missing PCK")
	check(Updater.archive_payload(PackedStringArray(["x/SupplyLineTrainer.exe", "y/SupplyLineTrainer.pck"])).is_empty(), "mixed roots")
	check(not Updater.available(), "source runner must not update")
	_async_checks.call_deferred()

func _async_checks() -> void:
	var directory := OS.get_environment("TEMP").path_join("supply-line-updater-test-" + Crypto.new().generate_random_bytes(8).hex_encode())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "isolated fixture directory")
	var zip_path := directory.path_join("release.zip")
	var packer := ZIPPacker.new()
	check(packer.open(zip_path) == OK, "create fixture archive")
	for name in Updater.PAYLOAD:
		packer.start_file(name)
		packer.write_file(("test payload " + name).to_utf8_buffer())
		packer.close_file()
	packer.close()
	var digest := FileAccess.get_sha256(zip_path)
	var zip_data := FileAccess.get_file_as_bytes(zip_path)
	check(Updater.verified_archive_error(zip_path, zip_data.size(), digest).is_empty(), "full archive digest validation")
	check(not Updater.verified_archive_error(zip_path, zip_data.size() + 1, digest).is_empty(), "full archive size rejection")
	check(not Updater.verified_archive_error(zip_path, zip_data.size(), "0".repeat(64)).is_empty(), "full archive digest rejection")
	var valid := await _transport_case(200, zip_data, "download", directory.path_join("good"), {"size": zip_data.size(), "digest": "sha256:" + digest})
	check(valid.ready, "HTTP download and threaded verification ready state")
	var corrupt := await _transport_case(200, zip_data, "download", directory.path_join("corrupt"), {"size": zip_data.size(), "digest": "sha256:" + "0".repeat(64)})
	check(not corrupt.ready and "SHA-256" in corrupt.status, "HTTP download corrupt digest rejection")
	var missing := await _transport_case(404, "missing".to_utf8_buffer(), "check", "", {})
	check(not missing.ready and "エラー" in missing.status, "HTTP 404 recoverable status")
	var invalid := await _transport_case(200, "{broken".to_utf8_buffer(), "check", "", {})
	check("確認できません" in invalid.status, "invalid release JSON")
	var latest := {"tag_name": str(ProjectSettings.get_setting("application/config/version")), "draft": false, "prerelease": false, "assets": []}
	var none := await _transport_case(200, JSON.stringify(latest).to_utf8_buffer(), "check", "", {})
	check("最新版" in none.status, "same current release no update")
	latest.prerelease = true
	var prerelease := await _transport_case(200, JSON.stringify(latest).to_utf8_buffer(), "check", "", {})
	check("正式版" in prerelease.status and not prerelease.ready, "prerelease metadata rejected")
	var node := Updater.new()
	root.add_child(node)
	node._phase = "check"
	node._request.timeout = 1.0
	node._request.request("http://127.0.0.1:1/")
	var deadline := Time.get_ticks_msec() + 3000
	while not node._phase.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(node._phase.is_empty() and "エラー" in node.status, "network failure recoverable status")
	node.queue_free()
	if failures.is_empty():
		print("UPDATER_TEST_OK: stable versions, trusted assets, redirects, size/digest limits, ZIP payloads, loopback HTTP success/404/invalid/prerelease/network failure, threaded verification")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _transport_case(code: int, body: PackedByteArray, phase: String, directory: String, asset: Dictionary) -> Dictionary:
	# The loopback server exercises transport in tests only; production URLs remain fixed.
	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "loopback server listen")
	var node := Updater.new()
	root.add_child(node)
	node._phase = phase
	node._auto_download = false
	node._asset = asset
	node._request.timeout = 5.0
	if phase == "download":
		DirAccess.make_dir_recursive_absolute(directory)
		node._stage = directory
		node._request.download_file = directory.path_join("release.zip")
		node._request.body_size_limit = int(asset.size)
	check(node._request.request("http://127.0.0.1:%d/fixture" % server.get_local_port()) == OK, "HTTP fixture request starts")
	var deadline := Time.get_ticks_msec() + 7000
	while not server.is_connection_available() and Time.get_ticks_msec() < deadline: await process_frame
	if server.is_connection_available():
		var peer := server.take_connection()
		peer.poll()
		while peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() == 0 and Time.get_ticks_msec() < deadline:
			peer.poll()
			await create_timer(0.005).timeout
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0: peer.get_data(peer.get_available_bytes())
		peer.put_data(("HTTP/1.1 %d Fixture\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, body.size()]).to_utf8_buffer())
		peer.put_data(body)
		while not node._phase.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		peer.disconnect_from_host()
	else: check(false, "HTTP fixture accepted connection")
	server.stop()
	var outcome := {"ready": node.ready_to_apply, "status": node.status}
	print("TRANSPORT_FIXTURE ", code, " ", phase, " ", outcome)
	check(node._phase.is_empty(), "HTTP fixture finishes " + phase)
	node.queue_free()
	await process_frame
	return outcome
