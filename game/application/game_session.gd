extends RefCounted
## Composition injects ports. Only this instance changes the application's active mode and phase.
const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const S = preload("res://contracts/schema.gd")
const V = preload("res://contracts/values.gd")
const Book = preload("res://application/receipt_book.gd")
const FieldCommands = preload("res://application/field_commands.gd")
const FieldResults = preload("res://mission/results/ports/field_results.gd")
const RULES := {"story":{"campaign":true,"main_story":true},"sandbox":{"campaign":true,"main_story":false},
	"custom":{"campaign":false,"main_story":false},"multiplayer":{"campaign":false,"main_story":false}}

var _store: RefCounted
var _campaign_factory: Callable
var _mission_factory: Callable
var _authorize: Callable
var _settle: Callable
var _network_sink: Callable
var _field_gateway: Callable
var _field := false
var _field_receipts := {}
var _decision_digest := ""
var _camp: RefCounted
var _mission: RefCounted
var _mode := ""
var _phase := "Frontend"
var _id := ""
var _slot := ""
var _marker := ""
var _epoch := -1
var _commands := {}
var _results := {}
var _pending: Variant
var _spec := {}
var _final := {}
var _routed := {}
var _ended := false
var _paused := false
var _busy := false
var _ack_lost := false

func _init(persist: RefCounted, campaign_factory: Callable, mission_factory: Callable, authorize: Callable,
		settle: Callable = Callable(), network_sink: Callable = Callable(), field_gateway: Callable = Callable()) -> void:
	_store=persist
	_campaign_factory=campaign_factory
	_mission_factory=mission_factory
	_authorize=authorize
	_settle=settle
	_network_sink=network_sink
	_field_gateway=field_gateway

func _call(action: Callable, args: Array = []) -> Dictionary:
	if _busy:
		return R.fail("InvalidState","session.busy")
	_busy=true
	_ack_lost=false
	var response: Dictionary=action.callv(args)
	_busy=false
	return response

func start_session(mode: String, options: Dictionary) -> Dictionary:
	return _call(_start,[mode,options])

func load_session(slot: String, content: Dictionary) -> Dictionary:
	return _call(_load,[slot,content])

func save_session() -> Dictionary:
	return _call(_save)

func dispatch(envelope: Dictionary, context: Variant) -> Dictionary:
	return _call(_dispatch,[envelope,context])

func prepare_mission(spec: Dictionary, scene: Dictionary, ruleset: Dictionary) -> Dictionary:
	return _call(_prepare,[spec,scene,ruleset])

func step_fixed(tick: Variant, inputs: Array) -> Dictionary:
	return _call(_step,[tick,inputs])

func finish_mission(outcome: Dictionary) -> Dictionary:
	return _call(_finish,[outcome])

func route_result(result: Dictionary) -> Dictionary:
	return _call(_route,[result])

func dispose_mission() -> Dictionary:
	return _call(_dispose_mission)

func close_session(_reason: String = "") -> Dictionary:
	return _call(_close)

func request_pause(reason: String = "") -> Dictionary:
	if _busy or _phase not in ["CampaignMap","Mission"] or _mode=="multiplayer" or _spec.get("mode","")=="multiplayer":
		return R.fail("InvalidState","pause")
	_paused=not reason.is_empty()
	return R.ok(_paused)

func query(kind: String = "session", visibility: Dictionary = {}) -> Dictionary:
	if _busy:
		return R.fail("Unavailable","session.busy")
	match kind:
		"session":
			return R.ok({"session_id":_id,"state":_phase,"mode":_mode,"paused":_paused,
				"rules":RULES.get(_mode,{}).duplicate(),"mission_id":_mission_id()})
		"campaign":
			if _camp!=null and _spec.get("mode","campaign")=="campaign":
				return _camp.read_snapshot(visibility)
		"pending_result":
			return _call(_pending_result_view,[visibility])
		"field":
			return _call(_field_query,[visibility])
		"mission":
			if _mission!=null:
				var view: Dictionary=_mission.view()
				return R.ok({"mission_id":view.mission_id,"phase":view.phase,"tick":view.tick})
	return R.fail("NotFound","query")

func _pending_result_view(visibility: Dictionary) -> Dictionary:
	if _phase!="Results" or _mission!=null or _pending==null or _spec.get("mode")!="campaign":
		return R.fail("InvalidState","pending.result")
	var operation:="session.pending_result"
	var request:={"scope_id":_id,"payload":{"type":operation}}
	if visibility.size()!=1 or _issuer(visibility.get("context"),operation,request).is_empty():
		return R.fail("Unauthorized","pending.result")
	return S.validate_shape("MissionResult",_final)

