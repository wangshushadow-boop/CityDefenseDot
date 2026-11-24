# BAI-T — L1 战术 AI：全军计划

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/ai/tactical/` | 总体基线：[§12.1、§12.3、§12.8](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

每个 Team 的 AI 指挥官评估战场，选择整体战术、分配编队职责和目标、根据失败/伤亡/增援进行阶段切换。玩家拥有指挥权时不自动覆盖订单。仅输出 FormationTask 与合法 FormationOrder 建议。

**协作边界：** BAI 共同感知；FORM 订单授权端口；RULES 目标查询；MOV 可达区域。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

`TacticalPlan`、各编队任务、候选评分、计划阶段与超时归 L1；编队实际订单归 FORM。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
commander / battlefield_evaluator
strategies/high_ground / infantry_pressure / ranged_cover
strategies/cavalry_flank / mounted_harass / reserve / siege_routes
planning/phase_graph / task_allocator / fallback
 evaluation/utility_score / commitment_policy
```

## 4. 数据模型与约束

`TacticalPlan{id,team,strategy,phase,formation_tasks,created_tick,locked_until,fallback}`；`FormationTask{id,formation_id,role,goal,position?,target_formation?,constraints,priority,completion,timeout}`；`TacticalContext{strength,terrain,known_contact_line,ammo,morale,objective_progress}`。阶段 Assess→Select→Deploy→Engage→Adapt→Finish；可切至 Retreat。

## 5. 公共接口

```text
build_tactical_context(team,view) -> TacticalContext
generate_strategies(ctx) -> TacticalCandidate[]
evaluate_strategy(candidate,ctx) -> ScoreBreakdown
allocate_formation_tasks(plan,formations) -> FormationTask[]
tick_tactic(plan,snapshot) -> FormationOrder[]
on_task_feedback(task_id,status,reason) -> PlanUpdate
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

生成可达且符合规则/兵种构成的候选。拟定效用：目标收益+有效战力+地形/射线优势+协同收益−风险−时间成本−切换代价，各项归一化。高地防守、步兵压迫、弓兵掩护、骑兵侧翼、骑射骚扰、预备队、攻城分路使用可组合阶段。任务分配先保证必要职责再按角色适配度与路程排序，禁止同编队多个互斥任务。任务超时、损失、缺弹或目标失效触发局部回退/改计划，不每帧重选全军战术。

## 7. 配置、异常与安全边界

配置策略权重、指挥官特质、锁期、重评阈值、任务超时、候选上限。0.5–2 Hz 初始；关键事件可提前重评。不得读不可见敌人或绕过玩家授权。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 每 Team 低频计算，复用地形评估；统计策略切换、任务完成率、候选成本。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-BAI-T-01 | BAI-04 | 兵种混合且存在可达高地/平地 | 选择战术 | 评分体现地形、有效射线与兵种适配 |
| T-BAI-T-02 | BAI-04 | 任务不可达或增援改变力量比 | 更新 | 触发回退/重分配或撤退 |
| T-BAI-T-03 | BAI-01 | 玩家未委派自己的编队 | AI 分配任务 | 不覆盖玩家订单 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/ai/tactical/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/mission/ai/tactical/commander/` | [战术指挥官](commander/README.md) | 父规格子目录 |
| `game/mission/ai/tactical/strategies/` | [战术策略库](strategies/README.md) | 父规格子目录 |
| `game/mission/ai/tactical/evaluation/` | [战术评估](evaluation/README.md) | 父规格子目录 |
| `game/mission/ai/tactical/planning/` | [战术任务规划](planning/README.md) | 父规格子目录 |
