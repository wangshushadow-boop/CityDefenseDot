extends HBoxContainer
## 战况与终局战报共用相同列，用开局来源编号定位每行，减员后仍保留原编制。
const S := preload("res://presentation/ui/war_style.gd")
var cells := {}
var totals: Array[Label] = []
var leaders: Array[String] = ["", ""]

func build(roster: Array, final: bool) -> void:
	add_theme_constant_override("separation", 18)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in 2:
		var card := S.panel(self)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body := S.stack(card, 9)
		var heading := S.row(body)
		S.banner(heading, Vector2(32, 42), side == 1)
		var color := S.BLUE if side == 0 else S.RED
		S.label(heading, "我方" if side == 0 else "敌方", 25, color, true)
		var total := S.label(heading, "", 16)
		total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		totals.append(total)
		S.rule(body)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("v_separation", 10)
		grid.add_theme_constant_override("h_separation", 10)
		body.add_child(grid)
		for title in ["部队", "出战", "幸存" if final else "在阵", "阵亡"]:
			var cell := S.label(grid, title, 14, S.GOLD)
			if title == "部队":
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else:
				cell.custom_minimum_size.x = 46
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var standing := 0
		var deployed := 0
		for entry: Dictionary in roster:
			if entry.side != side:
				continue
			var count: int = entry.survivors + entry.losses if final else entry.count
			var alive: int = entry.survivors if final else count
			var name_cell := S.label(grid, entry.title)
			name_cell.clip_text = true
			name_cell.tooltip_text = entry.title
			name_cell.mouse_filter = Control.MOUSE_FILTER_PASS
			var start := S.label(grid, str(count))
			var standing_cell := S.label(grid, str(alive))
			var lost := S.label(grid, str(count - alive))
			for number: Label in [start, standing_cell, lost]:
				number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cells[entry.id] = [standing_cell, lost, count]
			if not final and entry.role == "leader":
				leaders[side] = entry.id
			standing += alive
			deployed += count
		total.text = "%d / %d 人" % [standing, deployed]

func update_count(id: String, alive: int) -> void:
	var line: Array = cells[id]
	line[0].text = str(alive)
	line[1].text = str(int(line[2]) - alive)

func refresh(mission: BattleMission) -> void:
	for team in mission.teams:
		update_count(leaders[team.side], int(team.leader.alive()))
		for group in team.groups:
			update_count(group.id, group.strength())
		totals[team.side].text = "%d / %d 人" % [team.last_strength, team.units.size()]
