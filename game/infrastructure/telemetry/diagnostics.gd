extends RefCounted
## Bounded diagnostics owned by one session; game state is never retained.
const Result = preload("res://contracts/result.gd")
const FIELDS := ["scope_id", "revision", "tick", "entity_ref", "command_id", "result_id",
	"build", "content_hash", "seed", "phase", "module", "count", "elapsed_usec",
	"entities", "queue", "bytes", "status", "reason_code", "profile"]
var _limit: int
var _records: Array[Dictionary] = []
var _metrics := {}
var _dropped := 0

func _init(capacity: int = 256) -> void:
	_limit = clampi(capacity, 1, 65536)

func _context(source: Dictionary) -> Dictionary:
	var clean := {}
	for key: String in FIELDS:
		if not source.has(key):
			continue
		var value: Variant = source[key]
		if typeof(value) == TYPE_STRING:
			clean[key] = value.left(128)
		elif typeof(value) in [TYPE_INT, TYPE_BOOL]:
			clean[key] = value
	return clean

func log(record: Dictionary) -> void:
	var safe := _context(record)
	safe["at_usec"] = Time.get_ticks_usec()
	safe["fields"] = _context(record.fields) if typeof(record.get("fields")) == TYPE_DICTIONARY else {}
	safe["level"] = record.get("level") if record.get("level") in ["debug","info","warning","error"] else "info"
	var code: Variant = record.get("code")
	safe["code"] = code.left(80) if typeof(code) == TYPE_STRING and code.is_valid_ascii_identifier() else "event"
	if _records.size() == _limit:
		_records.pop_front()
		_dropped += 1
	_records.append(safe)

func measure_span(key: String, context: Dictionary = {}) -> Dictionary:
	return {"key":key, "start_usec":Time.get_ticks_usec(), "context":_context(context)}

func end_span(token: Dictionary) -> void:
	if typeof(token.get("start_usec")) == TYPE_INT and typeof(token.get("key")) == TYPE_STRING:
		observe(token.key, maxi(0, Time.get_ticks_usec() - token.start_usec), token.get("context", {}))

func observe(metric: String, value: float, tags: Dictionary = {}) -> void:
	if metric.is_empty() or not is_finite(value):
		return
	var safe_tags := _context(tags)
	var identity := JSON.stringify([metric, safe_tags], "", true)
	if not _metrics.has(identity):
		if _metrics.size() >= _limit:
			_dropped += 1
			return
		_metrics[identity] = {"key":metric, "tags":safe_tags, "samples":[]}
	var samples: Array = _metrics[identity].samples
	if samples.size() == _limit:
		samples.pop_front()
		_dropped += 1
	samples.append(value)

func export_report(session: String, filters: Dictionary = {}) -> Dictionary:
	var records := []
	var metrics := []
	for record: Dictionary in _records:
		if not filters.has("scope_id") or record.get("scope_id") == filters.scope_id:
			records.append(record.duplicate(true))
	for metric: Dictionary in _metrics.values():
		if filters.has("scope_id") and metric.tags.get("scope_id") != filters.scope_id:
			continue
		var sorted: Array = metric.samples.duplicate()
		sorted.sort()
		var row := {"key":metric.key, "tags":metric.tags.duplicate(true), "count":sorted.size()}
		for p in [50,95,99]:
			row["p%d" % p] = sorted[ceili(sorted.size() * p / 100.0) - 1]
		metrics.append(row)
	return {"session":session, "platform":OS.get_name(), "records":records, "metrics":metrics, "dropped":_dropped}

func capture_crash(context: Dictionary, path: String = "user://last-crash.json") -> Dictionary:
	var report := export_report(str(context.get("scope_id","")))
	report["context"] = _context(context)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.fail("Unavailable","report_path")
	file.store_string(JSON.stringify(report))
	file.flush()
	if file.get_error() != OK:
		return Result.fail("Unavailable","report_path")
	file.close()
	return Result.ok(path)
