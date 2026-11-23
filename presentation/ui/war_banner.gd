extends Control
## 按控件尺寸绘制城楼军旗，两军旗色与战场模型一致。
var cloth := Color("#285457")
const THREAD := Color("#dcc28b")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var h := minf(size.y, size.x * 1.34)
	if h <= 0:
		return
	draw_set_transform(Vector2((size.x - h * 0.72) / 2, (size.y - h) / 2), 0, Vector2.ONE * h)
	var points := PackedVector2Array([Vector2(0.04, 0.04), Vector2(0.68, 0.04), Vector2(0.68, 0.77), Vector2(0.36, 0.97), Vector2(0.04, 0.77)])
	draw_colored_polygon(points, cloth)
	points.append(points[0])
	draw_polyline(points, THREAD, 0.022, true)
	draw_line(Vector2(0, 0.055), Vector2(0.72, 0.055), THREAD, 0.05, true)
	draw_polyline(PackedVector2Array([Vector2(0.16, 0.43), Vector2(0.36, 0.28), Vector2(0.56, 0.43)]), THREAD, 0.044, true)
	draw_rect(Rect2(0.19, 0.44, 0.34, 0.055), THREAD)
	draw_rect(Rect2(0.23, 0.49, 0.065, 0.17), THREAD)
	draw_rect(Rect2(0.425, 0.49, 0.065, 0.17), THREAD)
	draw_line(Vector2(0.16, 0.68), Vector2(0.56, 0.68), THREAD, 0.032, true)
