extends RefCounted
const R = preload("res://contracts/result.gd")
const C = preload("res://contracts/canonical.gd")
const V = preload("res://contracts/values.gd")
const Content = preload("res://infrastructure/content/compiler.gd")

static func resolve(args: PackedStringArray, display: String, environment: Dictionary) -> Dictionary:
	var config := {"profile":"headless" if display=="headless" else "client","log_level":"info",
		"content_paths":[Content.BASE_PACKAGE],"config_sources":{"profile":"display","content_paths":"base","log_level":"default"},
		"world_options":{},"player_options":{},"smoke":false,"platform":OS.get_name(),"build_id":"p1"}
	# Only these two named environment entries enter the configuration.
	for pair in [["RECOLLECTION_PROFILE","profile"],["RECOLLECTION_LOG_LEVEL","log_level"]]:
		if environment.has(pair[0]) and environment[pair[0]]!="":
			config[pair[1]]=environment[pair[0]]
			config.config_sources[pair[1]]="environment"
	var paths := []
	for arg in args:
		if arg=="--p1-smoke":
			config.smoke=true
		elif arg.begins_with("--profile="):
			config.profile=arg.trim_prefix("--profile=")
			config.config_sources.profile="command_line"
		elif arg.begins_with("--log-level="):
			config.log_level=arg.trim_prefix("--log-level=")
			config.config_sources.log_level="command_line"
		elif arg.begins_with("--content-path="):
			paths.append(arg.trim_prefix("--content-path="))
		elif arg.begins_with("--battle-limit="):
			var value: String=arg.trim_prefix("--battle-limit=")
			if not value.is_valid_int() or value!=str(value.to_int()):
				return R.fail("InvalidArgument","battle_limit")
			config.player_options["battle_limit"]=value.to_int()
		else:
			return R.fail("InvalidArgument","argument")
	if not paths.is_empty():
		config.content_paths=paths
		config.config_sources.content_paths="command_line"
	return validate(config,display)

static func validate(config: Dictionary, display: String) -> Dictionary:
	for key in config:
		if key not in ["profile","content_paths","config_sources","log_level","build_id","platform","world_options","player_options","smoke"]:
			return R.fail("InvalidArgument","config.field")
	var sources: Variant=config.get("config_sources",{})
	if typeof(sources)!=TYPE_DICTIONARY:
		return R.fail("InvalidArgument","config_sources")
	for key in sources:
		if key not in ["profile","content_paths","log_level"] or typeof(sources[key])!=TYPE_STRING:
			return R.fail("InvalidArgument","config_sources")
	for key in ["platform","build_id"]:
		if config.has(key) and (typeof(config[key])!=TYPE_STRING or config[key].is_empty()):
			return R.fail("InvalidArgument",key)
	if config.get("profile") not in ["client","headless","tool"]:
		return R.fail("InvalidArgument","profile")
	if config.profile!="tool" and (config.profile=="headless")!=(display=="headless"):
		return R.fail("InvalidArgument","display_profile")
	if config.get("log_level","info") not in ["debug","info","warning","error"]:
		return R.fail("InvalidArgument","log_level")
	if not C.is_json_array(config.get("content_paths")) or config.content_paths.is_empty():
		return R.fail("InvalidArgument","content_paths")
	for path in config.content_paths:
		if typeof(path)!=TYPE_STRING or path.is_empty():
			return R.fail("InvalidArgument","content_paths")
	if typeof(config.get("smoke",false))!=TYPE_BOOL:
		return R.fail("InvalidArgument","smoke")
	for source in ["world_options","player_options"]:
		var overrides: Variant=config.get(source,{})
		if typeof(overrides)!=TYPE_DICTIONARY:
			return R.fail("InvalidArgument",source)
		for key in overrides:
			if key!="battle_limit" or not V.integer(overrides[key],1):
				return R.fail("InvalidArgument",source)
	if config.profile=="headless" and not config.get("player_options",{}).is_empty():
		return R.fail("Unauthorized","player_options")
	return R.ok(config.duplicate(true))
