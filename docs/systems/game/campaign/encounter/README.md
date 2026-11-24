# ENC — 遭遇、战略围城、预留与自动结算

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/encounter/` | 总体基线：[§4.3、§9.4、§10.2、§13.1、§17.4](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

维护遭遇状态、战役围城、参战预留、自动战斗与跨域结果提交。战略 AI 只提出意图；Mission 只输出临时结果，APP 调度，ENC 负责验证与准备战役结算写集。

**协作边界：** CON/SHRULE/DEF；PARTY、CHR、INV、SET、POL、WORLD 门面；PERSIST 由 APP 协调。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Encounter、Reservation、SiegeState、PendingResult、AppliedResultId 权威存储；PARTY 提供预留可用量，Mission 不直接扣战役兵力。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
encounter / negotiation / reservation
encounter_spec_builder / scene_selector
strategic_siege / blockade / engine_build_plan
auto_resolve / effective_power / casualty_sampler
result_validator / settlement_plan / result_receipt
```

## 4. 数据模型与约束

`Encounter{id,kind,participants,reservations,phase,revision,committed_result_id?}`；`Reservation{source_party,source_slot_range,troop_def_id?,hero_id?,count,loadout_snapshot}`；`SiegeState{target,attackers,defenders,build_progress,devices,fort_damage,supplies,start_minute}`。状态 Created→Negotiating→Reserved→MissionRunning/AutoResolving→ResultReady→Committed 或 Cancelled；仅合法跃迁。

## 5. 公共接口

```text
BeginEncounter(contact, participants) -> Result<EncounterId>
ReserveEncounter(encounter, selection) -> ChangeSet
BuildEncounterSpec(encounter) -> Result<EncounterSpec>
StartSiege / BuildSiegeDevice / LiftSiege(...) -> ChangeSet
AutoResolve(encounter,seed,policy) -> EncounterResult
CommitEncounterResult(result) -> Result<SettlementReceipt>
CancelEncounter(id,reason) -> ChangeSet
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

接触/围城验证外交、参与资格、来源不重复→生成唯一槽范围、锁名册/装备快照→保存战前检查点→APP 启动 Mission 或自动结算。自动结算按回合以兵种角色、装备、地形、士气、统帅和克制计算有效战力，按随机流抽取有界伤亡，每轮从剩余槽扣除，终止于撤退/无战力/回合上限；采用与实时同一结果语义。围城日结构筑器械、封锁交通、粮耗及工事损伤，援军可解围。结算先核对 result_id、revision、所有槽终态、英雄和俘虏归属；计算名册、装备、经验、战利品、领地、关系写集；一次持久提交去重记录，释放预留。

## 7. 配置、异常与安全边界

已经进入实时 Mission 的预留不得自动结算；加载失败按检查点取消。未入场不算死亡；撤离与伤情正交。失败强攻可回到 SiegeState；占领必须取得规则授权。重复 result_id 相同哈希返回原回执，内容不同 Conflict。

## 8. 表现及可观测性

遭遇面板提供谈判、派兵、撤退、攻城/解围、兵力与器械预览，结果显示各来源变化。

**性能与诊断：** 批量槽区间压缩；自动战斗离线与实时胜率/伤亡分布对比；记录预留年龄、结算重试、校验失败。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-ENC-01 | SAI-02 | 固定输入和种子的自动遭遇 | 重复结算计算 | 结果可复现、来源槽总量守恒 |
| T-ENC-02 | BAT-03 | 提交前/中/后故障 | 恢复并重试 | 无重复资产或丢失已提交结果 |
| T-ENC-03 | ARM-05 / BAT-02 | 有预备队未生成 | 实时战斗结束 | 每槽唯一终态，未生成归源 |
| T-ENC-04 | SGE-01 | 围城设备建造且商路阻断 | 推进/解围 | 费用、工事、粮耗和恢复一致 |
| T-ENC-05 | SGE-03 | 强攻失败或守军出击成功 | 提交 | 围城或撤围状态按规则，领地不错误易主 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/encounter/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
