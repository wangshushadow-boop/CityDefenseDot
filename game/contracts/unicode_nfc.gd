extends RefCounted

const Data = preload("res://contracts/unicode_data.gd")
const S_BASE := 0xAC00
const L_BASE := 0x1100
const V_BASE := 0x1161
const T_BASE := 0x11A7
const T_COUNT := 28
const V_COUNT := 21
const N_COUNT := V_COUNT * T_COUNT
const S_COUNT := 19 * N_COUNT

static func _composition(a: int, b: int) -> int:
	if a >= L_BASE and a < L_BASE + 19 and b >= V_BASE and b < V_BASE + V_COUNT:
		return S_BASE + ((a - L_BASE) * V_COUNT + b - V_BASE) * T_COUNT
	if a >= S_BASE and a < S_BASE + S_COUNT and (a - S_BASE) % T_COUNT == 0 and b > T_BASE and b < T_BASE + T_COUNT:
		return a + b - T_BASE
	return Data.COMPOSE.get((a << 21) | b, -1)

static func _flush_marks(marks: Dictionary, ordered: Array) -> void:
	var classes := marks.keys()
	classes.sort()
	for klass in classes:
		ordered.append_array(marks[klass])
	marks.clear()

static func is_nfc(value: String) -> bool:
	var ascii := true
	for i in value.length():
		if value.unicode_at(i) >= 128:
			ascii = false
			break
	if ascii:
		return true
	var ordered := []
	var marks := {}
	for i in value.length():
		var cp := value.unicode_at(i)
		if cp >= 0xD800 and cp <= 0xDFFF:
			return false
		var decomposed: Array
		if cp >= S_BASE and cp < S_BASE + S_COUNT:
			var s := cp - S_BASE
			decomposed = [L_BASE + s / N_COUNT, V_BASE + (s % N_COUNT) / T_COUNT]
			if s % T_COUNT != 0:
				decomposed.append(T_BASE + s % T_COUNT)
		else:
			decomposed = Data.DECOMPOSE.get(cp, [cp])
		for part: int in decomposed:
			var klass: int = Data.CLASS.get(part, 0)
			if klass == 0:
				if not marks.is_empty():
					_flush_marks(marks, ordered)
				ordered.append(part)
			else:
				if not marks.has(klass):
					marks[klass] = []
				marks[klass].append(part)
	_flush_marks(marks, ordered)
	var composed := []
	var starter := -1
	var previous_class := 0
	for cp: int in ordered:
		var klass: int = Data.CLASS.get(cp, 0)
		if starter >= 0 and (previous_class == 0 or previous_class < klass):
			var joined := _composition(composed[starter], cp)
			if joined >= 0:
				composed[starter] = joined
				continue
		if klass == 0:
			starter = composed.size()
		composed.append(cp)
		previous_class = klass
	if value.length() != composed.size():
		return false
	for i in composed.size():
		if value.unicode_at(i) != composed[i]:
			return false
	return true
