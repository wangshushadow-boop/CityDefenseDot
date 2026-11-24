# SAI-A — 战略 AI：军团规划

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/strategic_ai/army/` | 总体基线：[§6.2、§9.3、§13.1](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

接受王国目标、军团资源和情报，决策集结、行军、攻城、解围、撤退、解散。实际成员、凝聚力和围城由 PARTY/ENC 写。

**协作边界：** SAI、PARTY/WORLD/ENC/SET/POL 许可查询。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

军团任务计划及集合点意图；不保存第二套兵力/凝聚力。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
army_planner / assembly_plan
siege_feasibility / relief_evaluator
supply_risk / retreat_policy
```

## 4. 数据模型与约束

`ArmyContext{members,cohesion,food_days,known_enemies,target,travel_eta,fort_state,authority}`；`ArmyTask{goal,assembly_point,route_target,required_supply,timeout}`。

## 5. 公共接口

```text
generate_army_candidates(ctx) -> Candidate[]
decompose_siege(target, ctx) -> PlanSteps
evaluate_abort(plan, ctx) -> AbortReason?
produce_army_commands(plan,ctx) -> CommandEnvelope[]
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

围城 HTN：验证目标敌对→评估可集结兵力和抵达时间→合法召集→补粮→到达围城→建设器械/封锁→强攻或等待；敌援、缺粮、凝聚力阈值触发补给、解围或撤退。集合超时释放未加入队伍目标；军团解散后队伍 planner 接回控制。

## 7. 配置、异常与安全边界

配置集合超时、最低粮食、可接受兵力比、围城风险及目标锁期。队伍只能参加一军团，玩家队伍未经授权不被 AI 接管。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 批量评估集合路线；统计补给风险、集合耗时、目标失败原因。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SAI-A-01 | SAI-01 / ARM-04 | 成员无法抵达或凝聚不足 | 执行集合 | 超时重评/解散，不重复成员 |
| T-SAI-A-02 | SGE-01 / SAI-03 | 围城期间粮食低、已知援军抵达 | 重评 | 合法撤围/补给或继续并有评分解释 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/strategic_ai/army/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。
