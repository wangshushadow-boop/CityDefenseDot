# P2-BAI-I-002 玩家及 L3 共用 MoveIntent

开发候选，基线 `c9a3b199dd55ecd35dc5861ce73a6ee1bb0531ac`，工作树 `.worktrees/p2-move_intents`。覆盖 BAI-03、BAI-06、NAV-01、T-MOV-02、T-MOV-04。独立审查及集成验收由主 Agent 执行。

## 正常入口和所有权

组合根用 `FieldMovement.new(engine, mission_id, move_authority)` 注入可信读取口。其签名为 `(scope_id, actor_handle, context, tick) -> bool`，负责判定当前世代、控制权及存活状态。玩家和 L3 都在 `begin_step(tick)` 后向同一 MOV 候选调用 `apply_move_intent(stage_token, intent_v1, context)`，再由原有 `stage_step`、`commit_step`、`rollback_step` 处理。读口缺失、上下文未授权、句柄已退役或事务令牌失效都会拒绝。对已接纳命令，每次积分前在当前 tick 复验。撤权使角色停步，需要新的合法命令才恢复。阶段候选位姿可通过原 `read_poses/read_positions` 批读，撤销后已发布位姿和原有令牌语义得以保留。[MOV 入口](../../../game/mission/movement/ports/field_movement.gd)

本地域直接验收 v1 的四个字段，沿用其整数方向表示与百万分速度量化。地面输入取水平面，步行、冲刺、蹲伏使用原有步骑速度上限的 75%、100%、45%，空姿态采用原上限。脚步的零输入直接停止。骑兵沿已验证路线制动，换向时先减速再转向。步行和骑乘复用原有积分器、空间近邻和地形规则。

每名受控角色保有一段最长 18 m 的导航请求前视距离，按真实导航返回的折线前进。方向变化、走完可延续路线或导航版本变化触发重求；未获准加入地图的起点、断桥及受限窄门均不可越过。个体路线、共享走廊和成员入队共用每 tick 八次原生路径查询预算，同 tick 回滚重试复用已付费的答案。场景碰撞每个移动步实时检查；密集区域先使用包住该格全部合法单步的球体排除空格，再逐个精查可能碰撞的角色。已停止的角色保留原位置。[短路径](../../../game/mission/movement/intent_route.gd) · [查询队列](../../../game/mission/movement/path_queue.gd)

## 复跑

在本工作树根设置 `$godot='D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'`，然后运行以下命令。实际导航与碰撞由 EngineAdapter、NavigationServer3D 和 Jolt 提供。本轮使用无窗口进程。

```powershell
& $godot --headless --path game --check-only --script res://mission/movement/ports/field_movement.gd
& $godot --headless --path game --script res://tests/p2/move_intents/run.gd
& $godot --headless --path game --script res://tests/p2/movement/run.gd
& $godot --headless --path game --script res://tests/p2/ai/run.gd
```

## 实测

专属套三轮各 4464 项检查，均退出 0。真实 Jolt 墙将步兵中心挡在 x = −0.504494 m；移动墙体、保持同一导航版本后，角色可继续移动，前方新落下的墙再次挡住角色。断桥后位置停在 x = 0 m，重新开放后行至 x = 14.989967 m。骑兵受到仅限步兵的窄门约束，停在 x = −2.000367 m。半速骑行实测 4.500046 m/s，制动一帧后 4.366722 m/s。回滚、同 tick 路径预算、权限在物理读取中变更、句柄换代、同输入玩家与 L3 的位置与错误等价均通过。[专属测试](../../../game/tests/p2/move_intents/run.gd)

下表保留专属套三轮原数。每轮两档的实际移动人数分别为 500/500、1000/1000，导航请求总数分别为 500、1000，每 tick 峰值均为 8。步骑混合，20% 为骑兵。提交一批全部角色输入的耗时与随后 MOV 步进 P95 分列，单位为微秒。

| 轮次 | 500 全量接纳 | 500 MOV P95 | 1000 全量接纳 | 1000 MOV P95 | 退出码 |
|---|---:|---:|---:|---:|---:|
| 1 | 3844 | 4599 | 7686 | 11357 | 0 |
| 2 | 4228 | 4673 | 7807 | 9421 | 0 |
| 3 | 3746 | 4599 | 7504 | 10121 | 0 |

原 MOV 套退出 0。48/48 步兵通过窄门，861 tick 到齐，越界 0。骑兵受限位置 −2.001273 m。500/1000 档均全部成功加入，实测每 tick 至多 8 次寻路，原 500/1000 活动运动场景 P95 分别为 2973/3854 µs。解析检查退出 0。

原 BAI/COM/MOV 组合负载为每档 120 tick，固定门槛 16667 µs。最终版本 1000 档首轮超出门槛；后两轮由主 Agent 暂缓新 CPU 压测并串行复验，两轮均达标。运行未测得首轮波动的唯一原因。三轮功能工作量一致，两档的个体调度分别为 5120/10120，物理视线查询分别为 10504/20501，积压峰值皆为 0。

| 轮次 | 500 综合 P95 µs | 1000 综合 P95 µs | 1000 结果 | 进程退出码 |
|---|---:|---:|---|---:|
| 1 | 7108 | 18870 | FAIL | 1 |
| 2 | 6782 | 12959 | PASS | 0 |
| 3 | 7187 | 13962 | PASS | 0 |

首轮开发期测试错误地将首次空导航图的 `applied` 判作资源可用，已改为等待已知短路径可达；另修正了从岸边返回稍后方桥头后才能通行的情况。中间版本逐人执行全量球扫时，1000 档 MOV P95 曾为 17564 µs；保守格子粗筛后复测见上表。本任务未运行最终 BOOT 整场战斗与渲染性能，未进行人手操作设备体验。

最终源码 Git blob 分别为 `field_movement.gd:e6af949573e532ed5cb24be3ab7547635817af84`、`intent_route.gd:f8313aaa8af2075365598460031be08afcf4af5f`、`path_queue.gd:dfee516e1de8513464f1133c2b34d32deb97d699`。
