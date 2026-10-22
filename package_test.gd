extends SceneTree
func _init()->void:
	var archive:=ZIPReader.new()
	if archive.open(OS.get_environment("SLT_PACKAGE_ZIP"))!=OK:quit(1);return
	var payload:=SupplyLineUpdater.archive_payload(archive.get_files())
	if payload.size()!=2:push_error("package rejected by updater");quit(1);return
	print("PACKAGE_TEST_OK: updater accepts ",payload," SHA256=",FileAccess.get_sha256(OS.get_environment("SLT_PACKAGE_ZIP")))
	archive.close();quit(0)
