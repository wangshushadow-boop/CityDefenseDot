# recollection

古代中国风 3D 沙盒战争游戏 · 规格驱动开发项目

**设计基线 0.3**。功能规模以《骑马与砍杀2：霸主》为参照，所有程序、世界、角色、文本及资产独立原创。完整陆地单人/剧情、自定义战斗、多人和 MOD 均为 MUST；海战为独立 EXT。阶段实施不缩减最终目标。

## 启动与测试

用 Godot 4.7.2 Standard 打开 [game/project.godot](game/project.godot)。Windows PowerShell 可从仓库根目录运行以下命令。第一条启动客户端，第二条以 headless 运行同一组合根的固定步验收，第三条执行各模块的真实 Godot 测试。

```powershell
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $godot --path game
& $godot --headless --path game -- --p1-smoke
python game/tests/p1/harness/suite.py --godot $godot
```

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
| [模块测试规格](docs/testing/test_cases.csv) | 208 条规格及逐项实测状态 |
| [目录索引](PROJECT_TREE.md) | 规划目录与模块归属 |

## 当前交付边界

P1 交付公共运行时、会话、战役和 Mission 基础门面、磁盘事务与工程装配。后续战斗、世界、多人及正式内容的阶段边界见[路线图](development/planning/roadmap.md)。本机实测、历史失败及未运行项见[P1 阶段验收](development/reports/stages/P1.md)。

[变更记录](CHANGELOG.md) · [已知问题](KNOWN_ISSUES.md) · [基线来源](docs/architecture/baselines/README.md) · [交付核查](development/reports/bootstrap_verification.md)
