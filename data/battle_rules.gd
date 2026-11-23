class_name BattleRules extends Resource
## 配置只读，一局中变化的库存、士气和门耐久分别存入对应模块。
@export var commander: TroopSpec
@export var infantry: TroopSpec
@export var archer: TroopSpec
@export var capture_seconds := 5.0
@export var supply_period := 12.0
@export var initial_food := 22
@export var ram_cost := 6
@export var repair_cost := 2
@export var surrender_morale := 24.0
@export var surrender_strength := 6
