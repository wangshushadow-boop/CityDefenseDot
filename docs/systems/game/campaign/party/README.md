# PARTY — 队伍、军团、名册、俘虏、补给

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/party/` | 总体基线：[§6、§9.3、§10.2、§17](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

拥有战役兵力、编制、军团成员、预留可用量、工资、士气、俘虏与载重规则；World 写位置、Inventory 写库存与账户、Encounter 写参战 reservation。不可为每普通兵创建持久实时 Agent。

**协作边界：** DEF/SHRULE、INV/CHR/CLAN/WORLD/POL 的公共投影，APP 事务。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Party/Army 持久记录，RosterEntry 按兵种和经验桶聚合；预留锁由 ENC 发起，PARTY 维护可用量投影。英雄入队与被俘需更新 CHR.location_ref/life_status。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
party / army / roster / xp_bucket
recruitment / training / upgrade
prisoner_roster / ransom / conversion
supply / wage / morale / capacity
army_cohesion / transfer / reservations_view
```

## 4. 数据模型与约束

`RosterEntry{troop_def_id,healthy_count,wounded_count,xp_buckets[]}`；`Party{id,kind,leader_id?,owner_ref?,pos(只读投影),roster,prisoner_roster,inventory_id,account_id,morale,order}`；`Army{id,kingdom_id,leader_party_id,party_ids,target,cohesion}`。available = total - reserved；任何转移不得修改已预留槽。

## 5. 公共接口

```text
Recruit(party,source,troop,count) -> ChangeSet
Upgrade(party,edge,count,xp_bucket_ids) -> ChangeSet
TransferTroops(src,dst,selection) -> ChangeSet
RansomPrisoners(party,selection,quote) -> ChangeSet
CreateArmy(leader, members, contract) -> ChangeSet
JoinArmy / LeaveArmy / DisbandArmy(...) -> ChangeSet
plan_daily_supply(day_id, party) -> ResourcePlan
apply_roster_outcomes(reservation,outcomes) -> ChangeSet
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

招募先锁名额、兵源、资金→从真实来源减少、名册增加；训练经验分桶，升级扣达到阈值的兵和对应经验、材料、金钱，DAG 不允许循环。转移/俘虏赎回先计算容量，再同事务更改两边。每日按在队人数/动物/俘虏计算粮耗和工资，库存不足按明确优先级消耗；多样性、战绩、饥饿、欠薪影响士气；低于阈值生成有种子的逃兵候选。军团集结基于唯一成员，凝聚力衰减，补充影响力或解散，成员补给显式转账。

## 7. 配置、异常与安全边界

所有数量、经验桶、金钱非负；容量不足拒绝或预览合法上限，不静默截断。参战预留不能升级/转移。伤兵恢复重新分类不增总量。俘虏逃脱/转化与英雄身份同步。兵种树与日耗参数由 DEF/SHRULE。

## 8. 表现及可观测性

队伍/库存界面预览容量、工资、载重、升级条件；批量操作取消不改数据。

**性能与诊断：** 以兵种/经验桶批处理；记录来源兵力流、军团凝聚、每日补给成本、预留冲突。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-PARTY-01 | ARM-01 | 有经验、资金和材料的名册 | 招募、训练、升级、转驻军 | 数量和 XP 变化合法，无循环升级 |
| T-PARTY-02 | ARM-02 | 库存少于当日粮耗并拖欠工资 | 日结 | 不负库存，士气变化且逃兵有来源 |
| T-PARTY-03 | ARM-03 | 有普通俘虏和英雄俘虏 | 赎回、转化、逃脱 | 英雄位置唯一，正确移除名册 |
| T-PARTY-04 | ARM-04 | 同一 Party 已在 Army A | 加入 B 或解散 A | 拒绝重复成员，解散释放控制 |
| T-PARTY-05 | ARM-05 / BAT-02 | 兵力已预留且部分未上场 | 尝试转移并结算 | 拒绝预留转移；未入场归原队伍 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/party/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
