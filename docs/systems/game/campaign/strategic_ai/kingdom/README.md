# SAI-K — 战略 AI：王国规划

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/strategic_ai/kingdom/` | 总体基线：[§9.1、§9.3、§9.5](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

从王国合法视角提出战争、议和、边境防御、增援和战略目标。不得直接宣战、分配封地或操控所有个体；通过 POL 决议与军团任务渠道。

**协作边界：** SAI 公共规划器、POL/SET/PARTY/ECO/WORLD 只读投影。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

拥有王国层目标和计划游标，王国关系/财政仍属于 POL/INV。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
kingdom_planner / theater_analyzer
war_peace_evaluator / objective_allocator
reinforcement_priority / political_proposal
```

## 4. 数据模型与约束

`KingdomContext{known_fronts,own_power,estimated_enemy_power,treasury,war_weariness,political_votes,supply}`；`KingdomGoal{kind,region,target_settlement?,priority,deadline}`。估计敌军强度带置信度与时间戳。

## 5. 公共接口

```text
generate_kingdom_candidates(ctx) -> Candidate[]
score_front(ctx, target) -> ScoreBreakdown
build_kingdom_plan(goal) -> PlanSteps
propose_decision(goal, actor) -> CommandEnvelope
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

对边境按威胁、交通、粮食与城池价值划分战区；候选包括议和、增援、攻城、保卫、休养。战力和补给不足时过滤高风险候选；宣战/议和必须先提案、投票和授权。分配互斥目标或优先级供军团 planner 消费；战败/和平改变计划，撤销旧敌对目标。

## 7. 配置、异常与安全边界

配置多线战争成本、边境安全、厌战、最低补给储备、锁定周期。不能因落后直接注入兵力或绕过政治。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 王国级低频、按战区聚合；报告候选得分、边境目标与战争持续时间。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SAI-K-01 | SAI-01 / POL-02 | 财政不足、两线战争、决议待投票 | 规划 | 优先可维持目标，不直接宣战 |
| T-SAI-K-02 | SAI-03 | 长期战争损失和和平条件变化 | 更新 | 可提出合法议和与复苏计划 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/strategic_ai/kingdom/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。
