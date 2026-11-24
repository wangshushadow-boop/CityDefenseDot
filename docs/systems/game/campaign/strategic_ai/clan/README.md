# SAI-C — 战略 AI：家族规划

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/strategic_ai/clan/` | 总体基线：[§5.2、§9.3](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

家族资源经营、招募、角色任命、投票、婚配、投奔、队伍创建等目标决策；真实家族关系、资产和政治状态仍由 CLAN/INV/POL 写。

**协作边界：** SAI、CLAN/CHR/POL/INV/SET/PARTY 许可查询。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

家族目标计划、性格权重和失败冷却；不持有资产真值。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
clan_planner / household_budget
role_candidate_selector / political_preference
marriage_and_succession_policy
```

## 4. 数据模型与约束

`ClanContext{cash,expected_income,wages,fiefs,available_heroes,relations,renown,political_eligibility}`；`ClanGoal{kind,target,minimum_reserve,priority}`。

## 5. 公共接口

```text
generate_clan_candidates(ctx) -> Candidate[]
choose_role_candidate(role,heroes) -> Candidate?
plan_clan_action(goal) -> PlanSteps
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

先保留工资/粮食预算，再评分招募、经营、任命、增建队伍等；婚配候选由成年亲缘规则过滤；政治投票考虑关系、收益与影响力，但同样走 POL 投票。无领地或破产调整经营/投奔目标；领导者死亡触发合法继任处理。

## 7. 配置、异常与安全边界

配置性格偏好、最低储备、角色替换阈值、婚姻冷却；禁止访问他人私有资产或强制覆盖玩家任命。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 按家族日级/事件更新，缓存候选资格；统计破产和角色空缺。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SAI-C-01 | SAI-01 / CLN-01 | 可用英雄少且资金紧张 | 规划 | 无非法任命或超预算招募 |
| T-SAI-C-02 | CLN-02 / SAI-03 | 家族领袖死亡 | 更新 | 合法继任并重新规划 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/strategic_ai/clan/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。
