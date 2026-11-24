extends SceneTree
const Composition = preload("res://bootstrap/composition_root.gd")
const Canon = preload("res://contracts/canonical.gd")
const Config = preload("res://bootstrap/boot_config.gd")
const Compiler = preload("res://infrastructure/content/compiler.gd")
const R = preload("res://contracts/result.gd")
var errors := 0

func _initialize() -> void:
	run.call_deferred()

func check(pass_test: bool, label: String) -> void:
	if not pass_test:
		printerr("FAIL ",label)
		errors+=1

func result_group(label: String, previous: int) -> void:
	print(label," PASS" if errors==previous else " FAIL")

func descriptor(id: String, needs: Array, factory: Callable, stop: Callable) -> Dictionary:
	return {"id":id,"requires":needs,"version":1,"factory":factory,"shutdown":stop}

func config() -> Dictionary:
	return {"profile":"headless","content_paths":[Compiler.BASE_PACKAGE]}

func run() -> void:
	var initial:=errors
	var host:=Node.new()
	root.add_child(host)
	var boot:=Composition.new(host)
	var factory_calls := []
	var make:=func(_deps): factory_calls.append(1); return R.ok({"ready":true})
	var stop:=func(_service): return R.ok()
	check(boot.register(descriptor("a",["b"],make,stop)).ok and boot.register(descriptor("b",["a"],make,stop)).ok,"register cycle")
	check(boot.register(descriptor("a",[],make,stop)).error.code=="Conflict","reject duplicate")
	var cycle:=boot.boot(config())
	check(not cycle.ok and cycle.error.detail==["a","b","a"] and factory_calls.is_empty() and boot.session()==null,"cycle before any factory")
	boot=Composition.new(host)
	boot.register(descriptor("missing",["not-installed"],make,stop))
	check(boot.boot(config()).error.code=="Unavailable" and boot.report().missing_services==["not-installed"],"missing dependency named")
	result_group("T-BOOT-01",initial)
	initial=errors
	boot=Composition.new(host)
	var started:=boot.boot(config())
	check(started.ok and boot.session()!=null,"real content and session")
	if not started.ok:
		quit(1)
		return
	check(not ResourceLoader.has_cached("res://bootstrap/desktop.gd") and host.find_children("*","Control",true,false).is_empty(),"no desktop script or control")
	check(host.find_children("*","AudioStreamPlayer",true,false).is_empty() and RenderingServer.get_rendering_device()==null and DisplayServer.get_name()=="headless","no audio nodes/GPU/display")
	check(boot.start_training().ok,"headless session starts real mission port")
	var stepped:=boot.training_step()
	check(stepped.ok and stepped.value.tick==1 and stepped.value.phase=="Running","fixed step in real simulation")
	check(host.find_children("Simulation","Node3D",true,false).size()==1,"real simulation instance")
	check(not boot.boot(config()).ok,"no double initialization")
	var closed:=boot.shutdown()
	var order: Array=started.value.construct_order.duplicate()
	order.reverse()
	check(closed.ok and boot.report().release_order==order and host.get_child_count()==0 and boot.session()==null,"reverse disposal releases scene and scope")
	check(boot.shutdown().ok,"repeat shutdown")
	result_group("T-BOOT-02",initial)
	initial=errors
	var bad_dir:=ProjectSettings.globalize_path("user://boot-bad-"+Crypto.new().generate_random_bytes(6).hex_encode())
	DirAccess.make_dir_recursive_absolute(bad_dir)
	var file:=FileAccess.open(bad_dir.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var invalid_config:=config()
	invalid_config.content_paths=[bad_dir]
	var failed:=boot.boot(invalid_config)
	check(not failed.ok and boot.report().failed_module=="content" and boot.session()==null,"malformed manifest rejects")
	var built: Array=boot.report().construct_order.duplicate()
	built.reverse()
	check(built.size()>=2 and boot.report().release_order==built,"real content failure reverse releases all built")
	for dir in ["definitions","scenes"]:
		DirAccess.make_dir_recursive_absolute(bad_dir.path_join(dir))
	for path in ["definitions/runtime.json","scenes/training.scene.json"]:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(Compiler.BASE_PACKAGE.path_join(path)),bad_dir.path_join(path))
	var parsed:=Canon.decode_source(FileAccess.get_file_as_bytes(Compiler.BASE_PACKAGE.path_join("manifest.json")))
	parsed.value.erase("config")
	file=FileAccess.open(bad_dir.path_join("manifest.json"),FileAccess.WRITE)
	file.store_buffer(Canon.encode(parsed.value).value)
	file.close()
	failed=boot.boot(invalid_config)
	check(not failed.ok and failed.error.field=="content.battle_limit" and boot.session()==null,"missing required compiled setting")
	built=boot.report().construct_order.duplicate()
	built.reverse()
	check(boot.report().release_order==built,"missing setting rolls back before Session exists")
	result_group("T-BOOT-03",initial)
	initial=errors
	var attempts := [0]
	var retry:=func(_service):
		attempts[0]+=1
		return R.fail("Unavailable","retry") if attempts[0]==1 else R.ok()
	boot=Composition.new(host)
	boot.register(descriptor("z-hold",["session"],make,retry))
	boot.register(descriptor("z-later",["z-hold"],func(_deps): return R.fail("Unavailable","broken"),stop))
	check(not boot.boot(config()).ok and boot.report().shutdown_errors==["z-hold"],"failed startup with deferred release")
	check(boot.session()==null and not boot.start_training().ok and not boot.new_world("forbidden").ok,"half-initialized session is inaccessible")
	check(boot.shutdown().ok and attempts[0]==2 and boot.session()==null,"retry reverse cleanup")
	var bad:=config()
	bad["config_sources"]=3
	check(not Composition.new(host).boot(bad).ok,"type error returns diagnostic")
	var arguments:=PackedStringArray(["--profile=headless","--log-level=debug"])
	var parsed_config:=Config.resolve(arguments,"headless",{"RECOLLECTION_PROFILE":"client","RECOLLECTION_LOG_LEVEL":"error","SECRET":"never-retain"})
	check(parsed_config.ok and parsed_config.value.profile=="headless" and parsed_config.value.log_level=="debug" and not str(parsed_config.value).contains("never-retain"),"only whitelisted environment, command line wins")
	check(not Config.resolve(PackedStringArray(["--battle-limit=100"]),"headless",{}).ok,"server rejects local player overrides")
	var tool:=config()
	tool.profile="tool"
	boot=Composition.new(host)
	check(boot.boot(tool).ok and boot.session()==null and boot.report().construct_order==["telemetry","compiler","content"],"data-tool profile")
	boot.shutdown()
	result_group("BOOT-BOUNDARIES",initial)
	host.free()
	print("BOOT_CHECKS errors=",errors)
	quit(1 if errors else 0)
