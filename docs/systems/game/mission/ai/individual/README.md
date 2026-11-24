# BAI-I — L3 个体 AI：士兵感知、目标与动作意图

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/ai/individual/` | 总体基线：[§12.5、§11、§12.8](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

单 Agent 的轻量分层 FSM + Utility 选择。根据编队约束、局部感知、状态及兵种角色生成 MoveIntent/AttackIntent/BlockIntent/EquipIntent 等；不调用伤害写入、不直接移动节点、不拥有编队命令。

**协作边界：** BAI 感知与调度；BAI-F 成员约束、FORM 槽位查询、COM/MOV 执行接口。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

`AIState{mode,target_handle?,target_lock_until,next_decision_tick,role,behavior_memory}` 属于 L3；目标仅句柄和 TTL，不保留旧实体对象。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
controller/agent_brain
 decision/hfsm / utility_selector / reaction
 targeting/target_selector / threat_score
 behaviors/move_to_slot / approach / attack / guard / evade / route
 roles/infantry / archer / cavalry / horse_archer
 behaviors/operate_device / find_mount / recover
```

## 4. 数据模型与约束

`AgentDecisionView{health_state,action_state,perception,formation_constraints,slot_target,equipment,ammo,morale,mount_state}`；`Mode=ExecuteOrder|MoveToSlot|Engage|Recover|FindMount|OperateDevice|Routing|Incapacitated`；`MemberConstraint{fire_allowed,engage_allowed,slot_tolerance,focus_target?,movement_limit}`。`IntentSet` 最多一个主移动、一个兼容动作及必要视角意图。

## 5. 公共接口

```text
decide_agent(view,rng) -> IntentSet
select_target(view,candidates) -> EntityHandle?
react_to_threat(view,threat) -> IntentSet
select_role_action(role,view,target) -> IntentSet
on_intent_rejected(agent,reason) -> AIStateUpdate
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

优先级：失能→NoIntent；溃逃→合法撤离；紧急威胁且可反应→格挡/躲避；已分配器械→操作；需保持队形且槽偏差超阈→回槽；有效目标在攻击范围→攻击/防御；命令允许交战→接近/射击；否则保持/跟随。目标评分考虑可达距离、威胁、兵种适配、已围攻人数、命令偏离；锁定与冷却防抖。步兵近战择合法方向/时机，远程装填、保持射线和距离，骑兵考虑转向/冲锋后脱离，骑射在可达空间移动射击；技能/难度控制反应延迟、判断误差和格挡成功能力，不赋予透视。最终动作仍由 COM 校验。

## 7. 配置、异常与安全边界

5–20 Hz 初始；紧急反应单独预算。目标死亡/过期/generation 改变则清除，动作被拒绝不连续发送同非法命令。禁止逐兵全场查询、无条件瞬移、直接修改敌人生命、绑定特定动画。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 每 Agent 紧凑状态，有限候选数和 FSM 转换；记录反应延迟、目标切换、拒绝率和各角色 tick 成本。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-BAI-I-01 | BAI-03 | 四类兵种和各自合法装备 | 运行交战 | 角色决策不同、意图统一 |
| T-BAI-I-02 | BAI-05 | 敌人被遮挡或目标 handle 失效 | 决策 | 不继续非法攻击，重选有限候选 |
| T-BAI-I-03 | COM-05 | 同一动作玩家与 AI 发起 | 执行 | 由同一 COM 校验，结果语义一致 |
| T-BAI-I-04 | BAI-06 | 千人压力且出现紧急威胁 | 运行 | 紧急反应可执行，低频不冻结移动 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/ai/individual/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/mission/ai/individual/controller/` | [个体决策控制器](controller/README.md) | 父规格子目录 |
| `game/mission/ai/individual/decision/` | [个体决策](decision/README.md) | 父规格子目录 |
| `game/mission/ai/individual/targeting/` | [目标选择](targeting/README.md) | 父规格子目录 |
| `game/mission/ai/individual/behaviors/` | [个体行为](behaviors/README.md) | 父规格子目录 |
| `game/mission/ai/individual/roles/` | [兵种行为策略](roles/README.md) | 父规格子目录 |