func _field_query(visibility: Dictionary) -> Dictionary:
	if not _field or _mission==null or _phase not in ["Mission","Results","Recovery"] or not _field_gateway.is_valid():
		return R.fail("InvalidState","field.scope")
	var projection: Variant=visibility.get("projection")
	var scope:=_mission_id()
	if visibility.size()!=2 or not visibility.has("context") or projection not in ["hud","visual","camera","input"]:
		return R.fail("InvalidArgument","field.query")
	var payload := {"type":"field.view","scope_id":scope,"projection":projection}
	var token: Variant=visibility.context
	if _issuer(token,"field.view",{"scope_id":scope,"payload":payload}).is_empty():
		return R.fail("Unauthorized","field.view")
	return _field_gateway.call("field.view",payload,token)

func _issuer(context: Variant, operation: String, command: Dictionary) -> String:
	if context==null or not _authorize.is_valid():
		return ""
	var permit: Variant=_authorize.call(context,operation,command)
	if permit is Dictionary and is_same(permit.get("ok"),true) and permit.get("value") is String:
		return permit.value
	return ""

func _mission_id() -> String:
	return _mission.view().mission_id if _mission!=null else ""

static func _port(factory: Callable, args: Array, methods: Array) -> RefCounted:
	if not factory.is_valid():
		return null
	var candidate: Variant=factory.callv(args)
	if not candidate is RefCounted:
		return null
	for method: String in methods:
		if not candidate.has_method(method):
			return null
	return candidate

func _campaign_port() -> RefCounted:
	return _port(_campaign_factory,[],["create_world","restore","read_snapshot","save_snapshot","exchange","freeze_for_encounter","release_freeze","dispose"])

func _start(mode: String, options: Dictionary) -> Dictionary:
	if _phase!="Frontend" or not RULES.has(mode):
		return R.fail("InvalidState","mode")
	if RULES[mode].campaign:
		if not _campaign_factory.is_valid() or _store==null:
			return R.fail("Unavailable","campaign")
		if typeof(options.get("slot"))!=TYPE_STRING or typeof(options.get("seed"))!=TYPE_STRING or typeof(options.get("start_def"))!=TYPE_DICTIONARY or typeof(options.get("content"))!=TYPE_DICTIONARY:
			return R.fail("InvalidArgument","options")
		_phase="NewWorld"
		_camp=_campaign_port()
		if _camp==null:
			_clear()
			return R.fail("Unavailable","campaign_factory")
		var created: Dictionary=_camp.create_world(options.seed,options.start_def,options.content)
		if not created.ok:
			_clear()
			return created
		_slot=options.slot
		_mode=mode
		var saved:=_write(created.value,_commands,_results,null)
		if not saved.ok:
			_clear()
			return saved
		_phase="CampaignMap"
	else:
		_phase="CustomSetup" if mode=="custom" else "MultiplayerLobby"
	_mode=mode
	_id="session/"+Crypto.new().generate_random_bytes(16).hex_encode()
	return R.ok(_id)

func _write(world: Dictionary, commands: Dictionary, results: Dictionary, pending: Variant,
		result_id: String="", checkpoint_id: String="") -> Dictionary:
	var payload := {"schema_version":1,"world_id":world.world_id,"game_minute":world.game_minute,
		"content_hash":world.content_hash,"content_packages":world.content_packages,"revision":_epoch+1,
		"campaign":world,"session":{"mode":_mode,"commands":Book.pack(commands),"results":Book.pack(results),"pending":pending}}
	var ack: Dictionary
	if result_id!="":
		ack=_store.commit_critical(_slot,payload,result_id,_marker)
	elif checkpoint_id!="":
		ack=_store.write_prebattle_checkpoint(_slot,checkpoint_id,payload,_marker)
	else:
		ack=_store.save_game(_slot,payload,"session",_marker)
	if not ack.ok:
		# An I/O error can occur after marker publication. Determine whether this
		# exact proposed world and its receipts became visible before publishing RAM.
		var visible: Dictionary=_store.recover(_slot)
		if not visible.ok or visible.value.snapshot!=payload:
			return ack
		_marker=visible.value.manifest.commit_id
		_ack_lost=true
	else:
		_marker=ack.value.commit_id
	_epoch=payload.revision
	return R.ok({"commit_id":_marker})

