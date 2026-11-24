# P2-FORM-001 编队槽位开发记录

状态为 CANDIDATE。开发者为 p2formation，隔离工作树为 .worktrees/p2-formation，基线为 `005d777101654e67263e04fc6f2965403222e0b4`。本记录针对 BAI-02 的 T-FORM-02 领域切片。BAI-01、BAI-05、NET-04 由后续订单与授权任务覆盖。

[编队源码](../../../game/mission/formation/slot_layout.gd)按横队、盾墙、散阵、方阵、圆阵、楔形、纵队生成局部槽位。每个在场成员使用完整 AgentHandle；成员顺序变化后结果一致。小幅减员保留原槽及物理位置，损失超过四分之一时压紧占用区域。通道宽度由调用方提供；不足以容纳原队形时减少列数，退出后按原队形恢复。一个编队持有一个实例，成员、地形、队形或目标发生变化时重建。坐标以米计，朝向绕 Y 轴旋转。所有投影成功、目标唯一后发布整批只读槽位。控制权、组织成员的上层决策以及位置积分各自仍归原模块。公共协议没有变化。

## 可复现验证

在本工作树中，用 Godot 4.7.2 Standard 控制台运行以下命令。实际测试将 APPDATA、LOCALAPPDATA 和日志定向到独立临时目录。

```powershell
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/p2/formation/run.gd --quit-after 420
& $godot --headless --path game --script res://tests/p1/engine/run.gd --quit-after 420
python -B ci/gates.py dependencies
```

| 项目 | 实测结果 |
|---|---|
| 七种编队与伤亡，种子 241124 | 500 和 1000 个成员各跑七种队形。通过生产 P1 引擎适配器查询真实 Godot 导航面与一米宽通道，逐一核对目标可达、成员与槽位唯一。随机重排成员、移除后补入、通过窄道再展开，均与预期一致。合计 52,506 个可达目标。 |
| 异常与隔离 | 越出真实导航网格、被投影到同一点、畸形投影、通道窄于一个成员、同索引不同代、无效 generation、投影中重入均未覆盖已发布快照。测试另验证输入拷贝、只读子级、转向、减员压紧及清空。 |
| P2 退出码 | 0。最后一次 500 人整轮 246,049 µs，1000 人整轮 564,321 µs，`T-FORM-02-LAYOUT PASS`，`P2-FORM-001 PASS failures=0 reachable_slots=52506 seed=241124`。整轮计时含所有重排、真导航批次及断言。 |
| 适配器回归 / 依赖 | P1 引擎入口 `ENGINE failures=0`，退出 0。生产依赖 `dependencies PASS issues=0`，退出 0。 |

首轮退出 1。场景刚加载时引擎已有导航版本，但路径尚未可达，测试现等待一条已知路径可用。第二轮的细长导航多边形使实际投影终点偏移超过适配器固有容差，测试场景按 8 米细分了通道，保留原一米宽度及适配器判据。最终复跑通过。[测试入口](../../../game/tests/p2/formation/run.gd) · [场景](../../../game/tests/p2/formation/floor.tscn) · [导航网格](../../../game/tests/p2/formation/floor.gd)

## 交接

改动限于 game/mission/formation 的实现与导航 README、game/tests/p2/formation 的三个测试文件，以及本报告。开发者未提交 Git。完整玩家指挥入口、委派、实际运动跟随、AT-04 与 500/1000 真实混合野战的帧时在此任务中均未运行。独立审查、QA 和合入后复测由主 Agent 记录。
