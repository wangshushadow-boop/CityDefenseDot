# recollection

古代中国风 3D 沙盒战争游戏 · 规格驱动开发项目

**交付版本：0.3 / 研发初始化基线**。功能规模以《骑马与砍杀2：霸主》为参照，所有程序、世界、角色、文本及资产独立原创。完整陆地单人/剧情、自定义战斗、多人和 MOD 均为 MUST；海战为独立 EXT。阶段实施不缩减最终目标。

## 快速开始（你只需要一个 Codex 项目窗口）

1. 将 `recollection/` 解压至开发目录，从该目录打开 Codex。若需要 Git，先在此目录初始化仓库并提交初始基线（下面是新目录的示例）。已有 Git 仓库不要重复初始化或覆盖历史。
2. 运行 `python3 development/check_project.py` 检查文档、目录、任务依赖及初始状态。管理工具使用 Python 3.11+ 标准库，不代表游戏开发语言已选择。
3. 把 [首次启动提示词](development/prompts/initialize.md) 复制给 Codex，明确只执行 P0（技术验证与架构冻结）。主 Agent 使用原生 Subagents 组织工作；若客户端不提供该能力，则按同样职责顺序执行并说明限制。
4. 每个阶段完成后查看验收报告并决定下一阶段。以后直接发送“按照 AGENTS.md 和 PROJECT_STATE.md，开始 P1，组织多 Agent 实现并验收，完成后停止”。阶段指令见 [prompts](development/prompts/README.md)。

```bash
# 在已解压的 recollection/ 中执行；若已经是 Git 仓库请跳过初始化。
git init -b main
git add .
git commit -m "chore: initialize recollection design and development baseline"
python3 development/check_project.py
python3 development/check_project.py --ready P0
```

若 Git 未配置用户名/邮箱，自行设置后再提交。Codex 项目配置需要受信任的项目，遵守本地沙盒与审批规则；不会自动授予更高权限。详见 [Codex 使用指南](development/codex_setup.md)。

## 设计与研发入口

| 文件 | 用途 |
|---|---|
| [AGENTS.md](AGENTS.md) | 全局约束、主 Agent 协作入口 |
| [PROJECT_STATE.md](PROJECT_STATE.md) | 当前可读状态，机器记录为 development/state/*.json |
| [总体设计](docs/game_design.md) | 产品范围、总体架构、P0–P8 |
| [系统索引](docs/systems/README.md) | 57 份独立 SDD、96 个目录入口 |
| [公共契约](docs/architecture/common_contracts.md) | 公共类型、权威写入及接口提案 |
| [依赖规则](docs/architecture/dependency_policy.md) | 静态依赖及跨域协作 |
| [阶段计划](development/planning/roadmap.md) | 目标、批次、验收及跨阶段测试 |
| [任务图](development/planning/task_graph.json) | 工作包与阶段门禁（执行前细化） |
| [研发工作流](development/workflow.md) | 分配、审查、修复、集成、暂停与恢复 |
| [验收矩阵](docs/testing/acceptance_matrix.md) | 17 个跨系统场景 |
| [需求追踪](docs/testing/requirements_trace.csv) | 93 个需求及状态 |
| [模块测试规格](docs/testing/test_cases.csv) | 208 条规格，初始 NOT_RUN |
| [目录索引](PROJECT_TREE.md) | 完整目录与代码骨架 |

## 当前交付边界

这是完整设计、研发执行文档、Codex 项目配置和代码目录骨架；**不是已可启动的游戏**。引擎、语言、版本、公共接口编码、测试框架、性能基线仍需 P0 实验及批准。不存在假造的 `project.godot`、模拟游戏通过报告或临时正式实现。P0/P1 决策后才创建对应引擎工程。所有实际游戏测试初始 NOT_RUN；已有检查仅验证文档、配置和研发计划结构。

[变更记录](CHANGELOG.md) · [已知问题](KNOWN_ISSUES.md) · [基线来源](docs/architecture/baselines/README.md) · [交付核查](development/reports/bootstrap_verification.md)
