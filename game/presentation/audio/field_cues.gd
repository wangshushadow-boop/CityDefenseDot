extends RefCounted

const TEXT = preload("res://presentation/audio/captions.tres")
# Category, priority, audible range (metres), timbre.
const CUES := {
	"command":["Voice",100,0,0], "warning":["Voice",90,0,0],
	"hit":["Effects",24,40,150], "shield_broken":["Effects",56,55,320],
	"projectile_launched":["Effects",30,52,650], "projectile_obstructed":["Effects",20,32,190],
	"mount_impact":["Effects",51,60,83], "hoofbeat":["Effects",25,35,100], "dismounted":["Effects",43,40,120],
	"downed":["Effects",48,45,102], "routed":["Effects",64,60,440], "regrouped":["Effects",65,60,510],
	"ambience":["Ambience",8,80,90], "ui":["UI",70,0,700],
	"victory":["Music",110,0,740], "defeat":["Music",110,0,220]
}
const MELODIES := {
	"map":[262,330,392,330,294,262,196,0], "battle":[196,196,294,262,196,294,330,262],
	"victory":[262,330,392,523,440,392,330,523], "defeat":[330,294,262,220,196,165,131,0]
}
const RATE := 16000
var _cache := {}

func caption(key: String) -> String:
	var translated := TranslationServer.translate(key)
	if translated != key:
		return translated
	var locale := TranslationServer.get_locale()
	var entries: Dictionary = TEXT.get_meta("zh" if locale.begins_with("zh") else "en")
	return entries.get(key,key)

func spoken(order: String) -> String:
	return order if TEXT.get_meta("en").has("audio.order."+order) else "command"

func clip(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var music := MELODIES.has(id)
	var command: bool = id == "warning" or TEXT.get_meta("en").has("audio.order."+id)
	var length := 3.2 if music else (0.35 if command else (0.65 if id == "ambience" else 0.16))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_8_BITS
	sound.mix_rate = RATE
	var bytes := PackedByteArray()
	bytes.resize(roundi(length*RATE))
	var notes: Array = MELODIES.get(id,[])
	for i in bytes.size():
		var t := float(i) / RATE
		var wave: float
		if music:
			var beat := mini(floori(t/0.4),notes.size()-1)
			var local := t-beat*0.4
			var phase: float = TAU*notes[beat]*local
			wave = (sin(phase)+0.28*sin(2*phase)) * exp(-8*local) * minf(local*120,1)
			if id == "battle":
				wave += 0.45*sin(TAU*(72-45*local)*local)*exp(-20*local)
		elif command:
			var beat := floori(t/0.175)
			var local := fmod(t,0.175)
			var first := 330 if id in ["retreat","warning","hold_fire"] else 440
			var second := first + (110 if id in ["advance","charge","move"] else -55)
			var phase := TAU*(first if beat==0 else second)*local
			wave = (sin(phase) + 0.20*sin(phase*2)) * exp(-10*local) * minf(local*160,1)
		else:
			var phase: float = TAU*CUES[id][3]*t
			wave = (sin(phase)+0.5*sin(phase*1.75)+0.25*sin(phase*3.04)) * exp(-5*t/length) * minf(t*500,1)
		bytes[i] = clampi(roundi(wave*62),-127,127) & 255
	sound.data = bytes
	if music and id in ["battle","map"]:
		sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sound.loop_end = bytes.size()
	_cache[id] = sound
	return sound
