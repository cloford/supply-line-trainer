extends SceneTree

func _init()->void:
	var pairs := [["0.21","2.0.0"],["0.22","0.21"],["0.30","0.29"],["0.100","0.99"],["0.21","0.99.0"],["0.21","0.30.9"]]
	for pair in pairs:
		assert(ReleaseVersion.newer(pair[0],pair[1]),str(pair))
		assert(not ReleaseVersion.newer(pair[1],pair[0]),str(pair))
	assert(ReleaseVersion.same("v"+ReleaseVersion.PUBLIC,ReleaseVersion.INTERNAL))
	assert(ReleaseVersion.display(ReleaseVersion.INTERNAL) == ReleaseVersion.PUBLIC)
	assert(not ReleaseVersion.newer("2.99.0","0.21"))
	assert(not ReleaseVersion.newer("0.21","0.21"))
	assert(ReleaseVersion.parse("0.24.0").epoch == 0)
	assert(ReleaseVersion.newer(ReleaseVersion.PUBLIC,"0.21"))
	for invalid in ["0.020","0.21\n","0.21-beta","0.21+dev","0.21.0.0","01.0.0","0.999999999999","0.2"]:
		assert(ReleaseVersion.parse(invalid).is_empty(),invalid)
	print("RELEASE_VERSION_OK: explicit epochs, 2.0 -> 0.21, 0.29 -> 0.30, canonical public display, ambiguous legacy 0.x.y")
	quit(0)
