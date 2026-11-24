# CAMP — 战略世界运行时

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/ （根级编排文件）` | 总体基线：[§3.4、§4.2、§10.2、§17、§22](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

CampaignRuntime 装配各战略领域仓库和每日计划，协调世界生命周期、只读快照、仿真相位和规则注册；世界、政治、经济等模块各自拥有数据。不得运行实时 Agent 或管理联网赛局。

**协作边界：** CORE/CON、shared；本域各公开门面由 BOOT 注入；通过 APP 对接 Mission。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

WorldState 为 Campaign 聚合根，包含 game_minute、revision、seed、rng_states、repositories；各仓库写权仍归其领域。运行时仅维护 phase_cursor、checkpoint、日结去重标记与索引。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
campaign_runtime
world_state / repository_registry
campaign_snapshot_builder
phase_pipeline / daily_processor
world_factory / campaign_invariant_checker
```

## 4. 数据模型与约束

`CampaignPhase{minute, day_index, phase_id, cursor, expected_revision}`；`WorldSnapshot{stamp, visibility_context, projection}`；`DayPlan{day_id, production, market, supply, settlement, politics}`。索引可重建，日结中间写集不可发布为已提交日终快照。

## 5. 公共接口

```text
create_world(seed, start_def, content) -> Result<WorldState>
step_until(target_minute, budget) -> StepReport
read_snapshot(visibility_context) -> WorldSnapshot
prepare_day(day_id) -> DayPlan
commit_day(day_plan) -> Result<Revision>
freeze_for_encounter(id) -> FreezeToken
restore(snapshot) -> Result<Unit>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

整数分钟推进至下个关键事件边界 → 地图/遭遇检查 → 队伍行为 → 到期 AI → 日结阶段：生产消费计划、账本校验、市场、补给薪资、领地、政治、日终。各相位按稳定键分片；阶段之间读取明确版本。跨日不得跳过日结；战斗冻结用 token 释放，按规则推进战后时间。创建世界按内容定义稳定顺序分配 ID，保存随机流。

## 7. 配置、异常与安全边界

若日结预算不足，保留工作游标，阻止 UI 获取部分新日终快照；存档只在安全边界，或持久化明确恢复日志。单人暂停禁止积累大量真实时间补偿。数据不变量失败暂停模拟并报告，不静默修复账本。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 以总体 §19.4 的 300–500 地点、2000–5000 队伍为待验证目标；测快进速度、每日耗时、快照复制量。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-CAMP-01 | WLD-02 | 日结执行到一半预算耗尽 | 下一帧继续 | 所有 day_id 阶段一次完成且最终账本一致 |
| T-CAMP-02 | WLD-04 | 战役进入访问或战斗 | 结束返回 | 时间按规则推进、远方状态不丢失 |
| T-CAMP-03 | WLD-05 | 同内容、种子和开局 | 创建两次 | 规范化初始状态哈希一致 |
| T-CAMP-04 | SAI-03 / ECO-06 | 20 固定种子无玩家仿真十年 | 每日检查 | 无非法资源/孤儿引用，输出软指标轨迹 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/campaign/world/` | [世界地图、时钟、交通、情报](world/README.md) | 独立 SDD |
| `game/campaign/character/` | [英雄、成长、装备与生命状态](character/README.md) | 独立 SDD |
| `game/campaign/clan/` | [家族、婚育、同伴、职责与继承](clan/README.md) | 独立 SDD |
| `game/campaign/party/` | [队伍、军团、名册、俘虏、补给](party/README.md) | 独立 SDD |
| `game/campaign/economy/` | [经济、市场、商队、工坊与锻造](economy/README.md) | 独立 SDD |
| `game/campaign/settlement/` | [城镇、城堡、村庄与领地治理](settlement/README.md) | 独立 SDD |
| `game/campaign/politics/` | [王国、决议、外交、战争与身份](politics/README.md) | 独立 SDD |
| `game/campaign/encounter/` | [遭遇、战略围城、预留与自动结算](encounter/README.md) | 独立 SDD |
| `game/campaign/quest/` | [动态任务、剧情导演、对话与事件](quest/README.md) | 独立 SDD |
| `game/campaign/strategic_ai/` | [战略 AI 总控、调度与任务规划](strategic_ai/README.md) | 独立 SDD |
