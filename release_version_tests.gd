extends SceneTree

func _init()->void:
	var pairs := [["0.21","2.0.0"],["0.22","0.21"],["0.30","0.29"],["0.100","0.99"],["0.21","0.99.0"],["0.21","0.30.9"],["0.2.5","0.25"],["0.2.5","0.25.0"],["0.2.5","2.0.0"],["0.2.5","0.2.4"],["0.2.10","0.2.9"],["0.3.0","0.2.999"],["0.20.0","0.19.99"]]
	for pair in pairs:
		assert(ReleaseVersion.newer(pair[0],pair[1]),str(pair))
		assert(not ReleaseVersion.newer(pair[1],pair[0]),str(pair))
	assert(ReleaseVersion.same("v"+ReleaseVersion.PUBLIC,ReleaseVersion.INTERNAL))
	assert(ReleaseVersion.PUBLIC == "0.2.5")
	assert(ProjectSettings.get_setting("application/config/version") == ReleaseVersion.INTERNAL)
	assert(ReleaseVersion.display(ReleaseVersion.INTERNAL) == ReleaseVersion.PUBLIC)
	assert(not ReleaseVersion.newer("2.99.0","0.21"))
	assert(not ReleaseVersion.newer("0.21","0.21"))
	assert(ReleaseVersion.parse("0.26.0").epoch == 0)
	assert(ReleaseVersion.newer(ReleaseVersion.PUBLIC,"0.21"))
	for invalid in ["0.020","0.21\n","0.21-beta","0.21+dev","0.21.0.0","01.0.0","0.999999999999","0.2"]:
		assert(ReleaseVersion.parse(invalid).is_empty(),invalid)
	print("RELEASE_VERSION_OK: legacy epochs, 0.25 -> 0.2.5, 0.2.9 -> 0.2.10, canonical project/public version")
	quit(0)
