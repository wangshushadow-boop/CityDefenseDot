extends SceneTree

const S = preload("res://contracts/schema.gd")
const C = preload("res://contracts/canonical.gd")
const V = preload("res://contracts/values.gd")
const UUID := "988fc82e-13ab-4dad-a6e1-52973d4a8799"
const H := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
var good := 0
var bad := 0

func check(label:String, condition:bool) -> void:
	if condition:
		good+=1
	else:
		bad+=1
		printerr("FAIL ",label)

func err(receipt:Dictionary, code:String, field:String) -> bool:
	return receipt.get("ok") == false and receipt.get("error",{}).get("code") == code and field in str(receipt.get("error",{}).get("field"))

func sign_result(data:Dictionary) -> Dictionary:
	var copy:=data.duplicate(true)
	copy.erase("integrity_hash")
	copy["integrity_hash"]=C.hash_value(copy).value
	return copy

func run_probe() -> bool:
	var legacy:="{\"minutes\":0,\"schema_version\":0}".to_utf8_buffer()
	var migration:=S.decode_value("SaveHeader",legacy,0)
	check("old minute zero",migration.ok and migration.value == {"schema_version":1,"game_minute":0})
	for invalid in ['{"minutes":false,"schema_version":0}', '{"minutes":0,"schema_version":false}', '{"minutes":1,"schema_version":0,"unknown":null}', '{"minutes":-1,"schema_version":0}']:
		check("bad migration "+invalid,err(S.decode_value("SaveHeader",invalid.to_utf8_buffer(),0),"InvalidArgument","SaveHeader"))
	check("missing migration",err(S.decode_value("SaveHeader",legacy,2),"StaleVersion","schema_version"))
	var current:={"schema_version":1,"game_minute":0}
	check("current minute zero",S.validate_shape("SaveHeader",current).ok)
	current["flags"]=null
	check("new current field",err(S.validate_shape("SaveHeader",current),"InvalidArgument","flags"))
	var local:={"protocol_version":1,"content_api_version":1,"content_hash":H}
	for field in local:
		var remote:=local.duplicate()
		remote[field]="0".repeat(64) if field=="content_hash" else 2
		var rejected:=S.check_compatible(local,remote)
		check("compat mismatch "+field,err(rejected,"StaleVersion",field) and rejected.error.detail==local)
	for v in [true,1.0,{},null,-1,9007199254740992]:
		var remote:=local.duplicate()
		remote.protocol_version=v
		check("compat strict type "+str(v),err(S.check_compatible(local,remote),"InvalidArgument","protocol_version"))
	check("compat accepted",S.check_compatible(local,local.duplicate()).ok)
	var source:={"source_party_id":"party/"+UUID,"troop_def_id":"base:troop/horse","hero_id":null,"count":2,"source_slot_range":[4294967294,4294967296],"loadout_snapshot_id":"kit"}
	var encounter:={"schema_version":1,"encounter_id":"encounter/"+UUID,"reservation_revision":0,"mode":"campaign","scene_def_id":"base:scene/grass","ruleset_id":"base:rules/land","environment":{},"rng_seed":"ffffffffffffffff","sides":[],"reserved_sources":[source],"battle_limit":2,"deployment_constraints":{},"siege_snapshot":null}
	var one:={"source_slot_id":4294967295,"end_status":"withdrawn","wounded":true,"captor_team_key":null,"xp":3}
	var two:={"source_slot_id":4294967294,"end_status":"not_spawned","wounded":false,"captor_team_key":null,"xp":0}
	var result:=sign_result({"schema_version":1,"result_id":"r","encounter_id":encounter.encounter_id,"mission_id":"m","reservation_revision":0,"outcome":"draw","duration_ticks":1,"winner_team_keys":[],"objective_results":[],"slot_outcomes":[one,two],"loot_claims":[],"hero_outcomes":[],"siege_changes":null,"reward_intents":[],"stats":{}})
	var settled:=S.validate_settlement(encounter,result)
	check("sparse boundary / reverse order",settled.ok)
	result.slot_outcomes[0].xp = 0
	check("receipt copy", settled.value.slot_outcomes[0].xp == 3)
	result.slot_outcomes[0].xp = 3
	for pair in [["repeat",4294967295],["wrong source",2]]:
		var modified:=result.duplicate(true)
		modified.slot_outcomes[1].source_slot_id=pair[1]
		check(pair[0],err(S.validate_settlement(encounter,sign_result(modified)),"Conflict","source_slot_id"))
	var missing:=result.duplicate(true)
	missing.slot_outcomes.pop_front()
	check("missing source",err(S.validate_settlement(encounter,sign_result(missing)),"Conflict","slot_outcomes"))
	var stale:=result.duplicate(true)
	stale.reservation_revision=1
	check("stale reservation",err(S.validate_settlement(encounter,sign_result(stale)),"StaleVersion","reservation_revision"))
	var checksum:=result.duplicate(true)
	checksum.duration_ticks=2
	check("checksum",err(S.validate_settlement(encounter,checksum),"Conflict","integrity_hash"))
	var not_spawned:=result.duplicate(true)
	not_spawned.slot_outcomes[1].xp=1
	check("unspawned XP",err(S.validate_settlement(encounter,sign_result(not_spawned)),"InvalidArgument","not_spawned"))
	var overlapping:=encounter.duplicate(true)
	overlapping.reserved_sources.append(source)
	check("overlap",err(S.validate_settlement(overlapping,result),"Conflict","source_slot_range"))
	var hero:=encounter.duplicate(true)
	hero.reserved_sources[0].hero_id="hero/"+UUID
	check("hero count",err(S.validate_settlement(hero,result),"InvalidArgument","count"))
	var pending:=result.duplicate(true)
	pending.erase("siege_changes")
	check("nullable key required",err(S.validate_shape("MissionResult",pending),"InvalidArgument","siege_changes"))
	var nested:=result.duplicate(true)
	nested.slot_outcomes[0].unexpected=true
	check("nested extra",err(S.validate_shape("MissionResult",nested),"InvalidArgument","unexpected"))
	var version:=result.duplicate(true)
	version.schema_version=2
	check("result schema",err(S.validate_settlement(encounter,version),"StaleVersion","schema_version"))
	for value in [0,4294967296,true]:
		check("generation "+str(value),err(V.resolve_handle("m",{"index":0,"generation":value},"m",{0:1}),"InvalidArgument","actor_handle"))
	check("foreign mission",err(V.resolve_handle("m",{"index":0,"generation":1},"q",{0:1}),"NotFound","actor_handle"))
	check("old generation",err(V.resolve_handle("m",{"index":0,"generation":1},"m",{0:2}),"NotFound","actor_handle"))
	check("live handle",V.resolve_handle("m",{"index":0,"generation":1},"m",{0:1}).ok)
	var move:={"actor_handle":{"index":0,"generation":1},"desired_direction":[0,0,-1],"speed_fraction":0.5,"stance":null}
	check("runtime half speed", S.validate_shape("MoveIntent", move).ok)
	var encoded := S.encode_value("MoveIntent", move)
	check("half speed millionths", encoded.ok and '"speed_fraction":500000' in encoded.value.get_string_from_utf8())
	if encoded.ok:
		var decoded := S.decode_value("MoveIntent", encoded.value)
		check("half speed readback", decoded.ok and decoded.value.speed_fraction == 0.5)
	var old_wire := '{"actor_handle":{"generation":1,"index":0},"desired_direction":[0,0,-1],"speed_fraction":1000001,"stance":null}'
	check("reject above full speed", not S.decode_value("MoveIntent", old_wire.to_utf8_buffer()).ok)
	var receipt_wire := '{"command_id":"r","committed_revision":0,"errors":[],"status":"ok","view_changes":%s}'
	var text_wire := '"pre\\u0000post"'
	var misplaced := S.decode_value("CommandReceipt", (receipt_wire % text_wire).to_utf8_buffer())
	check("NUL text cannot serve as array", err(misplaced, "InvalidArgument", "view_changes"))
	var list_wire := (receipt_wire % ('[' + text_wire + ']')).to_utf8_buffer()
	var list_receipt := S.decode_value("CommandReceipt", list_wire)
	check("array containing NUL text", list_receipt.ok and S.encode_value("CommandReceipt", list_receipt.value).value == list_wire)
	var field_wire := '{"code":"NotFound","detail":null,"field":%s,"message_key":"error.not_found","retryable":false}'
	var field_bytes := (field_wire % text_wire).to_utf8_buffer()
	var text_receipt := S.decode_value("DomainError", field_bytes)
	check("NUL text in typed field", text_receipt.ok and S.encode_value("DomainError", text_receipt.value).value == field_bytes)
	var array_in_text := S.decode_value("DomainError", (field_wire % '["pre","post"]').to_utf8_buffer())
	check("text field rejects ordinary JSON array", err(array_in_text, "InvalidArgument", "field"))
	return true

func _initialize() -> void:
	check("completed",run_probe())
	print("P1-QA-CON-SHAPES ",good," passed / ",bad," failed")
	quit(0 if bad==0 else 1)
