# SAI-P — 战略 AI：队伍规划与类型策略

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/strategic_ai/party/` | 总体基线：[§4.3、§6、§7.2、§9.3](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

领主、商队、村民、盗匪、家族队伍的巡逻、交易、招兵、追击、逃离、返城与军团命令执行。共享移动和资源用例，按队伍类型注册策略。

**协作边界：** SAI、WORLD/PARTY/ECO/SET/ENC/POL 许可查询。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

每队目标、路径请求意图、行为状态与冷却持久化；位置和路线执行归 WORLD。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
party_planner / order_executor
strategies/lord / caravan / villager / bandit
strategies/family_party
threat_evaluator / opportunity_selector
```

## 4. 数据模型与约束

`PartyContext{kind,visible_intel,own_roster,food_days,cash,capacity,current_order,army_order?,market_quotes}`；`PartyBehavior=Travel|Patrol|Trade|Recruit|Pursue|Flee|Rest|JoinArmy|Wait`。

## 5. 公共接口

```text
select_policy(kind) -> PartyPolicy
generate_party_candidates(ctx) -> Candidate[]
step_behavior(plan,ctx) -> CommandEnvelope[]
score_trade_route(quotes,eta,risk,cost) -> ScoreBreakdown
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

优先处理合法军团指令和紧急逃离；领主按补给、兵力与目标巡逻/招募/追击，商队按可见价格、容量、风险和预计净收益选择交易路线，村民运输真实产出，盗匪受地区治安与生成冷却限制。路径不可达/报价过期/接触失败时退避重评；实际移动与遭遇走 WORLD/ENC。

## 7. 配置、异常与安全边界

配置危险容忍、返城阈值、库存保留、队伍行为间隔和候选上限。不可利用不可见敌情、凭空交易或刷盗匪。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 区域错峰计划、共享路径候选缓存；记录行为驻留时间、空转和交易成功率。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SAI-P-01 | SAI-01 / WLD-03 | 商队有货、路线敌情过期 | 选择路线 | 按许可情报与风险评分，交易资金真实 |
| T-SAI-P-02 | ECO-04 / SAI-03 | 利润为负且补给低 | 运行行为 | 返回补给/停业，无无限资金 |
| T-SAI-P-03 | ARM-04 | 军团任务结束 | 更新 | 队伍恢复自身合法目标 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/strategic_ai/party/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。
