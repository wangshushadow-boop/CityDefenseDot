# BAI — 战场 AI 共同基础、感知与调度

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/ai/` | 总体基线：[§12.1、§12.3–12.5、§19.2–19.4](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

战场 AI 的公共协调层，L1 Tactical、L2 Formation、L3 Individual 均独立决策，通过只读快照和统一命令/意图交互。感知、黑板、调度及调试共享；不包含真实位置、生命、命令权威存储。战略 AI 位于 campaign/strategic_ai，不依赖本目录。

**协作边界：** CORE/CON/DEF/SHRULE；MIS-RT、FORM、COM、MOV、RULES 的快照/命令端口。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

每 Mission 的 Blackboard/PerceptionCache/AISchedule 按 team、formation、agent scope 隔离；计划/目标锁归各层 AI；全部可随场景销毁，不进入战役存档。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
tactical/ ; formation/ ; individual/
perception/spatial_index / visibility / threat_summary
blackboard/team_view / formation_view / agent_view
scheduler/decision_budget / lod / job_dispatch
ports/ai_snapshot / intent_sink
debug/decision_trace / overlays
```

## 4. 数据模型与约束

`BattlefieldSnapshot{stamp,team_id,own_units,known_enemy_formations,terrain,objectives,morale,ammo,reinforcements}`；`PerceptionView{agent,nearby_allies,visible_enemies,immediate_threat,expires_tick}`；`DecisionJob{layer,entity,due_tick,priority,snapshot_stamp}`；`IntentOutput{scope_id,tick,handle,sequence,intents}`。黑板为只读派生数据，不是第二权威状态。

## 5. 公共接口

```text
build_ai_views(snapshot,visibility) -> AIViews
SenseNearby(view,agent,radius,max_candidates) -> PerceptionView
schedule_due(tick,budget,importance) -> DecisionJob[]
collect_intents(scope,tick,results) -> ValidatedIntent[]
trace_decision(layer,entity,candidates,reason) -> Unit
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

感知先按空间网格筛近邻→阵营/距离/视线/有效性过滤→限制候选数→构建各层投影。战术 0.5–2 Hz，编队 2–5 Hz，个体 5–20 Hz（源文档初始范围），错峰和优先级预算；受击/格挡/溃逃等紧急反应独立通道。工作线程读不可变快照，结果带 mission_id、tick、generation、order_revision/nav_revision；按稳定顺序提交，失效丢弃/重算。降频不停止权威战斗与移动。

## 7. 配置、异常与安全边界

禁止 AI 全图透视、直接写 COM/MOV/FORM、每 Agent 线程、全敌遍历；LOD 依据重要性和局部威胁，不允许因镜头转向改变已判定伤亡。配置各层频率、近邻上限、预算、缓存 TTL 与紧急反应额度。

## 8. 表现及可观测性

开发模式显示各层目标、得分、感知、路径和预算；玩家只得到合法战场信息。

**性能与诊断：** 空间索引 O(N+N*k) 目标（k 为有限近邻），统计每层执行频率、过期率、P95 决策成本、任务积压。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-BAI-01 | BAI-01 | 玩家与 AI 同时控制编队 | 执行同命令接口 | 授权规则一致，无第二套执行器 |
| T-BAI-02 | BAI-05 | 敌方被遮挡、旧快照返回 | AI 查询与提交 | 只读取许可情报，旧意图拒绝 |
| T-BAI-03 | BAI-06 | 500/1000 混合战场 | 记录调度性能 | 符合 §19.4 待验证预算，无持续积压 |
| T-BAI-04 | BAT-05 | Mission 销毁时 worker 正计算 | 创建新 Mission | 旧意图不能写入 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/ai/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/mission/ai/tactical/` | [L1 战术 AI：全军计划](tactical/README.md) | 独立 SDD |
| `game/mission/ai/formation/` | [L2 编队 AI：执行战术任务](formation/README.md) | 独立 SDD |
| `game/mission/ai/individual/` | [L3 个体 AI：士兵感知、目标与动作意图](individual/README.md) | 独立 SDD |
| `game/mission/ai/perception/` | [战场感知](perception/README.md) | 父规格子目录 |
| `game/mission/ai/blackboard/` | [战场黑板](blackboard/README.md) | 父规格子目录 |
| `game/mission/ai/scheduler/` | [战场 AI 调度](scheduler/README.md) | 父规格子目录 |
| `game/mission/ai/ports/` | [战场 AI 端口](ports/README.md) | 父规格子目录 |
| `game/mission/ai/debug/` | [AI 决策调试](debug/README.md) | 父规格子目录 |
