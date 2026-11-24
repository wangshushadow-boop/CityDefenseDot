# RESULTS — 来源追踪、战斗结果与统计

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/results/` | 总体基线：[§10.2、§10.5、§17.4、§22](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

负责把 Mission 权威终态转为版本化 MissionResult：来源槽、伤亡、未入场、俘虏候选、经验、战利品声明、器械变化、目标统计。不直接执行战役结算，也不把自定义/多人结果发送到战役资产。

**协作边界：** CON、MIS-RT/COM/FORM/RULES/SIEGE 的只读终态；APP ResultRouter。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

SourceSlotTracker、ResultBuilder、MissionStats 在 Mission 内；最终结果不可变。战役 result_id 去重与持久提交归 ENC。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
source_slot_tracker / spawn_binding
casualty_classifier / withdrawal_tracker
xp_aggregator / loot_claim_builder / hero_outcomes
result_builder / invariant_validator / stats
```

## 4. 数据模型与约束

`SlotOutcome{source_slot_id,end_status,wounded,captor_team_key?,xp}`，end_status 为 alive/wounded/dead/captured/withdrawn/not_spawned（拟定枚举，wounded 与撤离正交）；`MissionResult` 保留 §17.4 所有字段，带唯一 result_id、mission_id、reservation_revision、integrity_hash。战场失能不等同死亡，结算医术规则可转换。

## 5. 公共接口

```text
bind_spawn(slot,handle) -> Result<Unit>
record_terminal(slot,observed_outcome) -> Result<Unit>
collect_stats(snapshot,events) -> MissionStats
build_result(final_snapshot,outcome) -> Result<MissionResult>
validate_source_coverage(spec,result) -> ValidationReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

初始化登记全部预留槽含未入场；出生绑定唯一 handle；伤害/撤退/俘虏候选按权威事件记录，禁止重复终态。结束屏障读取最终实体/规则、器械状态，未出生标 not_spawned，区分撤离及伤病；汇总每源槽 XP 和合法 loot claim，生成不可变结果及哈希。结果有效性检查来源覆盖、count、英雄唯一、队伍归属、目标/时间；可压缩连续同终态槽范围。战役医术、俘虏容量、奖励及领地变化由 ENC 重新验证。

## 7. 配置、异常与安全边界

禁用结果构建后继续写状态；同源槽不可既死亡又被俘。自定义/多人无 encounter_id，不生成战役结算授权。完整性哈希用于损坏检测，不替代服务端认证签名。

## 8. 表现及可观测性

战后面板显示各队来源、伤亡、未入场、经验、俘虏和后续选择；战役实际奖励以提交回执为准。

**性能与诊断：** 来源槽按范围压缩、增量统计；记录结果大小、漏槽/重复槽、构建 P95。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-RESULTS-01 | BAT-02 / ARM-05 | 部分槽未生成、撤离受伤、英雄击倒 | 构建结果 | 每槽唯一分类，总量守恒 |
| T-RESULTS-02 | BAT-03 | 缺槽、重复槽、revision 不符 | 验证 | 拒绝并保留诊断 |
| T-RESULTS-03 | BAT-04 | 自定义或多人赛局 | 结果路由 | 不会生成战役资产变更 |
| T-RESULTS-04 | SGE-03 | 城防和设备损坏 | 生成结果 | 差异可追踪且不误计人形槽 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/results/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
