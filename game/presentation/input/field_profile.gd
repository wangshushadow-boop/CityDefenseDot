extends RefCounted
## Local presentation preferences. The canonical codec rejects non-data values.
const R = preload("res://contracts/result.gd")
const C = preload("res://contracts/canonical.gd")
const V = preload("res://contracts/values.gd")
const DEFAULT_NAME := "field-input"
var _path: String
const OPTIONS := {"deadzone_percent":18, "mouse_sensitivity":2500, "stick_sensitivity":35000,
	"invert_y":false, "toggle_block":false, "toggle_attack":false}
const BATTLE := {
	"move_left":[KEY_A, "a/0/-"], "move_right":[KEY_D, "a/0/+"],
	"move_forward":[KEY_W, "a/1/-"], "move_back":[KEY_S, "a/1/+"],
	"look_left":[KEY_LEFT,"a/2/-"], "look_right":[KEY_RIGHT,"a/2/+"],
	"look_up":[KEY_UP,"a/3/-"], "look_down":[KEY_DOWN,"a/3/+"],
	"attack":["m/1/0","a/5/+"], "block":["m/2/0","a/4/+"],
	"cancel_attack":[KEY_X,"j/1"], "sprint":[KEY_SHIFT,"j/7"], "crouch":[KEY_C,"j/8"],
	"jump":[KEY_SPACE,"j/0"], "equip_melee":[KEY_1,"j/13"], "equip_ranged":[KEY_2,"j/14"],
	"interact":[KEY_E,"j/2"], "mount":[KEY_F,"j/3"], "dismount":[KEY_G,"j/12"]}
const COMMAND := {
	"select_all":[KEY_0,"j/2"], "select_prev":[KEY_BRACKETLEFT,"j/13"], "select_next":[KEY_BRACKETRIGHT,"j/14"],
	"order_move":["m/1/0","j/0"], "order_charge":[KEY_R,"j/3"], "order_hold":[KEY_H,"j/1"],
	"cycle_layout":[KEY_F,"j/10"], "delegate":[KEY_G,"j/9"], "order_cancel":[KEY_X,"j/12"]}
const GLOBAL := {"menu":[KEY_ESCAPE,"j/6"], "command_mode":[KEY_TAB,"j/4"]}
var bindings: Dictionary
var options := OPTIONS.duplicate()

func _init(name: String = DEFAULT_NAME) -> void:
	_path = "user://"+name+".json" if name.is_valid_identifier() or name == DEFAULT_NAME else ""
	bindings = _defaults()

static func _defaults() -> Dictionary:
	var all := GLOBAL.duplicate()
	all.merge(BATTLE)
	all.merge(COMMAND)
	for i in range(1,10):
		all["select_" + str(i)] = [KEY_0+i]
	var result := {}
	for action in all:
		var slots := {}
		for code in all[action]:
			var token := "k/%d/0" % code if typeof(code) == TYPE_INT else str(code)
			slots[family(token)] = token
		result[action] = slots
	return result

static func family(token: String) -> String:
	return "pad" if token.begins_with("a/") or token.begins_with("j/") else "desktop"

static func scope(action: String) -> String:
	if GLOBAL.has(action): return "global"
	return "battle" if BATTLE.has(action) else "command"

static func _overlap(a: String, b: String) -> bool:
	return scope(a) == scope(b) or scope(a) == "global" or scope(b) == "global"

static func token_for(event: InputEvent) -> String:
	var mods := 0
	if event is InputEventWithModifiers:
		mods = int(event.shift_pressed) + 2*int(event.ctrl_pressed) + 4*int(event.alt_pressed) + 8*int(event.meta_pressed)
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]: mods = 0
		return "k/%d/%d" % [code, mods] if code > 0 else ""
	if event is InputEventMouseButton:
		return "m/%d/%d" % [event.button_index, mods]
	if event is InputEventJoypadButton:
		return "j/%d" % event.button_index
	if event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5:
		return "a/%d/%s" % [event.axis, "+" if event.axis_value > 0 else "-"]
	return ""

func action_for(token: String, mode: String) -> String:
	for action in bindings:
		if scope(action) not in [mode,"global"]:
			continue
		if bindings[action].get(family(token)) == token:
			return action
	return ""

