extends SceneTree

const C = preload("res://contracts/canonical.gd")
const S = preload("res://contracts/schema.gd")
const V = preload("res://contracts/values.gd")
const UUID := "b48883c0-79fb-4cd3-96fe-43bb44dfddbb"
var errors := 0

func check(value: bool, message: String) -> void:
	if not value:
		printerr("FAIL ",message)
		errors += 1

func group(label: String, before: int) -> void:
	print(label, " PASS" if errors == before else " FAIL")

static func with_digest(result: Dictionary) -> Dictionary:
	result = result.duplicate(true)
	result.erase("integrity_hash")
	result["integrity_hash"] = C.hash_value(result).value
	return result

func _initialize() -> void:
	var entry := {"source_party_id":"party/"+UUID,"troop_def_id":"base:troop/guard","hero_id":null,
		"count":2,"source_slot_range":[5,7],"loadout_snapshot_id":"stock"}
	var encounter := {"schema_version":1,"encounter_id":"encounter/"+UUID,"reservation_revision":2,
		"mode":"campaign","scene_def_id":"base:scene/field","ruleset_id":"base:rule/field",
		"environment":{},"rng_seed":"ffffffffffffffff","sides":[{"team_key":0,"faction_id":"base:faction/a",
		"commander_hero_id":null,"roster_allocations":[]}],"reserved_sources":[entry],"battle_limit":2,
		"deployment_constraints":{},"siege_snapshot":null}
	var row := {"source_slot_id":5,"end_status":"alive","wounded":false,"captor_team_key":null,"xp":1}
	var second := row.duplicate()
	second.source_slot_id = 6
	var result := with_digest({"schema_version":1,"result_id":"result-A","encounter_id":encounter.encounter_id,
		"mission_id":"mission-A","reservation_revision":2,"outcome":"victory","duration_ticks":12,
		"winner_team_keys":[0],"objective_results":[],"slot_outcomes":[row,second],"loot_claims":[],
		"hero_outcomes":[],"siege_changes":null,"reward_intents":[],"stats":{}})
	var before := errors
	check(S.validate_settlement(encounter,result).ok,"all source slots accounted")
	var duplicate := result.duplicate(true)
	duplicate.slot_outcomes[1].source_slot_id = 5
	var bad := S.validate_settlement(encounter,with_digest(duplicate))
	check(not bad.ok and bad.error.field.ends_with("source_slot_id"),"duplicate source location")
	duplicate = result.duplicate(true)
	duplicate.reservation_revision = 1
	check(S.validate_settlement(encounter,with_digest(duplicate)).error.code=="StaleVersion","stale reservation")
	duplicate = result.duplicate(true)
	duplicate.schema_version=2
	check(S.validate_shape("MissionResult",duplicate).error.code=="StaleVersion","bad schema version")
	check(S.validate_settlement(encounter,result).ok and result.slot_outcomes[1].source_slot_id==6,"input unchanged")
	group("T-CON-01",before)
	before=errors
	var local := {"protocol_version":1,"content_api_version":1,"content_hash":"ab".repeat(32)}
	check(S.check_compatible(local,local).ok,"matching handshake")
	for key in local:
		var remote := local.duplicate()
		remote[key] = "ff".repeat(32) if key=="content_hash" else 2
		bad = S.check_compatible(local,remote)
		check(not bad.ok and bad.error.field==key and bad.error.detail==local,"handshake "+key)
	var bool_version := local.duplicate()
	bool_version.protocol_version=true
	check(not S.check_compatible(local,bool_version).ok,"boolean version")
	group("T-CON-02",before)
	before=errors
	var old := '{"minutes":12,"schema_version":0}'.to_utf8_buffer()
	var migrated := S.decode_value("SaveHeader",old,0)
	check(migrated.ok and migrated.value=={"schema_version":1,"game_minute":12},"supported migration")
	check(not S.decode_value("SaveHeader",'{"extra":0,"minutes":12,"schema_version":0}'.to_utf8_buffer(),0).ok,"unknown critical field")
	check(not S.decode_value("SaveHeader",old,3).ok,"unknown version")
	check(old.get_string_from_utf8()=='{"minutes":12,"schema_version":0}',"migration preserves old bytes")
	group("T-CON-03",before)
	before=errors
	check(C.hash_value({"schema_version":1,"game_minute":12}).value=="bafa46fb93c768558e0945e9e95d714e0a4626a5e64bd66c31262526ed96b2f6","Python canonical digest")
	check(C.decode_source(' { "a":12, "\\u0062" : [true, null] } '.to_utf8_buffer()).value=={"a":12,"b":[true,null]},"editor input")
	for text in ['01','-01','+1','1e3','1.0','truefalse','[,1]','[1,]','[','{','{"a":1,"\\u0061":2}','"\\ud800"','"\\udc00"','"\\q"','9007199254740992','-9007199254740992','"e\\u0301"']:
		check(not C.decode_source(text.to_utf8_buffer()).ok,"reject "+text)
	for text in [' {"a":1}','-0','"\\u0061"','{"b":1,"a":2}']:
		check(not C.decode(text.to_utf8_buffer()).ok,"noncanonical "+text)
	for text in ['"\\u0000"','"\\u0000é\\u0000\\u0000猫\\u0000"','["",""]']:
		var parsed := C.decode(text.to_utf8_buffer())
		check(parsed.ok and C.encode(parsed.value).value==text.to_utf8_buffer(),"NUL/array "+text)
	check(C.decode('"\\u0000"'.to_utf8_buffer()).value.get_typed_builtin() == TYPE_STRING_NAME,"lossless NUL host type")
	check(not C.decode_source('{"\\u0000":0}'.to_utf8_buffer()).ok,"NUL key")
	check(not C.encode({"x":1.0}).ok and not C.encode({"x":NodePath("node")}).ok,"unsupported values")
	for cp in [8,9,10,12,13,31]:
		var control := C.encode(String.chr(cp))
		check(control.ok and C.decode(control.value).value==String.chr(cp),"control %d" % cp)
	check(C.decode('9007199254740991'.to_utf8_buffer()).value==9007199254740991,"exact upper bound")
	check(C.decode('"한글é猫🚀"'.to_utf8_buffer()).ok,"full Unicode")
	check(V.typed_id("hero/"+UUID,"hero") and not V.typed_id("party/"+UUID,"hero"),"persistent scope")
	check(V.def_id("mod:troop/guard") and not V.def_id("mod:troop/.."),"DefId")
	check(V.millimeters(-0.0005).value==-1 and not V.millimeters(2147483.648).ok,"rounding/range")
	check(V.resolve_handle("m",{"index":1,"generation":2},"m",{1:2}).ok,"live handle")
	check(not V.resolve_handle("m",{"index":1,"generation":1},"m",{1:2}).ok,"retired handle")
	var cmd := {"command_id":"q","actor_ref":"a","scope_id":"s","expected_revision":null,"issued_tick":null,"sequence":null,"payload":{"count":1}}
	var wire := S.encode_value("CommandEnvelope",cmd)
	check(wire.ok and S.decode_value("CommandEnvelope",wire.value).value==cmd,"complete command")
	cmd.erase("sequence")
	check(not S.validate_shape("CommandEnvelope",cmd).ok,"missing nullable key")
	var payload := {"sub":[{"name": PackedStringArray(["a","b"])}]}
	cmd["sequence"] = null
	cmd["payload"] = payload
	var read := S.validate_shape("CommandEnvelope",cmd)
	check(read.ok and read.value.is_read_only() and read.value.payload.is_read_only() and read.value.payload.sub.is_read_only() and read.value.payload.sub[0].is_read_only() and read.value.payload.sub[0].name.is_read_only(),"deep read-only contract and NUL text")
	payload.sub[0].name[0] = "changed"
	check(read.value.payload.sub[0].name[0]==&"a","original container detached")
	var huge := []
	huge.resize(C.MAX_ITEMS + 1)
	check(not C.encode(huge).ok and not C.decode_source(("["+"0,".repeat(C.MAX_ITEMS)+"0]").to_utf8_buffer()).ok,"bounded batch encode and parse")
	check(not S.validate_shape("CommandEnvelope",cmd,true).ok,"strict API version type")
	var move := {"actor_handle":{"index":0,"generation":1},"desired_direction":[1,0,0],"speed_fraction":0.0,"stance":null}
	for fraction in [0,0.0000005,0.5,1]:
		move.speed_fraction = fraction
		check(S.validate_shape("MoveIntent",move).ok,"domain speed %s" % fraction)
		var encoded_move := S.encode_value("MoveIntent",move)
		var parts := C.decode(encoded_move.value)
		check(typeof(parts.value.speed_fraction)==TYPE_INT and parts.value.speed_fraction == roundi(float(fraction)*S.SPEED_SCALE),"integer wire speed %s" % fraction)
		var decoded_move := S.decode_value("MoveIntent",encoded_move.value)
		check(decoded_move.ok and S.encode_value("MoveIntent",decoded_move.value).value==encoded_move.value,"round trip speed %s" % fraction)
	var batch := {"mission_id":"m","source_tick":0,"control_revision":1,"inputs":[move]}
	var encoded_batch := S.encode_value("IntentBatch",batch)
	check(encoded_batch.ok and S.decode_value("IntentBatch",encoded_batch.value).value.inputs[0].speed_fraction==1.0,"batch typed motion")
	for invalid_fraction in [-0.1,1.1,true,NAN,INF]:
		move.speed_fraction=invalid_fraction
		check(not S.validate_shape("MoveIntent",move).ok,"invalid speed")
	move.speed_fraction=1000001
	check(not S.decode_value("MoveIntent",C.encode(move).value).ok,"wire speed overflow")
	batch.inputs = [{"test":1}]
	check(not S.validate_shape("IntentBatch",batch).ok,"unknown intent")
	var nul := PackedStringArray(["a","b"])
	var receipt := {"command_id":"q","status":"ok","committed_revision":null,"errors":[],"view_changes":nul}
	check(not S.validate_shape("CommandReceipt",receipt).ok and not S.decode_value("CommandReceipt",C.encode(receipt).value).ok,"NUL string is not array")
	receipt.view_changes=[]
	receipt.errors=nul
	check(not S.decode_value("CommandReceipt",C.encode(receipt).value).ok,"NUL string is not typed array")
	batch.inputs=nul
	check(not S.decode_value("IntentBatch",C.encode(batch).value).ok,"NUL string is not inputs")
	var diagnostic := {"code":"Conflict","message_key":"error.conflict","field":nul,"detail":null,"retryable":false}
	var read_text := S.decode_value("DomainError",C.encode(diagnostic).value)
	check(read_text.ok and C.is_text(read_text.value.field) and not C.is_json_array(read_text.value.field),"NUL field text round trip")
	diagnostic.field=["", ""]
	check(not S.validate_shape("DomainError",diagnostic).ok,"JSON array is not text")
	diagnostic.field=null
	diagnostic.message_key="not\\nvalid".c_unescape()
	check(not S.validate_shape("DomainError",diagnostic).ok,"control in identifier")
	diagnostic.message_key=nul
	check(not S.validate_shape("DomainError",diagnostic).ok,"NUL in identifier")
	check(S.map_error("StaleVersion")=="error.stale_version","localized error code")
	check(not V.millimeters(true).ok and not V.yaw_microradians("0").ok,"numeric units reject bad types")
	group("P1-CON-BOUNDARY",before)
	print("CON_CHECKS errors=",errors)
	quit(0 if errors==0 else 1)
