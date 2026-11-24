extends RefCounted
const V = preload("res://contracts/values.gd")
const R = preload("res://contracts/result.gd")
const Canon = preload("res://contracts/canonical.gd")
const Protocol = preload("res://contracts/ports/network_port.gd")
const Config = preload("res://bootstrap/boot_config.gd")
const Graph = preload("res://bootstrap/module_graph.gd")
const Diagnostics = preload("res://infrastructure/telemetry/diagnostics.gd")
const Content = preload("res://infrastructure/content/compiler.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Store = preload("res://infrastructure/persistence/save_service.gd")
const Core = preload("res://core/runtime.gd")
const Camp = preload("res://campaign/runtime.gd")
const Mission = preload("res://mission/runtime/runtime.gd")
const Session = preload("res://application/game_session.gd")

var _host: Node
var _registered := {}
var _active := {}
var _services := {}
var _stack := []
var _busy := false
var _ready_for_requests := false
var _config := {}
var _report := {}

func _init(host: Node) -> void:
	_host=host

func register(descriptor: Dictionary) -> Dictionary:
	if _busy or not _stack.is_empty():
		return R.fail("InvalidState","registry")
	return Graph.insert(_registered,descriptor)

func validate_graph() -> Dictionary:
	return Graph.order(_registered)

func report() -> Dictionary:
	return _report.duplicate(true)

func _descriptor(id: String, requires: Array, factory: Callable, shutdown_fn: Callable) -> Dictionary:
	return {"id":id,"version":1,"requires":requires,"factory":factory,"shutdown":shutdown_fn}

func _defaults() -> Array:
	var release:=func(_service): return R.ok()
	var descriptors := [
		_descriptor("telemetry",[],func(_deps): return R.ok(Diagnostics.new()),release),
		_descriptor("compiler",["telemetry"],func(_deps): return R.ok(Content.new()),release),
		_descriptor("content",["compiler"],_compile,release)]
	if _config.profile!="tool":
		descriptors.append_array([
			_descriptor("core",[],func(_deps): return R.ok(Core.new()),release),
			_descriptor("engine",[],func(_deps): return R.ok(Adapter.new(_host,_config.profile=="headless")),release),
			_descriptor("persistence",[],func(_deps): return R.ok(Store.new()),release),
			_descriptor("session",["content","core","engine","persistence"],_create_session,
				func(service): return service.close_session("shutdown"))])
	return descriptors

func _compile(deps: Dictionary) -> Dictionary:
	var compiler: RefCounted=deps.compiler
	var resolved: Dictionary=compiler.resolve_packages(compiler.scan_packages(_config.content_paths),Content.VERSION)
	if not resolved.ok:
		return resolved
	var overrides: Dictionary=_config.get("world_options",{}).duplicate()
	overrides.merge(_config.get("player_options",{}),true)
	var compiled: Dictionary=compiler.compile(resolved.value,overrides)
	if not compiled.ok:
		return compiled
	if _config.profile!="tool" and not V.integer(compiled.value.config.get("battle_limit"),1):
		return R.fail("InvalidArgument","content.battle_limit")
	# The single scene needed to boot the P1 training flow must resolve before
	# constructing a Session. Content/DEF own the definitions and asset checks.
	for pair in [["base:scene/training","scene"],["base:ruleset/standard","ruleset"]]:
		if _config.profile=="tool":
			break
		var found: Dictionary=compiled.value.registry.get_definition(pair[0],pair[1])
		if not found.ok:
			return found
	var sources: Dictionary=compiled.value.config_provenance.duplicate(true)
	for key in _config.get("world_options",{}):
		sources[key]="world"
	for key in _config.get("player_options",{}):
		sources[key]="player"
	_report["effective_options"]=compiled.value.config.duplicate(true)
	_report["option_sources"]=sources
	return compiled

func _create_session(deps: Dictionary) -> Dictionary:
	var core: RefCounted=deps.core
	var engine_adapter: RefCounted=deps.engine
	var replay: bool=_config.get("smoke",false)
	var mission_factory:=func(mode: String):
		# Only the CI replay restores a fixed authority-issued instance ID.
		return Mission.new(core,engine_adapter,mode,Callable(),"mission/p1-training-replay" if replay else "")
	# The frontend exposes world and training actions only. A gameplay exchange
	# needs an installed trusted authority rather than a caller-supplied identity.
	return R.ok(Session.new(deps.persistence,func(): return Camp.new(),mission_factory,Callable()))

func boot(config: Dictionary) -> Dictionary:
	if _busy or not _stack.is_empty():
		return R.fail("InvalidState","boot")
	_busy=true
	_report={"construct_order":[],"release_order":[],"shutdown_errors":[],"timings_usec":{},"failed_module":"",
		"missing_services":[],"errors":[],"content_hash":"","protocol_version":Protocol.VERSION}
	var checked:=Config.validate(config,DisplayServer.get_name())
	if not checked.ok:
		return _failed("config",checked)
	_config=checked.value
	_report["resolved_config"]={"profile":_config.profile,"log_level":_config.get("log_level","info"),
		"platform":OS.get_name(),"build_id":_config.get("build_id","p1"),
		"content_paths":_config.content_paths.duplicate(),"sources":_config.get("config_sources",{}).duplicate()}
	_active=_registered.duplicate()
	for descriptor in _defaults():
		var added:=Graph.insert(_active,descriptor)
		if not added.ok:
			return _failed("registry",added)
	var sorted:=Graph.order(_active)
	if not sorted.ok:
		if sorted.error.code=="Unavailable":
			_report.missing_services.append(sorted.error.field)
		return _failed("graph",sorted)
	for id in sorted.value:
		var descriptor: Dictionary=_active[id]
		var dependencies := {}
		for key in descriptor.requires:
			dependencies[key]=_services[key]
		dependencies.make_read_only()
		var start:=Time.get_ticks_usec()
		var made: Variant=descriptor.factory.call(dependencies)
		_report.timings_usec[id]=Time.get_ticks_usec()-start
		if typeof(made)!=TYPE_DICTIONARY or typeof(made.get("ok"))!=TYPE_BOOL:
			return _failed(id,R.fail("Unavailable","factory"))
		if not made.ok:
			return _failed(id,made if typeof(made.get("error"))==TYPE_DICTIONARY else R.fail("Unavailable","factory"))
		if made.get("value")==null:
			return _failed(id,R.fail("Unavailable","service"))
		_services[id]=made.value
		_stack.append(id)
		_report.construct_order.append(id)
	_ready_for_requests=true
	_report.content_hash=_services.content.content_hash
	_services.telemetry.log({"level":"info","module":"boot","phase":"ready","content_hash":_report.content_hash,"profile":_config.profile})
	_busy=false
	return R.ok(report())

func _failed(id: String, error: Dictionary) -> Dictionary:
	_ready_for_requests=false
	_report.failed_module=id
	_report.errors.append(error.error.duplicate(true))
	_drain()
	_busy=false
	return error

func _drain() -> void:
	while not _stack.is_empty():
		var id: String=_stack.back()
		var stopped: Variant=_active[id].shutdown.call(_services[id])
		if typeof(stopped)!=TYPE_DICTIONARY or stopped.get("ok")!=true:
			_report.shutdown_errors.append(id)
			return
		_services.erase(id)
		_stack.pop_back()
		_report.release_order.append(id)
	_active={}
	_config={}

func shutdown() -> Dictionary:
	if _busy:
		return R.fail("InvalidState","shutdown")
	_busy=true
	_ready_for_requests=false
	if not _stack.is_empty():
		_drain()
	_busy=false
	return R.ok(report()) if _stack.is_empty() else R.fail("Unavailable","shutdown")

func session() -> RefCounted:
	return _services.get("session") if _ready_for_requests and not _busy else null

func new_world(slot: String) -> Dictionary:
	if session()==null: return R.fail("InvalidState","session")
	return session().start_session("sandbox",{"slot":slot,"seed":Crypto.new().generate_random_bytes(8).hex_encode(),
		"start_def":{},"content":_services.content})

func load_world(slot: String) -> Dictionary:
	if session()==null: return R.fail("InvalidState","session")
	return session().load_session(slot,_services.content)

func start_training() -> Dictionary:
	if session()==null: return R.fail("InvalidState","session")
	var mode: String="multiplayer" if _config.profile=="headless" and not _config.get("smoke",false) else "custom"
	var app: RefCounted=session()
	var state: Dictionary=app.query().value
	if state.state=="Frontend":
		var started: Dictionary=app.start_session(mode,{})
		if not started.ok:
			return started
	elif state.state=="CampaignMap" or state.state=="CustomSetup":
		mode="custom"
	elif state.state=="MultiplayerLobby":
		mode="multiplayer"
	else:
		return R.fail("InvalidState","training")
	var content: Dictionary=_services.content
	var scene: Dictionary=content.registry.get_definition("base:scene/training","scene").value.duplicate(true)
	var rules: Dictionary=content.registry.get_definition("base:ruleset/standard","ruleset").value
	scene["simulation_scene"]=Adapter.DEFAULT_SCENE
	var spec := {"schema_version":1,"encounter_id":"encounter/00000000-0000-4000-8000-000000000001",
		"reservation_revision":0,"mode":mode,"scene_def_id":scene.id,"ruleset_id":rules.id,
		"environment":{},"rng_seed":"1234567890abcdef","sides":[],"reserved_sources":[],
		"battle_limit":content.config.battle_limit,"deployment_constraints":{},"siege_snapshot":null}
	return app.prepare_mission(spec,scene,rules)

func training_step() -> Dictionary:
	if session()==null: return R.fail("InvalidState","session")
	var view: Dictionary=session().query("mission")
	if not view.ok:
		return view
	return session().step_fixed(view.value.tick+1,[])
