# 游戏工程

> 对应计划实现目录：`game/`
> 文档类型：分组索引（非新增独立 SDD）

游戏运行代码、数据、引擎适配及测试的入口。

本目录负责导航，不引入新的运行时或权威数据。

[上级入口](../README.md) · [全部模块索引](../README.md)

## 下级目录

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/bootstrap/` | [启动、装配与配置](bootstrap/README.md) | 独立 SDD |
| `game/core/` | [核心运行时原语与调度](core/README.md) | 独立 SDD |
| `game/contracts/` | [公共契约与版本管理](contracts/README.md) | 独立 SDD |
| `game/application/` | [应用层、GameSession 与事务](application/README.md) | 独立 SDD |
| `game/campaign/` | [战略世界运行时](campaign/README.md) | 独立 SDD |
| `game/mission/` | [实时任务场景](mission/README.md) | 分组索引 |
| `game/shared/` | [公共领域系统](shared/README.md) | 分组索引 |
| `game/presentation/` | [表现层](presentation/README.md) | 分组索引 |
| `game/infrastructure/` | [基础设施](infrastructure/README.md) | 分组索引 |
| `game/multiplayer/` | [多人会话、大厅、匹配与模式组装](multiplayer/README.md) | 独立 SDD |
| `game/addons/` | [编辑器插件与可信扩展 SDK](addons/README.md) | 独立 SDD |
| `game/content/` | [游戏内容](content/README.md) | 分组索引 |
| `game/tests/` | [领域、集成、场景与长期测试](tests/README.md) | 独立 SDD |
