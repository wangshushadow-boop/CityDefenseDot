extends SceneTree

const Inv = preload("res://shared/inventory/inventory.gd")
const R = preload("res://contracts/result.gd")
const C = preload("res://contracts/canonical.gd")
const V = preload("res://contracts/values.gd")
const COIN := {"kind": "currency", "id": "base:currency/copper"}
const GRAIN := {"kind": "stock", "def_id": "base:item/grain", "modifier_id": null, "quality": 0}
const BLADE := {"kind": "instance", "id": "blade-1"}
const AXE := {"kind": "instance", "id": "axe-2"}
const LOC := {"buyer": {"kind": "account", "currency": "base:currency/copper"},
	"seller": {"kind": "account", "currency": "base:currency/copper"},
	"cart": {"kind": "inventory", "capacity": 100}, "pack": {"kind": "inventory", "capacity": 100},
	"hand": {"kind": "slot"}, "belt": {"kind": "slot"}}
var failures := 0
var saved := {}


func expect(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAIL ", label)
		failures += 1


func rejected(result: Dictionary, code: String) -> bool:
	return result.get("ok") == false and result.get("error", {}).get("code") == code


func row(holder: String, resource: Dictionary, amount: int) -> Dictionary:
	return {"holder": holder, "resource": resource, "amount": amount}


func fixture() -> Inv:
	var bank := Inv.new()
	var seeded := bank.initialize(LOC, [row("buyer", COIN, 60), row("cart", GRAIN, 14),
		row("pack", BLADE, 1), row("belt", AXE, 1)], authorize)
	expect(seeded.ok, "valid genesis")
	return bank


func authorize(reason: String, source_ref: String, _resource: Dictionary, _mint: bool) -> bool:
	return reason == "production" and source_ref == "workshop"


func line(src: Variant, dst: Variant, resource: Dictionary, amount: int,
		reason: String = "trade", source: String = "market") -> Dictionary:
	return {"src": src, "dst": dst, "resource": resource, "amount": amount, "reason": reason, "source_ref": source}


func tx(bank: Inv, id: String, lines: Array) -> Dictionary:
	var plan := bank.prepare_exchange(id, lines)
	return bank.commit(plan.value) if plan.ok else plan


func failure_atomicity() -> bool:
	var bank := fixture()
	var before := bank.snapshot()
	for legs in [[line("buyer","seller",COIN,61),line("cart","pack",GRAIN,1)],
			[line("buyer","seller",COIN,2),line("cart","pack",GRAIN,15)]]:
		expect(rejected(tx(bank, "trade-fail", legs), "InsufficientResource"), "reject unfunded exchange")
		expect(bank.snapshot() == before, "failed exchange leaves every fact unchanged")
	var hold := bank.reserve("hold", "r", "cart", GRAIN, 12, "caravan", 200)
	expect(hold.ok and bank.commit(hold.value).ok, "reserve 12 units")
	expect(bank.available("cart", GRAIN).value == 2, "reservation reduces available")
	var loaded := Inv.new()
	expect(loaded.restore(bank.snapshot(), authorize).ok and loaded.available("cart",GRAIN).value == 2,"save keeps reservation")
	var reward := loaded.mint_or_burn("reward","buyer",COIN,2,true,"production","workshop")
	expect(reward.ok and loaded.commit(reward.value).ok and loaded.balance("buyer").value == 62,"restored runtime authorization")
	before = bank.snapshot()
	expect(rejected(tx(bank,"bad",[line("cart","pack",GRAIN,3)]), "InsufficientResource"), "reserved stock blocked")
	expect(rejected(bank.release("release","r","other"), "Unauthorized"), "reservation owner")
	expect(bank.snapshot() == before, "failed reservation operations do not mutate")
	var consume := [{"op":"release","reservation_id":"r","owner":"caravan"},line("cart","pack",GRAIN,12)]
	expect(tx(bank, "deliver", consume).ok and bank.available("cart",GRAIN).value == 2, "consume reserved quantity once")
	var net := [line("cart","pack",GRAIN,3),line("pack","cart",GRAIN,3)]
	expect(tx(bank, "net", net).ok, "net all legs before rejecting")
	expect(rejected(tx(bank,"overflow",[line(null,"buyer",COIN,V.MAX_INTEGER,"production","workshop")]),"InvalidArgument"), "overflow")
	expect(rejected(tx(bank,"capacity",[line(null,"cart",GRAIN,99,"production","workshop")]),"InsufficientResource"), "capacity")
	expect(rejected(tx(bank,"bool",[line("cart","pack",GRAIN,1).merged({"amount":true}, true)]),"InvalidArgument"), "integer amount")
	expect(rejected(tx(bank,"forge",[line(null,"buyer",COIN,1,"production","anonymous")]),"Unauthorized"), "untrusted mint")
	before = bank.snapshot()
	expect(rejected(bank.prepare_transfer("decimal","buyer","seller",COIN,1.75,"trade","market"),"InvalidArgument"),"fractional transfer rejected")
	expect(rejected(bank.mint_or_burn("decimal","buyer",COIN,1.75,true,"production","workshop"),"InvalidArgument"),"fractional mint rejected")
	expect(rejected(bank.reserve("decimal","r","cart",GRAIN,1.75,"caravan"),"InvalidArgument"),"fractional reservation rejected")
	expect(rejected(bank.prepare_exchange("decimal",net,1.5),"InvalidArgument"),"fractional exchange revision rejected")
	expect(rejected(bank.prepare_transfer("decimal","buyer","seller",COIN,1,"trade","market",1.5),"InvalidArgument"),"fractional transfer revision rejected")
	expect(bank.snapshot() == before,"rejecting fractional inputs preserves all facts")
	return true


func equipment() -> bool:
	var bank := fixture()
	var before := bank.snapshot()
	expect(rejected(tx(bank,"duplicate",[line("pack","hand",BLADE,1),line("pack","belt",BLADE,1)]),"Conflict"),"same item two slots")
	expect(rejected(tx(bank,"occupied",[line("pack","belt",BLADE,1)]),"Conflict"), "occupied slot")
	expect(rejected(tx(bank,"wrong",[line("hand","cart",BLADE,1)]),"Conflict"), "wrong owner")
	expect(bank.snapshot() == before, "bad ownership leaves no trace")
	expect(tx(bank,"swap",[line("pack","belt",BLADE,1), line("belt","hand",AXE,1)]).ok,"atomic exchange")
	expect(bank.owner_of("blade-1").value == "belt" and bank.owner_of("axe-2").value == "hand", "single new owners")
	var corrupt := bank.snapshot()
	corrupt.state.owners["blade-1"] = "hand"
	before = bank.snapshot()
	var invalid := bank.restore(corrupt)
	expect(rejected(invalid,"Conflict") and bank.snapshot() == before,"reject bad saved owner atomically: " + str(invalid))
	var fresh := Inv.new()
	expect(rejected(fresh.initialize(LOC,[row("belt",BLADE,1),row("hand",BLADE,1)]),"Conflict"),"duplicate loadout at genesis")
	expect(fresh.initialize(LOC,[row("pack",BLADE,1)]).ok,"failed genesis remains retryable")
	return true


func durability() -> bool:
	var bank := fixture()
	var before := bank.snapshot()
	var legs := [line("buyer","seller",COIN,10),line("cart","pack",GRAIN,2)]
	var plan := bank.prepare_exchange("trade",legs,0).value as Dictionary
	var stale := bank.prepare_transfer("stale","buyer","seller",COIN,1,"trade","market").value as Dictionary
	var refuse := func(candidate: Dictionary, receipt: Dictionary):
		expect(candidate.state.applied.trade.receipt == receipt, "candidate includes dedup receipt")
		expect(bank.snapshot() == before, "not published before save")
		expect(rejected(bank.commit(stale),"InvalidState"), "no nested write while persisting")
		return R.fail("Unavailable","disk")
	expect(rejected(bank.commit(plan,refuse),"Unavailable") and bank.snapshot() == before,"disk failure rolls back")
	var persist := func(candidate: Dictionary, _receipt: Dictionary):
		saved = candidate.duplicate(true)
		candidate.state.owners.clear()
		return R.ok()
	var receipt := bank.commit(plan,persist)
	expect(receipt.ok and saved == bank.snapshot(), "durable snapshot equals published facts")
	expect(bank.commit(plan) == receipt and bank.snapshot() == saved, "same ID original receipt")
	expect(rejected(bank.commit(stale),"StaleVersion"),"stale plan rejected")
	expect(rejected(bank.prepare_exchange("trade",[line("buyer","seller",COIN,11)],0),"Conflict"),"same ID different payload")
	var changed_legs := legs.duplicate(true)
	changed_legs.reverse()
	expect(rejected(bank.prepare_exchange("trade",changed_legs,0),"Conflict"),"changed ledger line order conflicts")
	expect(bank.balance("buyer").value == 50 and bank.balance("seller").value == 10,"both sides committed")
	var entries := bank.ledger_for("trade").value as Array
	expect(entries.size() == 2 and entries[0].txn_id == "trade" and entries[1].line_id == 1,"indexed ledger legs")
	var bytes := C.encode(saved)
	var resumed := Inv.new()
	var loaded := resumed.restore(C.decode(bytes.value).value) if bytes.ok else bytes
	expect(loaded.ok,"canonical snapshot roundtrip: " + str(loaded))
	expect(resumed.commit(plan) == receipt and resumed.snapshot() == saved,"post-crash retry")
	var bad := saved.duplicate(true)
	bad.state.applied.trade.digest = "0".repeat(64)
	expect(rejected(resumed.restore(bad),"Conflict") and resumed.snapshot() == saved,"corrupt applied ID rejected")
	return true


func conservation() -> bool:
	var rng := RandomNumberGenerator.new()
	for seed_id in [7,19,83,517]:
		rng.seed = seed_id
		var bank := fixture()
		var total := 60
		var grain_total := 14
		for i in 100:
			var commodity := rng.randi_range(0,1) == 0
			var resource := GRAIN if commodity else COIN
			var holders := ["cart","pack"] if commodity else ["buyer","seller"]
			if rng.randi_range(0,1) == 1:
				holders.reverse()
			var amount := rng.randi_range(1,7)
			var op := rng.randi_range(0,2)
			var src: Variant = null if op == 0 else holders[0]
			var dst: Variant = null if op == 1 else holders[1]
			var receipt := tx(bank, str(i), [line(src,dst,resource,amount,"production","workshop")])
			var created := amount if op == 0 else (-amount if op == 1 else 0)
			if receipt.ok:
				if commodity:
					grain_total += created
				else:
					total += created
			else:
				expect(rejected(receipt,"InsufficientResource"),"random failure classified")
			var a: int = bank.balance("buyer").value
			var b: int = bank.balance("seller").value
			var c: int = bank.available("cart",GRAIN).value
			var d: int = bank.available("pack",GRAIN).value
			expect(mini(a,b) >= 0 and a+b == total and mini(c,d) >= 0 and c+d == grain_total,"seed %d step %d" % [seed_id,i])
		var reloaded := Inv.new()
		expect(reloaded.restore(bank.snapshot()).ok and reloaded.snapshot() == bank.snapshot(),"seed %d full history replay" % seed_id)
	return true


func _initialize() -> void:
	for suite in [["T-INV-01",failure_atomicity],["T-INV-02",equipment],["T-INV-03",durability],["T-INV-04",conservation]]:
		var before := failures
		expect(suite[1].call() == true, suite[0] + " completed")
		if failures == before:
			print("PASS ", suite[0])
	quit(0 if failures == 0 else 1)
