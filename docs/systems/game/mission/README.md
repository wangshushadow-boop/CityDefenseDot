# 实时任务场景

> 对应计划实现目录：`game/mission/`
> 文档类型：分组索引（非新增独立 SDD）

Mission 各模块的入口；生命周期由 runtime 模块定义。

本目录负责导航，不引入新的运行时或权威数据。

[上级入口](../README.md) · [全部模块索引](../../README.md)

## 下级目录

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/mission/runtime/` | [Mission 运行时、实体与增援](runtime/README.md) | 独立 SDD |
| `game/mission/combat/` | [动作、装备、命中、伤害与士气执行](combat/README.md) | 独立 SDD |
| `game/mission/formation/` | [编队、指挥授权、阵型与槽位执行](formation/README.md) | 独立 SDD |
| `game/mission/ai/` | [战场 AI 共同基础、感知与调度](ai/README.md) | 独立 SDD |
| `game/mission/movement/` | [战场路径、避障、运动与动态导航](movement/README.md) | 独立 SDD |
| `game/mission/siege/` | [实时攻城器械、城防与动态连接](siege/README.md) | 独立 SDD |
| `game/mission/rules/` | [Mission 规则、目标与玩法组合](rules/README.md) | 独立 SDD |
| `game/mission/interaction/` | [场景交互、NPC 与访问流程](interaction/README.md) | 独立 SDD |
| `game/mission/results/` | [来源追踪、战斗结果与统计](results/README.md) | 独立 SDD |
