# recollection 项目状态

**P2 已验收 15/16 个工作包。** 正式河原两档实战均低于性能预算。首轮千槽结算在一次坐骑失能后卡在第 1304 步；源码和专服成品均已复现，正在验证修正。P3 人物已获条件授权，前置为 GATE-P2。[本期阶段报告](development/reports/stages/P2.md)

此前模块性能检查点为 `847890e`。Windows 冷开发交付有客户端、专服和内容 ZIP。四份野战模型、署名以及 48 条中英命令和警告均已验证；两个 PCK 分别捕获到每句真实声音。最终客户端在六个干净用户目录启动成功。P2 的 19 个模块测试入口及两项跨域/音频补充入口、P1 的 15 套回归均通过。20% 骑乘的 L3 夹具在 500 人时三轮固定步 P95 为 9.786–10.802 ms，1000 人为 21.559–22.890 ms，超出 16.667 ms。8 GiB 设备与人工听辨尚未实测。[构建清单](development/reports/tests/P2/build-checkpoint/final-manifest.json) · [P2 回归](development/reports/tests/P2/integrated-regressions.json) · [20% 骑乘原数](development/reports/tests/P2/l3-mixed-20pct-integrated.json)

P0、P1 已验收。P2 从 P1 最终提交 `005d777` 分支，本阶段开发与集成记录在 `codex/p2-field`。下面的构建与启动入口属于最近一次已验收的 P1 版本。

| 项目 | 当前状态 |
|---|---|
| 引擎与契约 | Godot 4.7.2 Standard、类型化 GDScript、Forward+/Vulkan，已签核 ADR-011/012/013/014/015。Mission、联网与 MOD v1 端口已冻结。 |
| 可运行入口 | 用指定 Godot 打开 [game/project.godot](game/project.godot)，或从仓库根运行 `Godot --path game`。专服固定步验收使用 `Godot --headless --path game -- --p1-smoke`。 |
| 交付构建 | 客户端 PCK、专服 PCK、原始资源 ZIP 已独立冷重载。可从 Git 提交重建，产物写入本地 out/p1-build；版本和摘要见[交付清单](development/reports/tests/P1/build-manifest.json)。 |
| 验证 | 15 套 Godot 入口通过。54 个阶段候选模块用例中 36 项完整通过，18 项完整条件尚未执行。四个断点恢复、50 次任务切换及存档冷载均通过。 |
| 签核与预算 | 负责人批准默认 1A、2A，保留总体规格 §1.3 全部原创内容范围。后续以首批正式资产的实测工时和返工率安排预算。 |
| 待验 | 正式战斗/世界/在线玩法、完整 AT-10/AT-15、固定设备的正式性能回退与发布验收按路线图进行。独立 EXE 导出缺少 4.7.2 Windows 模板，退出 1。 |

[阶段验收报告](development/reports/stages/P1.md) · [运行与构建](ci/README.md) · [测试与未测项](development/reports/tests/P1/README.md) · [任务及锁](development/state/tasks.json) · [负责人签核](docs/architecture/decisions/ADR-013-p1-ports-and-save.md)

[P2 工作批次](development/planning/P2.md) · [P2 阶段记录](development/reports/stages/P2.md)
