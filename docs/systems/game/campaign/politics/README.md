# POL — 王国、决议、外交、战争与身份

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/politics/` | 总体基线：[§9.1–9.2、§17.5](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

维护王国成员资格、政治决议、政策、国家间战争和平、协议、战争统计与政治授权；领地归属由 SET 写，影响力/贡金由 INV 写，家族和军团引用通过 APP 一致更新。

**协作边界：** DEF/SHRULE；CLAN/SET/PARTY/INV/WORLD 公开查询及应用用例。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Kingdom、Membership、Decision、DiplomaticRelation、Treaty、WarStats 为权威数据；Clan.kingdom_id 与 Kingdom.members 一处真值的事务投影，禁止独立修改。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
kingdom / membership / succession
policy / decision / voting / influence
relation_pair / treaty / war / peace
negotiation / feud / fief_authorization
kingdom_lifecycle / war_statistics
```

## 4. 数据模型与约束

`Decision{id,kind,proposer,candidates,eligible_voters,deadline,ballots,status}`；`DiplomaticRelation{ordered_pair,state,since,treaties}`（键为排序无序对）；`Treaty{id,terms,signatories,expiry,obligations}`；`Membership{clan,kingdom,kind,contract}`。`DecisionStatus=Proposed|Voting|Resolved|Committed|Cancelled`。

## 5. 公共接口

```text
JoinKingdom / LeaveKingdom / FoundKingdom(...) -> ChangeSet
ProposeDecision(actor,kind,candidates) -> ChangeSet
Vote(decision,clan,candidate,influence) -> ChangeSet
ResolveDecision(decision,ruler_choice) -> ChangeSet
DeclareWar / MakePeace(authorization,terms) -> ChangeSet
ProposeTreaty / AcceptTreaty(...) -> ChangeSet
GetPoliticalEligibility(actor,action) -> Eligibility
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

提案验证身份、候选合法性、当前状态→冻结候选及选民资格→投票窗口锁定/扣影响力→到期按配置权重统计、君主确认→应用层统一提交决议。宣战更新唯一关系对并通知战略/世界通行；议和取消不再合法的追击围城，按协议处理俘虏军团和贡金。战争统计消费已提交结果而非直接读战场。王国消亡处置剩余成员、领地、协议、决议和任务，允许合法重建。

## 7. 配置、异常与安全边界

一方不能与自身宣战；战争关系对称；政治身份与人物私仇独立。期限按游戏分钟，投票重复命令幂等；候选实体失效则按规则撤销或重开，不静默替换。涉及资产转移先校验授权与余额。

## 8. 表现及可观测性

王国界面展示候选、票数、费用、授权、战争统计、政策效果与谈判条件。

**性能与诊断：** 关系按 pair 索引；事件增量聚合战争损失，避免每次遍历全历史。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-POL-01 | POL-01 | 佣兵加入、封臣退国与建国 | 执行身份变更 | 唯一合法成员关系，收入及战争关系同步 |
| T-POL-02 | POL-02 | 非成员、重复投票和截止后投票 | 提交 | 拒绝；合法决议影响力仅扣一次 |
| T-POL-03 | POL-03 | 战争期间有效围城与追击 | 议和 | 取消非法行动并应用协议、贡金 |
| T-POL-04 | POL-04 | 最后封地易主或君主死亡 | 执行兴亡/继任 | 合法政治引用，无孤儿决议 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/politics/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
