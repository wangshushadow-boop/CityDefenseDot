class_name TroopSpec extends Resource
## 兵种与装备的共享定义。实际生命值、格挡和冷却由每个角色保存。
@export var title: String
@export var weapon: String
@export var health := 100.0
@export var damage := 15.0
@export var reach := 1.3
@export var speed := 3.0
@export var interval := 1.0
@export var ranged := false
