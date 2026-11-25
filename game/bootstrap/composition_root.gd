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

const FieldSetup = preload("res://bootstrap/field_setup.gd")
var _campaign_settlement: Callable
var _save_owner: RefCounted
var _save_session := ""
var _field_authority: RefCounted
var _field_mission: WeakRef
var _field_launch := false
var _serial := 0

var _host: Node
var _registered := {}
var _active := {}
var _services := {}
var _stack := []
var _busy := false
var _ready_for_requests := false
var _config := {}
var _report := {}

func _init(host: Node, campaign_settlement: Callable = Callable()) -> void:
	_host=host
	_campaign_settlement=campaign_settlement

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
		if _field_launch:
			var runtime: Script = load("res://mission/runtime/field_mission.gd")
			var brains: Script = load("res://mission/runtime/field_brains.gd")
			if runtime == null or brains == null: return null
			var create_brains := func(scope,adapter,form,teams):return brains.new(scope,adapter,form,teams)
			var field: RefCounted = runtime.new(core,engine_adapter,mode,deps.content.registry,_field_principal,create_brains)
			_field_mission = weakref(field)
			return field
		# Only the CI replay restores a fixed authority-issued instance ID.
		return Mission.new(core,engine_adapter,mode,Callable(),"mission/p1-training-replay" if replay else "")
	# The frontend exposes world and training actions only. A gameplay exchange
	# needs an installed trusted authority rather than a caller-supplied identity.
	return R.ok(Session.new(deps.persistence,func(): return Camp.new(),mission_factory,_field_permit,_campaign_settlement,_receive_match_result,_field_gateway))

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
	_save_owner=null
	_save_session=""
	_field_authority=null
	_field_mission=null
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
	var loaded: Dictionary = session().load_session(slot,_services.content)
	if loaded.ok:
		_save_owner = RefCounted.new()
		_save_session = session().query().value.session_id
	return loaded

func pending_result() -> Dictionary:
	if session()==null or _save_owner==null: return R.fail("Unauthorized","pending.result")
	return session().query("pending_result",{"context":_save_owner})

func has_campaign_settlement() -> bool:
	return _campaign_settlement.is_valid()

func resume_result() -> Dictionary:
	var saved := pending_result()
	if not saved.ok: return saved
	var receipt: Dictionary = session().route_result(saved.value)
	if not receipt.ok: return receipt
	return session().dispose_mission()

func _receive_match_result(result: Dictionary) -> Dictionary:
	if not has_field() or result.get("encounter_id")!=null:
		return R.fail("Unauthorized","field_match")
	# A match result belongs to this server process. The P6 network transport consumes the same session route.
	_report["last_match"] = {"result_id":result.result_id,"mission_id":result.mission_id,"outcome":result.outcome,
		"winner_team_keys":result.winner_team_keys.duplicate(),"integrity_hash":result.integrity_hash}
	return R.ok(_report.last_match.duplicate(true))

func _field_principal(token: Variant) -> Dictionary:
	if _field_authority == null or not is_same(token,_field_authority):
		return R.fail("Unauthorized","field_authority")
	return R.ok({"issuer_id":"player","team_key":0})

func _field_permit(token: Variant, operation: String, envelope: Dictionary) -> Dictionary:
	if operation=="session.pending_result" and _save_owner!=null and is_same(token,_save_owner) and envelope.get("scope_id")==_save_session:
		return R.ok("save_owner")
	if not operation.begins_with("field."):
		return R.fail("Unauthorized","authority")
	var principal := _field_principal(token)
	return R.ok(principal.value.issuer_id) if principal.ok else principal

func _field_gateway(operation: String, payload: Dictionary, token: Variant) -> Dictionary:
	var field: RefCounted = _field_mission.get_ref() if _field_mission!=null else null
	if field == null: return R.fail("NotFound","field_mission")
	return field.gateway(operation,payload,token)

func has_field() -> bool:
	return _field_authority != null and _field_mission != null and _field_mission.get_ref() != null

func start_field(limit: int = -1, total: int = -1, seed_value: int = 241124) -> Dictionary:
	var app: RefCounted = session()
	if app == null or has_field(): return R.fail("InvalidState","field")
	var mode := "multiplayer" if _config.profile=="headless" else "custom"
	var state: Dictionary = app.query().value
	if state.state=="CampaignMap" or state.state=="CustomSetup": mode = "custom"
	if state.state=="MultiplayerLobby": mode = "multiplayer"
	if state.state not in ["Frontend","CampaignMap","CustomSetup","MultiplayerLobby"]: return R.fail("InvalidState","field")
	if limit==-1: limit = _services.content.config.battle_limit
	var setup := FieldSetup.build(_services.content,mode,limit,limit if total==-1 else total,seed_value)
	if not setup.ok: return setup
	if state.state=="Frontend":
		var opened: Dictionary = app.start_session(mode,{})
		if not opened.ok: return opened
	_field_launch = true
	_field_authority = RefCounted.new()
	_serial = 0
	var prepared: Dictionary = app.prepare_mission(setup.value.spec,setup.value.scene,setup.value.rules)
	_field_launch = false
	if not prepared.ok:
		_field_mission = null
		_field_authority = null
		if state.state=="Frontend": app.close_session("field_prepare")
	return prepared

func field_view(projection: String) -> Dictionary:
	return session().query("field",{"context":_field_authority,"projection":projection}) if has_field() else R.fail("NotFound","field")

func field_command(operation: String, payload: Dictionary, revision: int, stable_id: String = "") -> Dictionary:
	if not has_field(): return R.fail("NotFound","field")
	var scope: String = session().query().value.mission_id
	_serial += 1
	var body := payload.duplicate()
	body["type"] = operation
	var id := stable_id if not stable_id.is_empty() else "field/%s"%_serial
	var envelope := {"command_id":id,"actor_ref":"player","scope_id":scope,"expected_revision":revision,
		"issued_tick":revision,"sequence":null,"payload":body}
	return session().dispatch(envelope,_field_authority)

func field_step() -> Dictionary:
	if not has_field(): return R.fail("NotFound","field")
	var tick: int = session().query("mission").value.tick+1
	var done: Dictionary = session().step_fixed(tick,[])
	if not done.ok: return done
	for row in done.value.system_reports:
		if row.id=="field.rules" and row.value.get("outcome") != null:
			var result: Dictionary = session().finish_mission(row.value.outcome)
			if not result.ok: return result
			var routed: Dictionary = session().route_result(result.value)
			if not routed.ok: return routed
			break
	return done

func leave_field() -> Dictionary:
	if not has_field(): return R.fail("NotFound","field")
	var closed: Dictionary = session().dispose_mission()
	if closed.ok:
		_field_mission = null
		_field_authority = null
	return closed

func field_camera_sweep(queries: Array, stamp: Dictionary) -> Dictionary:
	if not has_field() or stamp.get("scope_id")!=session().query().value.mission_id:
		return R.fail("Unauthorized","camera_scope")
	return _services.engine.query_sweep_batch(queries,stamp)

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
