## 2026-11-24 签核及恢复

负责人选择 1A、2A，ADR-013 已批准，§1.3 全部内容目标按实测产能滚动预算。合入 214b04b 后重新运行两套契约互操作与 QA 入口，全部退出 0。P1 继续执行。

# recollection 项目状态

**首批候选记录。** 2026-11-24；P0 已按实测范围验收，GATE-P1 尚未通过，P2–P8 为 PLANNED。[P1 阶段记录](development/reports/stages/P1.md) · [P0 签核报告](development/reports/stages/P0.md)

| 项目 | 最新状态 |
|---|---|
| 技术栈 | 已批准 Godot Standard 4.7.2、类型化 GDScript、Forward+/Vulkan、ENet 权威专服、规范 UTF-8 JSON/SHA-256。 |
| P0 | RTX 3090 上完成 500/1000 人压测、动态导航、回环联网及原创内容 PCK 验证。签核提交 ab80995，P1 启动基线 f72d1cb。 |
| P1 实现 | 两个契约开发任务已提交到已测联合候选分支 codex/p1-contract-candidate，提交 f37b8f4。等待负责人批准 ADR-013 后集成到 codex/p1-runtime。 |
| 实际测试 | T-CON-01/02/03 在候选上 PASS。其余 205 项模块用例和 17 项完整 AT 保持 NOT_RUN。93 条需求仍未按完整游戏能力验收。 |
| 恢复 | 已保存候选、审查、QA 与失败记录。ADR-013 签核后重跑契约，再按 DAG 开始 CORE 与 DEF。§23.2 的原创内容规模与预算口径可并行确认。 |

[待决 ADR](docs/architecture/decisions/ADR-013-p1-ports-and-save.md) · [机器状态](development/state/project.json) · [任务记录](development/state/tasks.json) · [集成与复跑命令](development/reports/integration/P1.md)
