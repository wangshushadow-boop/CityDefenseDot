# BAI-F — L2 编队 AI：执行战术任务

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/ai/formation/` | 总体基线：[§12.1–12.4、§12.8](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

从 FormationTask 或玩家当前订单推导编队行为、局部目标和约束。维护行为 FSM、编队态势与失败反馈；FORM 执行阵型/成员/槽位，MOV 执行路径，个体 AI 执行动作选择。未授权不得替换玩家订单。

**协作边界：** BAI、BAI-T FormationTask、FORM/MOV/COM/RULES 只读端口与订单入口。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

`FormationBrainState`、行为目标、局部重规划/失败冷却；不保存另一份 Formation、槽位或成员。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
controller/formation_brain / task_executor
behaviors/hold / advance / ranged_fire / charge
behaviors/retreat / regroup / follow / siege
 evaluation/formation_evaluator / threat_response
feedback / local_goal_selector
```

## 4. 数据模型与约束

`FormationBrainState{formation_id,behavior,task_id?,order_revision,local_goal,started_tick,retry_after}`；`Behavior=Hold|Move|Fire|Advance|Charge|Retreat|Regroup|Follow|OperateSiege`；`TaskFeedback{status,reason,progress,formation_id,task_id}`。输入包含聚合兵力、成员缺口、槽误差、射线、弹药、路径和士气。

## 5. 公共接口

```text
decide_formation(view,task,order) -> FormationBehaviorIntent
select_local_goal(behavior,nav_view) -> GoalCandidate
build_member_constraints(behavior,order) -> MemberConstraint[]
report_task_status(state,view) -> TaskFeedback
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

按当前授权订单限制候选→紧急溃散/不可达等安全条件→行为评分→保留或切换。弓兵保持射击距离/射线，步兵按推进防守目标接敌，骑兵冲锋后脱离重整，骑射保持移动空间；具体角色由配置而非四套独立执行系统。瓶颈请求 FORM 改可行队形；中心/槽位路径由 MOV。Task 完成条件、超时、伤亡/弹药不足输出反馈给 L1；未委派玩家只执行命令内约束，不改主命令。

## 7. 配置、异常与安全边界

初始 2–5 Hz；配置射击距离范围、接战阈值、重整条件、行为冷却和槽误差；紧急动作由 L3，不在 L2 每 tick 直接控制全员。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 按编队数量低频执行；复用聚合快照；记录行为切换、目标到达时间和命令冲突。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-BAI-F-01 | BAI-01 | 玩家命令保持且 AI 认为冲锋高分 | 决策 | 保留保持约束 |
| T-BAI-F-02 | BAI-02 | 队形遭遇窄门和伤亡 | 更新行为 | 申请可行队形，重组后恢复 |
| T-BAI-F-03 | BAI-04 | 弹药不足或任务超时 | 反馈 | 合法回退且 L1 得到原因 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/ai/formation/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/mission/ai/formation/controller/` | [编队决策控制器](controller/README.md) | 父规格子目录 |
| `game/mission/ai/formation/behaviors/` | [编队行为](behaviors/README.md) | 父规格子目录 |
| `game/mission/ai/formation/evaluation/` | [编队行为评估](evaluation/README.md) | 父规格子目录 |
