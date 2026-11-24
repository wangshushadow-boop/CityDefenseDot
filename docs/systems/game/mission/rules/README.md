# RULES — Mission 规则、目标与玩法组合

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/rules/` | 总体基线：[§1.2、§10、§13.2、§16.3](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

实现可组合 MissionDefinition、BattleRule、Objective、Round、RewardIntent、退出、重生、部署与模式授权。野战、攻城、竞技、访问等使用同一 Runtime/Combat；不复制一套战斗器，不直接写战役资产。

**协作边界：** CON/DEF、MIS-RT、FORM/COM/MOV/SIEGE/INTERACT/RESULTS 公共接口。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

RuleSetState、ObjectiveState、RoundState、OutcomeDecision、SpawnPolicy 归规则；实体、伤害与槽位归各执行模块。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
mission_definition / rule_registry / mission_rule
objectives/capture / eliminate / defend / escort / escape / timer
modes/field_battle / siege / village / hideout / arena
modes/visit / prison / infiltration / training / story
modes/custom / duel / team_deathmatch / skirmish / captain / multiplayer_siege
round / reward_intent / spawn_policy / withdrawal
```

## 4. 数据模型与约束

`MissionDefinition{id,mode,scene_def_id,systems[],rule_ids[],objective_graph,spawn_policy,permissions}`；`ObjectiveState{id,kind,owners,progress,status,dependencies}`；`Outcome{status,winner_team_keys,reason,objective_results}`；规则接口 `on_start/on_tick/on_event/check_outcome/build_result`。Objective 状态 Inactive→Active→Completed/Failed；终态不可重复奖励。

## 5. 公共接口

```text
create_rules(definition,context) -> Result<RuleSet>
on_start(ctx) -> RuleCommands
on_tick(tick,snapshot) -> RuleCommands
on_event(event,snapshot) -> RuleCommands
check_outcome(snapshot) -> Outcome?
get_spawn_policy(team,phase) -> SpawnPolicy
build_reward_intents(outcome) -> RewardIntent[]
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

模式装配前验证系统依赖、出生/目标、允许权限。野战以可战力量、撤退/士气和目标结束；攻城使用阶段突破/争夺；村庄护送保护非战斗者；藏身处小队逐区/首领；竞技多轮、临时装备、非致命；访问只启用移动和交互；潜入/监狱处理守卫与捕获；训练/剧情使用检查点目标；自定义不改战役。多人决斗、团队死亡竞赛、小队对抗、队长、攻城使用各自计分、重生和角色预算，所有结果仅赛局。每 tick 在伤害后评估目标，统一终局条件与平局/超时规则，进入 Ending 后禁止影响结果。

## 7. 配置、异常与安全边界

奖励意图由 RESULTS 传路由，规则不发长期物品；模式注册需数据校验且权限白名单。临时装备不可流入长期库存；访问模式禁战斗时拒绝攻击。新模式通过扩展注册点组合组件。

## 8. 表现及可观测性

部署、比分、目标 HUD、倒计时、退出/观战和结果按模式展示。

**性能与诊断：** 目标事件增量更新；避免每帧全实体扫描，使用局部计数；记录回合、目标状态、胜负原因。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-RULES-01 | BAT-01 / MIS-01 | 野战、村庄、藏身处、竞技、访问、潜入、剧情各定义 | 运行完整流程 | 规则与目标完成/失败，复用核心 |
| T-RULES-02 | MIS-02 | 竞技临时装备、自定义战斗、战役访问 | 退出 | 无临时奖励/装备串域 |
| T-RULES-03 | MOD-03 / BAT-04 | 自定义地图、天气、人数与野战/攻城 | 完成 | 无战役状态写入 |
| T-RULES-04 | MOD-04 / NET-02 | 五种多人模式含队长与攻城 | 运行回合 | 规则重生、计分和权限正确 |
| T-RULES-05 | SGE-02 | 城防突破并满足占领条件 | 评估 | 不是仅按击杀数判胜 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/rules/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