func _load(slot: String, content: Dictionary) -> Dictionary:
	if _phase!="Frontend" or _store==null or not _campaign_factory.is_valid():
		return R.fail("InvalidState","load")
	var installed := {"content_hash":content.get("content_hash"),"content_packages":content.get("packages",content.get("content_packages"))}
	var loaded: Dictionary=_store.load_game(slot,installed)
	if not loaded.ok:
		return loaded
	var visible: Dictionary=_store.recover(slot)
	if not visible.ok or visible.value.snapshot!=loaded.value:
		return R.fail("StaleVersion","commit_id")
	var payload: Dictionary=loaded.value
	if payload.size()!=8 or not payload.has_all(["schema_version","world_id","game_minute","content_hash","content_packages","revision","campaign","session"]) or not V.integer(payload.revision):
		return R.fail("StaleVersion","session_snapshot")
	var book: Variant=payload.session
	if typeof(book)!=TYPE_DICTIONARY or book.size()!=4 or not book.has_all(["mode","commands","results","pending"]) or book.mode not in ["story","sandbox"]:
		return R.fail("InvalidArgument","session")
	var command_book:=Book.unpack(book.commands)
	var result_book:=Book.unpack(book.results)
	if not command_book.ok or not result_book.ok:
		return R.fail("InvalidArgument","receipts")
	var world: Variant=payload.campaign
	if typeof(world)!=TYPE_DICTIONARY or not world.has("freeze"):
		return R.fail("InvalidArgument","campaign")
	for field in ["world_id","game_minute","content_hash","content_packages"]:
		if world.get(field)!=payload[field]:
			return R.fail("Conflict",field)
	if book.pending!=null:
		if typeof(book.pending)!=TYPE_DICTIONARY or book.pending.size()!=2 or not book.pending.has_all(["spec","result"]):
			return R.fail("InvalidArgument","pending")
		var checked:=S.validate_shape("EncounterSpec",book.pending.spec)
		if not checked.ok or checked.value.mode!="campaign" or typeof(world.freeze)!=TYPE_DICTIONARY or world.freeze.get("encounter_id")!=checked.value.encounter_id or world.freeze.get("revision")!=checked.value.reservation_revision:
			return R.fail("Conflict","reservation")
		if book.pending.result!=null:
			if typeof(book.pending.result)!=TYPE_DICTIONARY or not S.validate_settlement(checked.value,book.pending.result).ok:
				return R.fail("Conflict","pending.result")
			if _saved_field(checked.value,book.pending.result) and not FieldResults.validate_source_coverage(checked.value,book.pending.result).ok:
				return R.fail("Conflict","pending.result")
	elif world.freeze!=null:
		return R.fail("Conflict","reservation")
	_phase="LoadWorld"
	_camp=_campaign_port()
	if _camp==null:
		_clear()
		return R.fail("Unavailable","campaign_factory")
	var restored: Dictionary=_camp.restore(world)
	if not restored.ok:
		_clear()
		return restored
	_slot=slot
	_mode=book.mode
	_marker=visible.value.manifest.commit_id
	_epoch=payload.revision
	_commands=command_book.value
	_results=result_book.value
	_pending=book.pending
	_id="session/"+Crypto.new().generate_random_bytes(16).hex_encode()
	_phase="CampaignMap"
	if _pending!=null:
		if _pending.result!=null:
			_spec=_pending.spec
			_final=_pending.result
			_field=_saved_field(_spec,_final)
			_phase="Results"
		else:
			_phase="Recovery"
			var released:=_cancel_checkpoint()
			if not released.ok:
				_clear()
				return released
	return R.ok(_id)

func _save() -> Dictionary:
	if _phase!="CampaignMap" or _camp==null:
		return R.fail("InvalidState","safe_point")
	var snapshot: Dictionary=_camp.save_snapshot()
	if not snapshot.ok:
		return snapshot
	return _write(snapshot.value,_commands,_results,null)

