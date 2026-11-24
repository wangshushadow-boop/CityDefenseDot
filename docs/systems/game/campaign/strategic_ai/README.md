# SAI — 战略 AI 总控、调度与任务规划

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/strategic_ai/` | 总体基线：[§9.3–9.5、§4.2、§19](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

L0 战略 AI 总控。协调王国、家族、军团、队伍四类 planner，使用 Utility AI + 任务 FSM + 有限 HTN，输出合法战役命令。只读可见快照，不直接写领域真值，不负责自动战斗计算（ENC）。

**协作边界：** CORE/CON/DEF/SHRULE；WORLD 可见快照、POL/CLAN/PARTY/ECO/SET 查询端口、APP 命令端口。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

AIPlan、Goal、PlanCursor、Cooldown、LastScore 和许可情报缓存持久化；领域命令执行结果归实际模块。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
scheduler / strategic_context / plan_store
planning/htn_decomposer / task_fsm
evaluation/utility_score / hard_constraints
perception/intel_projection
kingdom/ ; clan/ ; army/ ; party/
```

## 4. 数据模型与约束

`StrategicPlan{owner_ref,goal,steps[],cursor,state,score,locked_until,retry_after,source_revision}`；`Candidate{kind,target,expected_value,p_success,travel_cost,risk,resource_cost,urgency,personality_bias}`。状态 Proposed→Committed→Executing→Succeeded/Failed/Cancelled；步骤状态 Pending/Running/Done/Blocked。

## 5. 公共接口

```text
schedule_due(game_minute, budget) -> PlannerJob[]
evaluate_candidates(context, candidates) -> RankedCandidates
choose_plan(current, ranked, rng) -> PlanDecision
decompose(goal, context, max_depth) -> PlanSteps
step_plan(plan, visible_snapshot) -> CommandEnvelope[]
on_command_receipt(plan_id, receipt) -> PlanUpdate
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

先按权限、资源、可达性、外交和冷却硬过滤；score=priority*expected_value*p_success-travel_cost-risk*risk_aversion-resource_cost+urgency+personality_bias。统一量纲归一化范围配置，分数/来源写调试；新分数未超过当前+switch_margin 则保留。HTN 仅为复杂目标分解有限步骤，计划锁期、失败冷却和小随机扰动避免抖动。战略计划每 1–6 游戏小时错峰，队伍执行 10–60 分钟或事件触发。结果陈旧重算；命令提交重验版本。

## 7. 配置、异常与安全边界

不可用全局敌军实时坐标、无限资源、绕过玩家/政治权限；AI 的难度加成显式配置。配置候选数量、HTN 深度、锁定时间、重试/危险权重。计划失败不重复无成本尝试。

## 8. 表现及可观测性

调试面板展示目标、候选分数分项、失败原因与计划阶段；玩家 UI 只看许可情报。

**性能与诊断：** 按王国/队伍/区域分片；限制每次候选和路径请求；监控计划失败率、切换率、命令拒绝、可见性访问。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SAI-01 | SAI-01 | 资源、可见情报与外交限制同时存在 | 生成计划 | 只输出合法候选并使用同一命令接口 |
| T-SAI-02 | WLD-03 | 敌方未发现且移动 | 重新评分 | 不读取其真实坐标 |
| T-SAI-03 | SAI-03 | 长期世界仿真 | 记录计划切换 | 无高频抖动、无无限补兵，政治经济轨迹可解释 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/strategic_ai/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/campaign/strategic_ai/kingdom/` | [战略 AI：王国规划](kingdom/README.md) | 独立 SDD |
| `game/campaign/strategic_ai/clan/` | [战略 AI：家族规划](clan/README.md) | 独立 SDD |
| `game/campaign/strategic_ai/army/` | [战略 AI：军团规划](army/README.md) | 独立 SDD |
| `game/campaign/strategic_ai/party/` | [战略 AI：队伍规划与类型策略](party/README.md) | 独立 SDD |
| `game/campaign/strategic_ai/planning/` | [战略任务规划](planning/README.md) | 父规格子目录 |
| `game/campaign/strategic_ai/evaluation/` | [战略候选评估](evaluation/README.md) | 父规格子目录 |
| `game/campaign/strategic_ai/perception/` | [战略情报](perception/README.md) | 父规格子目录 |
| `game/campaign/strategic_ai/scheduler/` | [战略 AI 调度](scheduler/README.md) | 父规格子目录 |
