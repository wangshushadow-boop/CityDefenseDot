extends SceneTree
const Book = preload("res://application/receipt_book.gd")
const C = preload("res://contracts/canonical.gd")

func _initialize() -> void:
	var key0 := "%064x"%0
	var sample:=Book.record({},key0,key0,"first",1)
	var old:=Book.unpack(sample)
	var good: bool=old.ok and Book.replay(old.value,key0,key0).ok
	var archive:=sample.duplicate()
	for i in range(1,C.MAX_ITEMS):
		archive["%064x"%i]=sample[key0]
	var last:="%064x"%C.MAX_ITEMS
	archive=Book.record(archive,last,last,"last",2)
	var pages: Variant=Book.pack(archive)
	var encoded:=C.encode({"commands":pages,"results":{}})
	var restored:=Book.unpack(pages)
	good=good and encoded.ok and restored.ok and restored.value.size()==C.MAX_ITEMS+1
	good=good and Book.replay(restored.value,key0,key0).value.command_id=="first"
	good=good and Book.replay(restored.value,last,last).value.command_id=="last"
	good=good and not Book.unpack([pages[0],pages[0]]).ok
	print("APP_ARCHIVE count=",archive.size()," pages=",pages.size()," ", "PASS" if good else "FAIL")
	quit(0 if good else 1)