func _dispatch(envelope: Dictionary, context: Variant) -> Dictionary:
	if _field and _mission!=null:
		return _dispatch_field(envelope,context)
	if _camp==null or _phase!="CampaignMap":
		return R.fail("InvalidState","campaign")
	var checked:=S.validate_shape("CommandEnvelope",envelope)
	if not checked.ok:
		return checked
	var cmd: Dictionary=checked.value
	if not _authorize.is_valid():
		return R.fail("Unauthorized","authority")
	var permit: Variant=_authorize.call(context,"exchange",cmd)
	if typeof(permit)!=TYPE_DICTIONARY or permit.get("ok")!=true or typeof(permit.get("value"))!=TYPE_STRING or permit.value!=cmd.actor_ref:
		return R.fail("Unauthorized","actor_ref")
	var view: Dictionary=_camp.read_snapshot().value
	if cmd.scope_id!=view.world_id:
		return R.fail("Unauthorized","scope_id")
	var key:=Book.key([cmd.scope_id,permit.value,cmd.command_id])
	var digest:=Book.key(cmd)
	var old: Variant=Book.replay(_commands,key,digest)
	if old!=null:
		return old
	if cmd.expected_revision!=null and cmd.expected_revision!=view.revision:
		return R.fail("StaleVersion","expected_revision")
	if cmd.payload.size()!=2 or cmd.payload.get("type")!="exchange" or not C.is_json_array(cmd.payload.get("lines")):
		return R.fail("InvalidArgument","exchange")
	var next: Dictionary=Book.record(_commands,key,digest,cmd.command_id,view.revision+1)
	var durable:=func(world: Dictionary,_receipt: Dictionary):
		return _write(world,next,_results,null)
	var applied: Dictionary=_camp.exchange("app/command/"+key,cmd.payload.lines,-1,durable)
	if not applied.ok:
		return applied
	_commands=next
	return _ack(next[key].receipt)

func _dispatch_field(envelope: Dictionary, context: Variant) -> Dictionary:
	if not _field_gateway.is_valid():
		return R.fail("Unavailable","field.gateway")
	var parsed:=FieldCommands.prepare(envelope)
	if not parsed.ok:
		return parsed
	var cmd: Dictionary=parsed.value.cmd
	var operation: String=cmd.payload.type
	if cmd.scope_id!=_mission_id() or _issuer(context,operation,cmd)!=cmd.actor_ref:
		return R.fail("Unauthorized","field.authority")
	var digest:=Book.key(cmd)
	var replay: Variant=Book.replay(_field_receipts,cmd.command_id,digest)
	if replay!=null:
		if replay.ok and operation=="field.order":
			var grant: Dictionary=_field_gateway.call("field.check_order",parsed.value.local,context)
			if not grant.ok:
				return grant
		return replay
	if _phase!="Mission" or _ended or _paused:
		return R.fail("InvalidState","field.command")
	var applied: Dictionary=_field_gateway.call(operation,parsed.value.local,context)
	if not applied.ok:
		return applied
	var row:=Book.entry(digest,cmd.command_id,cmd.expected_revision)
	_field_receipts[cmd.command_id]=row
	return _ack(row.receipt)

func _ack(receipt: Dictionary) -> Dictionary:
	return R.fail("Unavailable","receipt") if _ack_lost else R.ok(receipt.duplicate(true))

func _prepare(spec: Dictionary, scene: Dictionary, ruleset: Dictionary) -> Dictionary:
	if _phase not in ["CampaignMap","CustomSetup","MultiplayerLobby"] or _mission!=null or not _mission_factory.is_valid():
		return R.fail("InvalidState","mission")
	var validated:=S.validate_shape("EncounterSpec",spec)
	if not validated.ok:
		return validated
	var candidate: Dictionary=validated.value
	var mode: String=candidate.mode
	if mode not in ["campaign","custom","multiplayer"] or (mode=="campaign" and _camp==null) or (_camp==null and mode!=_mode):
		return R.fail("Unauthorized","mode")
	var old_phase:=_phase
	var before := {}
	if mode=="campaign":
		var snapshot: Dictionary=_camp.save_snapshot()
		if not snapshot.ok:
			return snapshot
		before=snapshot.value
		if candidate.reservation_revision!=before.revision+1:
			return R.fail("StaleVersion","reservation_revision")
		_phase="Encounter"
		var token: Dictionary=_camp.freeze_for_encounter(candidate.encounter_id)
		if not token.ok:
			_phase=old_phase
			return token
		var proposed := {"spec":candidate,"result":null}
		var recorded:=_write(_camp.save_snapshot().value,_commands,_results,proposed,"",candidate.encounter_id)
		if not recorded.ok:
			_camp.restore(before)
			_phase=old_phase
			return recorded
		_pending=proposed
	_phase="LoadingMission"
	_mission=_port(_mission_factory,[mode],["prepare","view","step_fixed","request_end","finalize","dispose"])
	var prepared: Dictionary=R.fail("Unavailable","mission_factory") if _mission==null else _mission.prepare(candidate,scene,ruleset)
	if not prepared.ok:
		if _mission!=null:
			_mission.dispose()
			_mission=null
		if mode=="campaign":
			_phase="Recovery"
			var cleared:=_cancel_checkpoint(before)
			if not cleared.ok:
				return cleared
		_phase=old_phase
		return prepared
	_spec=candidate
	_field=ruleset.get("battle_mode")=="field" or _known_field(candidate)
	_field_receipts.clear()
	_decision_digest=""
	_final={}
	_routed={}
	_ended=false
	_paused=false
	_phase="Mission"
	return R.ok(_mission_id())

