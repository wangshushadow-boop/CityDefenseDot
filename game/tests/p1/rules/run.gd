extends SceneTree
const Rules = preload("res://shared/rules/numeric_policy.gd")
const Runtime = preload("res://core/runtime.gd")
class InvalidStream extends RefCounted:
	func next_u32() -> float:
		return 0.5

var errors := 0

func check(value: bool, id: String) -> void:
	print(id, " PASS" if value else " FAIL")
	if not value:
		errors += 1

func effect(id: String, scope: String, group: String, op: String, value: Variant, priority: int) -> Dictionary:
	return {"source_id":id,"scope":scope,"group":group,"operation":op,"value":value,"priority":priority}

func _initialize() -> void:
	var rows := [effect("foreign","party","", "add",999,1),
		effect("less","hero","perk","add",100,1),effect("best","hero","perk","add",3,2),
		effect("scale","hero","","multiply",{"numerator":2,"denominator":1},10)]
	var first := Rules.apply_effects(5,rows,"hero")
	rows.reverse()
	var other := Rules.evaluate("effects",{"base":5,"modifiers":rows,"scope":"hero"},{})
	check(first.ok and other.ok and first.value == other.value and first.value.final == 16 and first.value.steps[0].source_id == "best", "T-SHRULE-01")
	var fraction := {"numerator":9007199254740991,"denominator":2}
	check(Rules.round_money(1.125,"buy").value == 2 and Rules.round_money(1.125,"sell").value == 1 and Rules.round_money(fraction,"buy").value == 4503599627370496 and Rules.round_money(fraction,"sell").value == 4503599627370495,"T-SHRULE-02")
	check(Rules.apply_effects(250,[],"armor",{"max":100}).value.final == 100 and not Rules.apply_effects(NAN,[],"armor").ok and not Rules.apply_effects(1,[],"armor",{"min":3,"max":2}).ok and not Rules.round_money({"numerator":1,"denominator":0},"buy").ok,"T-SHRULE-03")
	var core := Runtime.new()
	core.open_scope("hero")
	var stream := core.derive_rng("hero","chance")
	var state := stream.snapshot()
	var a := Rules.evaluate("chance",{},{"numerator":1,"denominator":3},stream)
	stream.restore(state)
	check(a.ok and Rules.evaluate("chance",{},{"numerator":1,"denominator":3},stream) == a and not Rules.evaluate("chance",{},{"numerator":1,"denominator":3},InvalidStream.new()).ok and not Rules.round_money(true,"buy").ok,"P1-RULES-RNG")
	quit(1 if errors else 0)
