# 基础设施

> 对应计划实现目录：`game/infrastructure/`
> 文档类型：分组索引（非新增独立 SDD）

存档、数据加载、引擎、网络与遥测适配。

本目录负责导航，不引入新的运行时或权威数据。

[上级入口](../README.md) · [全部模块索引](../../README.md)

## 下级目录

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/infrastructure/persistence/` | [存档、原子提交、迁移与恢复](persistence/README.md) | 独立 SDD |
| `game/infrastructure/content/` | [数据包编译、MOD 注册与配置合并](content/README.md) | 独立 SDD |
| `game/infrastructure/engine/` | [引擎适配、物理、导航与资源端口](engine/README.md) | 独立 SDD |
| `game/infrastructure/network/` | [网络协议、传输、权威与状态复制](network/README.md) | 独立 SDD |
| `game/infrastructure/telemetry/` | [日志、指标、诊断与崩溃报告](telemetry/README.md) | 独立 SDD |
