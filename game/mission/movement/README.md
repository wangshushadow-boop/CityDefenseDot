# game/mission/movement/

项目：`recollection`。模块：`MOV`。

[野战移动门面](ports/field_movement.gd) 按 Mission 持有步骑位姿与速度，为已分配槽位的单位推进共享走廊。组合方提供生效的实体句柄、已投影的出生点与终点槽位，以及场景通道的米制边界和通行类型。

共享走廊的请求、固定步查询预算和缓存由 [path_queue.gd](path_queue.gd) 管理。导航版本来自注入的引擎适配器。设计与验收见[模块规格](../../../docs/systems/game/mission/movement/README.md)和[真实场景测试](../../tests/p2/movement/run.gd)。
