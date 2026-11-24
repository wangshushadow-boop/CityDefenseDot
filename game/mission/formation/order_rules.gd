extends RefCounted
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const Layout = preload("res://mission/formation/slot_layout.gd")
## Internal field-mode registration: (default queue policy, completion condition).
const FIELD_ORDERS := {
	"move":["replace","arrived"], "follow":["replace","executed"], "hold":["replace","executed"],
	"advance":["append","executed"], "retreat":["replace","executed"], "charge":["replace","executed"],
	"free_attack":["replace","executed"], "cancel":["replace","executed"],
	"face":["immediate","executed"], "face_enemy":["immediate","executed"], "layout":["immediate","executed"],
	"fire_at_will":["immediate","executed"], "hold_fire":["immediate","executed"], "use_ranged":["immediate","executed"],
	"mount":["immediate","executed"], "dismount":["immediate","executed"], "keep_distance":["immediate","executed"],
	"assign_members":["immediate","executed"], "split":["immediate","executed"], "merge":["immediate","executed"],
	"delegate":["immediate","executed"], "appoint_captain":["immediate","executed"]}
const ORGANIZE := ["assign_members","split","merge","delegate","appoint_captain"]
const FIELDS := {"layout":["layout"], "face":["facing_microradians"], "keep_distance":["distance_mm"],
	"assign_members":["members","source_id"], "split":["new_formation_id","members"], "merge":["source_id"],
	"delegate":["actor"], "appoint_captain":["actor"]}

static func policy(order: Dictionary) -> String:
	return order.parameters.get("queue_policy", FIELD_ORDERS[order.order_type][0])

static func completion(order: Dictionary) -> String:
	return order.parameters.get("completion_condition", FIELD_ORDERS[order.order_type][1])

## The v1 envelope is validated by contracts/schema.gd before these mode-specific rules.
static func validate(order: Dictionary) -> Dictionary:
	var kind: String = order.order_type
	if kind not in FIELD_ORDERS:
		return R.fail("InvalidArgument", "order_type")
	if (kind == "move") != (order.target_position != null) or (kind in ["charge","follow","face_enemy"]) != (order.target_formation_id != null):
		return R.fail("InvalidArgument", "target")
	var p: Dictionary = order.parameters
	for key in p:
		if key not in ["queue_policy","completion_condition","expires_tick"] and key not in FIELDS.get(kind, []):
			return R.fail("InvalidArgument", "parameters")
	if p.has("queue_policy") and (p.queue_policy not in ["replace","append"] or (FIELD_ORDERS[kind][0] == "immediate" or (kind == "cancel" and p.queue_policy != "replace"))):
		return R.fail("InvalidArgument", "queue_policy")
	if p.has("expires_tick") and not V.integer(p.expires_tick, order.issued_tick):
		return R.fail("InvalidArgument", "expires_tick")
	if p.get("completion_condition", "executed") not in ["executed","arrived"] or (p.get("completion_condition") == "arrived" and kind != "move"):
		return R.fail("InvalidArgument", "completion_condition")
	if kind in ORGANIZE and order.formation_ids.size() != 1:
		return R.fail("InvalidArgument", "formation_ids")
	if kind in ["delegate","appoint_captain"] and typeof(p.get("actor")) != TYPE_STRING:
		return R.fail("InvalidArgument", "actor")
	if kind in ["split","assign_members"] and typeof(p.get("members")) != TYPE_ARRAY:
		return R.fail("InvalidArgument", "members")
	if (kind == "merge" or p.has("source_id")) and not V.integer(p.get("source_id"), 0, V.MAX_U32):
		return R.fail("InvalidArgument", "source_id")
	if kind == "split" and not V.integer(p.get("new_formation_id"), 0, V.MAX_U32):
		return R.fail("InvalidArgument", "new_formation_id")
	if kind == "keep_distance" and not V.integer(p.get("distance_mm"), 0, 2147483647):
		return R.fail("InvalidArgument", "distance_mm")
	if kind == "layout" and p.get("layout") not in Layout.KINDS:
		return R.fail("InvalidArgument", "layout")
	if kind == "face" and not V.integer(p.get("facing_microradians"), -3141593, 3141593):
		return R.fail("InvalidArgument", "facing_microradians")
	return R.ok()
