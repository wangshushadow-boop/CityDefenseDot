# recollection 项目状态

P1 正在实施。负责人已选择 1A 与 2A，修订版 ADR-013 已批准，§1.3 全部内容目标按实测产能滚动安排预算。P0 已完成，P2–P8 保持 PLANNED。

| 项目 | 当前状态 |
|---|---|
| 引擎 | Godot Standard 4.7.2、类型化 GDScript、Forward+/Vulkan、权威 ENet。 |
| 公共契约 | 生产实现已合入 214b04b，规范 JSON/SHA-256、版本、迁移与三类端口通过独立审查、QA 及合并态复测。 |
| 开发 | 15 个 P1 工作包中已有 10 个合入并验证。当前在隔离工作树开发战役和 Mission 门面，应用层、装配和 CI 留在本阶段后续批次。 |
| 内容预算 | 首批正式资产验收后记录单件实测工时与返工率，用于后续批次排期。 |

[阶段记录](development/reports/stages/P1.md) · [任务状态](development/state/tasks.json) · [签核 ADR](docs/architecture/decisions/ADR-013-p1-ports-and-save.md)
