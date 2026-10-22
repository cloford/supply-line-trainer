extends SceneTree

# Read the actual public API/CDN, never replace or restart the running game.
func _init()->void:call_deferred("_run")
func _run()->void:
	if OS.get_environment("SLT_TEST_DATA")!="1":quit(1);return
	var expected:=SupplyLineUpdater.current_version()
	var updater:=SupplyLineUpdater.new();root.add_child(updater)
	ProjectSettings.set_setting("application/config/version","1.8.0")
	updater._auto_download=false;updater._phase="check"
	updater._request.timeout=25
	if updater._request.request(SupplyLineUpdater.RELEASE_API,["Accept: application/vnd.github+json","User-Agent: SupplyLineTrainer-ReleaseTest"])!=OK:quit(1);return
	var deadline:=Time.get_ticks_msec()+30000
	while not updater._phase.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	ProjectSettings.set_setting("application/config/version",expected)
	if updater.release_version!=expected or updater._asset.is_empty():push_error("published update not detected: "+updater.status);quit(1);return
	print("PUBLIC_UPDATE_DETECTED: v1.8.0 -> v",updater.release_version)
	updater._stage=ProjectSettings.globalize_path("user://public-release-verification")
	DirAccess.make_dir_recursive_absolute(updater._stage)
	updater._phase="download";updater._redirects=0
	updater._request.download_file=updater._stage.path_join("release.zip")
	updater._request.body_size_limit=int(updater._asset.size);updater._request.timeout=120
	updater._request_asset(str(updater._asset.browser_download_url))
	deadline=Time.get_ticks_msec()+150000
	while not updater.ready_to_apply and not updater._phase.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not updater.ready_to_apply:push_error("public ZIP verification failed: "+updater.status);quit(1);return
	print("PUBLIC_RELEASE_OK: API/CDN download, redirect, size, SHA256, archive verified; no apply/restart. ",updater._asset.digest)
	updater.queue_free();await process_frame;quit(0)