func _set_binding(table: Dictionary, action: String, token: String) -> Dictionary:
	if not table.has(action) or token.is_empty():
		return R.fail("InvalidArgument","binding")
	var parts := token.split("/")
	if parts.size() < 2 or not parts[1].is_valid_int():
		return R.fail("InvalidArgument","binding")
	var n := parts[1].to_int()
	match parts[0]:
		"k","m":
			if parts.size() != 3 or n <= 0 or not parts[2].is_valid_int() or not V.integer(parts[2].to_int(),0,15):
				return R.fail("InvalidArgument","binding")
		"j":
			if parts.size() != 2 or not V.integer(n,0,JOY_BUTTON_MAX-1): return R.fail("InvalidArgument","binding")
		"a":
			if parts.size() != 3 or not V.integer(n,0,JOY_AXIS_MAX-1) or parts[2] not in ["+","-"]: return R.fail("InvalidArgument","binding")
		_: return R.fail("InvalidArgument","binding")
	if action == "menu":
		return R.fail("Unauthorized","reserved_menu")
	for other in table:
		if other != action and _overlap(action,other) and table[other].get(family(token)) == token:
			return R.fail("Conflict","binding." + other)
	table[action][family(token)] = token
	return R.ok()

static func _settings(candidate: Dictionary) -> bool:
	if candidate.size() != OPTIONS.size():
		return false
	for key in OPTIONS:
		var value: Variant = candidate.get(key)
		if typeof(OPTIONS[key]) == TYPE_BOOL:
			if typeof(value) != TYPE_BOOL: return false
		elif key == "deadzone_percent":
			if not V.integer(value,0,95): return false
		elif not V.integer(value,1,1000000):
			return false
	return true

func _save(table: Dictionary, settings: Dictionary) -> Dictionary:
	if _path.is_empty(): return R.fail("InvalidArgument","input_profile")
	var bytes := C.encode({"bindings":table,"options":settings})
	if not bytes.ok: return bytes
	var temp := _path + "." + ResourceUID.id_to_text(ResourceUID.create_id()).trim_prefix("uid://") + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return R.fail("Unavailable","input_profile")
	file.store_buffer(bytes.value)
	file.flush()
	var success := file.get_error() == OK
	file.close()
	if not success or DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return R.fail("Unavailable","input_profile")
	bindings = table
	options = settings
	return R.ok()

func rebind(action: String, event: InputEvent) -> Dictionary:
	var table := bindings.duplicate(true)
	var result := _set_binding(table,action,token_for(event))
	return _save(table,options) if result.ok else result

func set_options(changes: Dictionary) -> Dictionary:
	var candidate := options.duplicate()
	candidate.merge(changes,true)
	return _save(bindings,candidate) if _settings(candidate) else R.fail("InvalidArgument","input_options")

func load_saved() -> Dictionary:
	if _path.is_empty(): return R.fail("InvalidArgument","input_profile")
	if not FileAccess.file_exists(_path): return R.ok()
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null or file.get_length() > 32768: return R.fail("InvalidArgument","input_profile")
	var decoded := C.decode(file.get_buffer(file.get_length()))
	if not decoded.ok or typeof(decoded.value) != TYPE_DICTIONARY: return R.fail("InvalidArgument","input_profile")
	var data: Dictionary = decoded.value
	var table := _defaults()
	if typeof(data.get("options")) != TYPE_DICTIONARY or not _settings(data.options) or typeof(data.get("bindings")) != TYPE_DICTIONARY or data.bindings.size() != table.size():
		return R.fail("InvalidArgument","input_profile")
	if typeof(data.bindings.get("menu")) != TYPE_DICTIONARY or data.bindings.menu != table.menu: return R.fail("InvalidArgument","reserved_menu")
	# Validate the finished map, allowing a pair of bindings that changed places.
	for action in table:
		if typeof(data.bindings.get(action)) != TYPE_DICTIONARY: return R.fail("InvalidArgument","binding")
		table[action] = {} if action != "menu" else table.menu
	for action in table:
		if action == "menu": continue
		var slots: Dictionary = data.bindings[action]
		if slots.is_empty(): return R.fail("InvalidArgument","binding")
		for slot in slots:
			var token: Variant = slots[slot]
			if typeof(token) != TYPE_STRING or family(token) != slot or not _set_binding(table,action,token).ok:
				return R.fail("InvalidArgument","binding")
	bindings = table
	options = data.options.duplicate()
	return R.ok()
