# game/mission/combat/

项目：`recollection`。模块：`COM`。

[近战固定步执行](melee.gd)处理四向动作、格挡和权威碰撞候选。[模块验收入口](../../tests/p2/combat/run.gd)覆盖真实碰撞体与确定性重放。[模块规格](../../../docs/systems/game/mission/combat/README.md)

野战装配使用 [field_combat.gd](ports/field_combat.gd) 的 `enlist`、`mount`、`step_field` 和 `view` 执行角色动作、弹体碰撞、骑乘及士气。实际用法见[野战物理用例](../../tests/p2/combat/field_cases.gd)。