func _step(tick: Variant, inputs: Array) -> Dictionary:
	if _phase!="Mission" or _paused or _ended or not V.integer(tick,1):
		return R.fail("InvalidState","tick")
	if _field and not inputs.is_empty():
		return R.fail("Unauthorized","field.input")
	return _mission.step_fixed(tick,inputs)

static func _known_field(spec: Dictionary) -> bool:
	return spec.get("ruleset_id") in ["field:ruleset/field_battle","base:ruleset/field_battle"]

static func _saved_field(spec: Dictionary, result: Dictionary) -> bool:
	if _known_field(spec):
		return true
	for objective in result.objective_results:
		if objective is Dictionary and objective.get("id")=="field" and result.stats.has("teams"):
			return true
	return false

func _rule_decision() -> Variant:
	for report in _mission.view().get("system_reports",[]):
		if report.id=="field.rules" and report.phase=="objectives":
			return report.value.get("outcome")
	return null

func _same_finish(request: Dictionary, digest: String) -> bool:
	if request.has("result_id"):
		return not _final.is_empty() and S.validate_shape("MissionResult",request).ok and request==_final
	if not _decision_digest.is_empty():
		return digest==_decision_digest
	# A cold, pending field result preserves the complete result and its digest but not the
	# complete RULES decision (for example the team that requested withdrawal).
	return not _field and _final.get("winner_team_keys",[]).is_empty() and _final.get("objective_results",[]).is_empty() and request=={"outcome":_final.get("outcome")}

func _finish(outcome: Dictionary) -> Dictionary:
	var request_hash:=C.hash_value(outcome)
	if not request_hash.ok:
		return request_hash
	if _phase=="Results" and not _final.is_empty():
		return R.ok(_final.duplicate(true)) if _same_finish(outcome,request_hash.value) else R.fail("Conflict","outcome")
	if _phase not in ["Mission","Recovery"] or _mission==null:
		return R.fail("InvalidState","mission")
	if _ended and not _same_finish(outcome,request_hash.value):
		return R.fail("Conflict","outcome")
	if not _ended:
		if _field:
			var confirmed: Variant=_rule_decision()
			if not confirmed is Dictionary or Book.key(confirmed)!=request_hash.value:
				return R.fail("Conflict","field.outcome")
		var ending: Dictionary=_mission.request_end(outcome)
		if not ending.ok:
			return ending
		_ended=true
		_decision_digest=request_hash.value
	if _final.is_empty():
		var finished: Dictionary=_mission.finalize()
		if not finished.ok:
			return finished
		var value: Dictionary=finished.value
		if value.get("outcome")!=outcome.get("outcome"):
			return R.fail("Conflict","outcome")
		if _field:
			var coverage:=FieldResults.validate_source_coverage(_spec,value)
			if not coverage.ok:
				return coverage
			if value.mission_id!=_mission_id() or value.winner_team_keys!=outcome.winner_team_keys or value.objective_results!=outcome.objective_results:
				return R.fail("Conflict","field.result")
		_final=value
	var result: Dictionary=_final
	if _spec.mode=="campaign":
		var proposed := {"spec":_spec,"result":result}
		var persisted:=_write(_camp.save_snapshot().value,_commands,_results,proposed)
		if not persisted.ok:
			_phase="Recovery"
			return persisted
		_pending=proposed
	_final=result
	_phase="Results"
	return R.ok(_final.duplicate(true))

