# game/mission/formation/

[field_formation.gd](ports/field_formation.gd) 为每场 Mission 保存编队、成员、授权和订单。部署时注入认证和导航查询，在 Mission 固定步调用 `advance(tick)`。玩家和受托 AI 共用 `issue_order`。

队形几何和槽位重排入口是 [slot_layout.gd](slot_layout.gd)，用于成员、队形、朝向或可用通道发生变化时重建目标。领域算法采用一次批量地形投影。[模块规格](../../../docs/systems/game/mission/formation/README.md) · [Godot 验收测试](../../tests/p2/formation/run.gd)
