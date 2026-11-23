extends Control
## 军用沙盘与战场共享坐标。点选地面、据点或移动中的攻城槌后交给原军令入口。
signal destination(at: Vector2)
const S := preload("res://presentation/ui/war_style.gd")
var mission: BattleMission
var aim := BattleSpace.GRAIN

func map_point(at: Vector2) -> Vector2:
	return (at / BattleSpace.LIMIT + Vector2.ONE) * size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var at: Vector2 = (event.position / size * 2 - Vector2.ONE) * BattleSpace.LIMIT
		# 槌可能正在出城，优先吸附槌的位置，护送命令才会命中当前器械。
		var fort := mission.field.forts[0]
		if fort.ram_hp > 0 and map_point(fort.ram_at).distance_to(event.position) < 8:
			at = fort.ram_at
		else:
			for point in mission.supply.points:
				if map_point(point.at).distance_to(event.position) < 8:
					at = point.at
					break
		destination.emit(at)
		accept_event()

func _draw() -> void:
	if not mission:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#363b31"))
	var river := PackedVector2Array()
	var edge := int(BattleSpace.LIMIT.x)
	for x in range(-edge, edge + 1, 2):
		river.append(map_point(Vector2(x, FieldTerrain.river_z(x))))
	draw_polyline(river, Color("#536d69"), size.y * 0.07, true)
	for x: float in [-FieldTerrain.FORD_X, FieldTerrain.FORD_X]:
		var crossing := map_point(Vector2(x, FieldTerrain.river_z(x)))
		draw_line(crossing - Vector2(0, 6), crossing + Vector2(0, 6), Color("#b49e76"), 4)
	draw_line(map_point(mission.field.forts[0].yard()), map_point(mission.field.forts[1].yard()), Color("#877655"), 2)
	for rock: Vector3 in FieldTerrain.ROCKS:
		draw_circle(map_point(Vector2(rock.x, rock.y)), 2.8, Color("#626050"))
	for fort in mission.field.forts:
		var wall := map_point(fort.gate)
		draw_line(Vector2(wall.x, 2), Vector2(wall.x, size.y - 2), Color("#9b8c6b"), 2)
		for door: float in [0.0, BattleSpace.SIDE_Z]:
			var opened := fort.front_open() if door == 0 else fort.side_open
			if opened:
				var gap := map_point(fort.gate + Vector2(0, door))
				draw_line(gap - Vector2(0, 4), gap + Vector2(0, 4), Color("#363b31"), 3)
	for i in mission.supply.points.size():
		var point := mission.supply.points[i]
		var point_color: Color = [S.GOLD, S.BLUE, S.RED][point.owner + 1]
		var p := map_point(point.at)
		draw_arc(p, 4, 0, TAU, 12, point_color, 2, true)
		var title := point.title if i < 2 else ("西城" if i == 2 else "东城")
		draw_string(get_theme_default_font(), p + Vector2(-18, 16), title, HORIZONTAL_ALIGNMENT_CENTER, 36, 12, S.IVORY)
	for team in mission.teams:
		var color := S.BLUE if team.side == 0 else S.RED
		for unit in team.units:
			if unit.alive():
				draw_circle(map_point(unit.position), 1.5, color)
		var fort := mission.field.forts[team.side]
		if fort.ram_hp > 0:
			var p := map_point(fort.ram_at)
			draw_rect(Rect2(p - Vector2(4, 2), Vector2(8, 4)), color)
			draw_string(get_theme_default_font(), p + Vector2(-7, -4), "槌", HORIZONTAL_ALIGNMENT_LEFT, 15, 12, color)
	var marker := map_point(aim)
	draw_arc(marker, 7, 0, TAU, 20, S.GOLD, 1.6, true)
	draw_line(marker + Vector2(0, -11), marker + Vector2(0, -5), S.GOLD, 1.6)