func _route(result: Dictionary) -> Dictionary:
	var validated:=S.validate_shape("MissionResult",result)
	if not validated.ok:
		return validated
	var value: Dictionary=validated.value
	var digest:=Book.key(value)
	var key:=Book.key(value.result_id)
	if value.encounter_id!=null and _camp!=null and _spec.get("mode","campaign")=="campaign":
		var prior: Variant=Book.replay(_results,key,digest)
		if prior!=null:
			return prior
	if _phase!="Results" or _final.is_empty() or value!=_final:
		return R.fail("Conflict","authoritative_result")
	if not _routed.is_empty():
		return R.ok(_routed.duplicate(true))
	if _spec.mode!="campaign":
		if _spec.mode=="multiplayer":
			if not _network_sink.is_valid():
				return R.fail("Unavailable","match_results")
			var accepted: Variant=_network_sink.call(value)
			if typeof(accepted)!=TYPE_DICTIONARY or accepted.get("ok")!=true:
				return R.fail("Unavailable","match_results")
		_routed={"result_id":value.result_id,"mode":_spec.mode,"outcome":value.outcome}
		return R.ok(_routed.duplicate(true))
	var valid:=S.validate_settlement(_spec,value)
	if not valid.ok:
		return valid
	if not _settle.is_valid():
		return R.fail("Unavailable","settlement_rule")
	var allocation: Variant=_settle.call(_spec,value)
	if typeof(allocation)!=TYPE_DICTIONARY or allocation.get("ok")!=true or not C.is_json_array(allocation.get("value")):
		return R.fail("InvalidArgument","settlement_rule")
	var frozen: Dictionary=_camp.save_snapshot().value
	var released: Dictionary=_camp.release_freeze(frozen.freeze)
	if not released.ok:
		return released
	var world: Dictionary=_camp.save_snapshot().value
	var lines: Array=allocation.value
	var next:=Book.record(_results,key,digest,value.result_id,world.revision+(0 if lines.is_empty() else 1))
	var written: Dictionary
	if lines.is_empty():
		written=_write(world,_commands,next,null,value.result_id)
	else:
		var durable:=func(proposed: Dictionary,_receipt: Dictionary):
			return _write(proposed,_commands,next,null,value.result_id)
		written=_camp.exchange("app/result/"+key,lines,-1,durable)
	if not written.ok:
		_camp.restore(frozen)
		return written
	_results=next
	_pending=null
	_routed=next[key].receipt
	return _ack(_routed)

func _cancel_checkpoint(before: Dictionary = {}) -> Dictionary:
	var frozen: Dictionary=_camp.save_snapshot().value
	var released: Dictionary=_camp.release_freeze(frozen.freeze)
	if not released.ok:
		return released
	if not before.is_empty():
		var reverted: Dictionary=_camp.restore(before)
		if not reverted.ok:
			_camp.restore(frozen)
			return reverted
	var recorded:=_write(_camp.save_snapshot().value,_commands,_results,null)
	if not recorded.ok:
		_camp.restore(frozen)
		return recorded
	_pending=null
	_phase="CampaignMap"
	return R.ok()

func _unrecorded_outcome() -> bool:
	if _final.is_empty() or not _routed.is_empty():
		return false
	return _spec.get("mode")!="campaign" or (_pending!=null and _pending.result==null)

func _dispose_mission() -> Dictionary:
	if _phase not in ["Mission","Results","Recovery"]:
		return R.fail("InvalidState","mission")
	if _unrecorded_outcome() or (_pending!=null and _pending.result!=null):
		return R.fail("InvalidState","unsettled_result")
	if _mission!=null:
		var stopped: Dictionary=_mission.dispose()
		if not stopped.ok:
			return stopped
		_mission=null
	if _pending!=null:
		_phase="Recovery"
		var cancelled:=_cancel_checkpoint()
		if not cancelled.ok:
			return cancelled
	_spec={}
	_field=false
	_field_receipts.clear()
	_decision_digest=""
	_final={}
	_routed={}
	_paused=false
	_ended=false
	if _camp!=null:
		_phase="CampaignMap"
	else:
		_phase="CustomSetup" if _mode=="custom" else "MultiplayerLobby"
	return R.ok()

func _close() -> Dictionary:
	if _unrecorded_outcome():
		return R.fail("InvalidState","unrecorded_outcome")
	if _mission!=null:
		var stopped: Dictionary=_mission.dispose()
		if not stopped.ok:
			return stopped
		_mission=null
	# An unfinished campaign result has already been committed as pending.
	# Closing drops runtime ownership, while the next session can resume settlement.
	_clear()
	return R.ok()

func _clear() -> void:
	if _camp!=null:
		_camp.dispose()
	_camp=null
	_mission=null
	_mode=""
	_phase="Frontend"
	_id=""
	_slot=""
	_marker=""
	_epoch=-1
	_pending=null
	_commands={}
	_results={}
	_field=false
	_field_receipts.clear()
	_decision_digest=""
	_spec={}
	_final={}
	_routed={}
	_ended=false
	_paused=false
