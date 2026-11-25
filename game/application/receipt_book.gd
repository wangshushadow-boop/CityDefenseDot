extends RefCounted

const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const S = preload("res://contracts/schema.gd")
const V = preload("res://contracts/values.gd")

static func key(identity: Variant) -> String:
	return C.hash_value(identity).value

static func replay(book: Dictionary, id: String, digest: String) -> Variant:
	if not book.has(id):
		return null
	if book[id].digest != digest:
		return R.fail("Conflict","request")
	return R.ok(book[id].receipt.duplicate(true))

static func entry(digest: String, cmd: String, revision: int) -> Dictionary:
	var receipt := {"command_id":cmd,"status":"committed","committed_revision":revision,"errors":[],"view_changes":[]}
	return {"digest":digest,"receipt":receipt}

static func record(book: Dictionary, id: String, digest: String, cmd: String, revision: int) -> Dictionary:
	var candidate := book.duplicate()
	candidate[id]=entry(digest,cmd,revision)
	return candidate

static func valid(book: Variant) -> bool:
	if typeof(book)!=TYPE_DICTIONARY:
		return false
	for id in book:
		var row: Variant = book[id]
		if not V.hex(id,64) or typeof(row)!=TYPE_DICTIONARY or row.size()!=2 or not V.hex(row.get("digest"),64):
			return false
		if not S.validate_shape("CommandReceipt",row.get("receipt")).ok:
			return false
	return true

# A pre-P1.1 archive, or a small current archive, is a flat map. Larger archives
# use ordered pages; directories can nest so no canonical container exceeds its budget.
const PAGE := 4096

static func pack(book: Dictionary) -> Variant:
	if book.size()<=C.MAX_ITEMS:
		return book
	var ids:=book.keys()
	ids.sort()
	var groups: Array=[]
	for first in range(0,ids.size(),PAGE):
		var leaf: Dictionary={}
		for i in range(first,mini(first+PAGE,ids.size())):
			leaf[ids[i]]=book[ids[i]]
		groups.append(leaf)
	while groups.size()>PAGE:
		var parents: Array=[]
		for first in range(0,groups.size(),PAGE):
			parents.append(groups.slice(first,first+PAGE))
		groups=parents
	return groups

static func unpack(data: Variant) -> Dictionary:
	if typeof(data)==TYPE_DICTIONARY:
		return R.ok(data) if valid(data) else R.fail("InvalidArgument","receipts")
	var restored := {}
	var pages: Array=[data]
	while not pages.is_empty():
		var item: Variant=pages.pop_back()
		if C.is_json_array(item) and item.size()>0 and item.size()<=PAGE:
			pages.append_array(item)
		elif typeof(item)==TYPE_DICTIONARY and valid(item) and item.size()<=PAGE:
			for id in item:
				if restored.has(id):
					return R.fail("Conflict","receipt_id")
				restored[id]=item[id]
		else:
			return R.fail("InvalidArgument","receipts")
	return R.ok(restored)
