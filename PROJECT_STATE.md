# recollection 项目状态

**P2 实时战争开发中。** 9/16 个工作包已集成。兵源分波、动作、移动、编队、AI 公共层、输入、相机、视觉和音频已验收。千人固定步的独立三轮 P95 为 13.035–15.062 ms。三层策略正在开发。ADR-014 采用负责人批准的方案 A。三支以上敌对部队中整场主持人是否可随本队撤退终止其余各方，等待 ADR-015 决定。AT-04 与 AT-05 战场切片仍待整场入口验证。[P2 工作批次](development/planning/P2.md) · [阶段报告与测试边界](development/reports/stages/P2.md)

P0、P1 已验收。P2 从 P1 最终提交 `005d777` 分支，本阶段开发与集成记录在 `codex/p2-field`。下面的构建与启动入口属于最近一次已验收的 P1 版本。

| 项目 | 当前状态 |
|---|---|
| 引擎与契约 | Godot 4.7.2 Standard、类型化 GDScript、Forward+/Vulkan，已签核 ADR-011/012/013/014。Mission、联网与 MOD v1 端口已冻结。 |
| 可运行入口 | 用指定 Godot 打开 [game/project.godot](game/project.godot)，或从仓库根运行 `Godot --path game`。专服固定步验收使用 `Godot --headless --path game -- --p1-smoke`。 |
| 交付构建 | 客户端 PCK、专服 PCK、原始资源 ZIP 已独立冷重载。可从 Git 提交重建，产物写入本地 out/p1-build；版本和摘要见[交付清单](development/reports/tests/P1/build-manifest.json)。 |
| 验证 | 15 套 Godot 入口通过。54 个阶段候选模块用例中 36 项完整通过，18 项完整条件尚未执行。四个断点恢复、50 次任务切换及存档冷载均通过。 |
| 签核与预算 | 负责人批准默认 1A、2A，保留总体规格 §1.3 全部原创内容范围。后续以首批正式资产的实测工时和返工率安排预算。 |
| 待验 | 正式战斗/世界/在线玩法、完整 AT-10/AT-15、固定设备的正式性能回退与发布验收按路线图进行。独立 EXE 导出缺少 4.7.2 Windows 模板，退出 1。 |

[阶段验收报告](development/reports/stages/P1.md) · [运行与构建](ci/README.md) · [测试与未测项](development/reports/tests/P1/README.md) · [任务及锁](development/state/tasks.json) · [负责人签核](docs/architecture/decisions/ADR-013-p1-ports-and-save.md)

[P2 工作批次](development/planning/P2.md) · [P2 阶段记录](development/reports/stages/P2.md)
