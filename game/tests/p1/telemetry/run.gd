extends SceneTree
const Diagnostics = preload("res://infrastructure/telemetry/diagnostics.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		print("FAIL ", label)
		failures += 1

func _initialize() -> void:
	var d := Diagnostics.new(4)
	for i in range(5):
		d.log({"level":"info","scope_id":"mission","command_id":"order","tick":i,"code":"frame",
			"token":"private-value","fields":{"count":i,"chat":"private-value","password":"private-value"}})
		d.observe("queue", i, {"scope_id":"mission"})
	var token := d.measure_span("startup", {"scope_id":"boot"})
	d.end_span(token)
	var report := d.export_report("session", {"scope_id":"mission"})
	check(report.records.size() == 4 and report.records[0].tick == 1 and report.dropped == 2,"bounded")
	check(report.metrics.size() == 1 and report.metrics[0].p50 == 2 and report.metrics[0].p99 == 4,"percentiles")
	check(not JSON.stringify(report).contains("private-value"),"redaction")
	report.records.clear()
	check(d.export_report("session").records.size() == 4,"detached evidence")
	d.log({"code":{"token":"private-value"},"level":"error"})
	var sanitized := d.export_report("session").records.back() as Dictionary
	check(sanitized.code == "event" and not JSON.stringify(sanitized).contains("private-value"),"malformed code filtered")
	var path := "user://p1-diagnostics-%d.json" % OS.get_process_id()
	var captured := d.capture_crash({"scope_id":"mission","token":"private-value"},path)
	check(captured.ok,"local crash capture")
	var disk := FileAccess.get_file_as_string(path)
	check(disk.contains("startup") and not disk.contains("private-value"),"local report")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures == 0:
		print("P1-TELEM-BOUNDARY PASS T-TELEM-01/02/03 slices")
	quit(1 if failures else 0)
