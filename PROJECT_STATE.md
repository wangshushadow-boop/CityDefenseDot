# recollection 项目状态

**P1 公共运行时与工程基础正在执行。** 2026-11-24，项目负责人批准 ADR-011、ADR-012 和按已测范围验收 P0。P1 已获本次会话授权，P2–P8 为 PLANNED。[阶段报告](development/reports/stages/P0.md)

| 项目 | 最新状态 |
|---|---|
| 技术栈 | Godot Standard 4.7.2.stable.official.ed1daf0bf、类型化 GDScript、Forward+/Vulkan；ENet 权威专服 30 Hz，快照 15 Hz。Python 3.12.14 标准库与 Godot headless/桌面实验用于验证。 |
| 关键契约 | 带类型的持久 UUID、作用域句柄、坐标与精度、命令/快照所有权、规范 UTF-8 JSON/SHA-256 和版本迁移策略已批准。 |
| 实测 | RTX 3090 上完成 500/1000 活跃人形桌面压测、256 人动态导航、1/4 进程故障与 64/128 个回环连接实验，以及原创内容 PCK 和跨引擎编解码测试。 |
| 游戏实现 | GDD 与 57 份 SDD 的正式模块实现仍待后续阶段。P0 实验位于 test_scenarios/p0。93 条需求 NOT_IMPLEMENTED，208 项模块测试、17 项 AT 为 NOT_RUN。 |
| 本地归档 | 分支 codex/p0-validation；初始基线 eea39fa，实验集成 47d3a40，负责人签核 ab80995。10 个 P0 执行任务、8 个工作包与阶段门禁均为 DONE。实验锁已释放。 |

[机器状态](development/state/project.json) · [任务与变更记录](development/state/tasks.json) · [独立 QA](development/reports/tests/P0/README.md) · [集成记录](development/reports/integration/P0.md)
