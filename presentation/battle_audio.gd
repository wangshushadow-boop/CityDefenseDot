class_name BattleAudio extends AudioStreamPlayer
## 用简短的合成提示音确认军令，无需外部音频资源，可直接替换为正式音效。
func _ready() -> void:
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_8_BITS
	sample.mix_rate = 16000
	var data := PackedByteArray()
	data.resize(1200)
	for i in data.size():
		var fade := 1.0 - float(i) / data.size()
		data[i] = int(sin(TAU * 520 * i / sample.mix_rate) * 50 * fade) & 255
	sample.data = data
	stream = sample
	volume_db = -12
