# P2-FIELD-INTEGRATION-013 · 三层野战 AI 装配

开发者 ai_tx_dev，独立工作树 `.worktrees/p2-field-brains`，基线 `5b60654`。候选状态 CANDIDATE。需求 BAT-01、MIS-02，测试为 T-MIS-RT-01、T-MIS-RT-02、T-TEST-01 的战场调度切片。

新增 `game/mission/runtime/field_brains.gd`、`game/tests/p2/field_brains/run.gd` 和本报告。生产脚本使用既有 BAI、L1、L2、L3 局部门面，FORM 通过原令牌签发下一步 v1 命令。人形的队伍、代际、成员与控制修订按真实 FORM 复验，通行和视线按当前场景查询。玩家手控人形跳过个体 AI，其他士兵继续按本队 L2 约束行动。战斗动作与移动各按原顺序匹配实际回执，朝向意图交由现有动作输入链。HUD 仅读取已提交的可见敌编队编号。

使用 Godot 4.7.2 Standard Windows console。真实入口为 `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/p2/<目录>/run.gd`。客户端、专服和最终 AT 的启动记录由组合层任务提供。

| 入口 | 退出码 | 实测 |
|---|---:|---|
| field_brains | 0 | 真实 Jolt 战场、121 个提交步、9 名人形、4 匹坐骑。1318 项断言，失败 0。5 次 L1 战术、55 次 L2 编队、80 次 L3 个体决策，4 个实际编队命令、51 个 COM 输入、22 个 MOV 驱动、16 次命中。 |
| ai_transaction | 0 | 29 项通过。 |
| tactical | 0 | FIELD_TACTICS errors=0，真实导航查询 1576、物理视线查询 4593。 |
| formation_ai | 0 | P2-BAI-F-001 通过，4877 项断言。 |
| individual，追加 `-- --functional-only` | 0 | 910 项检查通过。另有 1000 名人形、500 匹马的 L3 夹具，整体 P95 为 33.105 ms。此入口只验功能。 |

现场记录的 L3 模式包括步兵 11 次近战、弓手 13 次瞄准、骑兵 7 次马上打击和骑射兵 18 次马上射击。测试执行已发动作和移动，回滚所有参与域，再以同一 tick 匹配重试的命令、令牌和结果。窗口间撤销编队授权时，原回执被拒绝。测试也覆盖未提交目标不可见、旧代际成员、回执缺失及单兵手控。

首轮测试在导航服务器刚报告已应用时提前启动，路径均不可达，8 个实战断言失败。夹具改为等待场景中的实际非零长度路径与探墙查询成功后开战，随后回归通过。已向组合层开发者同步这一条件。完整 Mission 七阶段、500/1000 人整场、真实窗口与 8 GiB 目标设备在本任务中均为 NOT_RUN。候选由主 Agent 执行差异门禁、独立 QA 和集成。
