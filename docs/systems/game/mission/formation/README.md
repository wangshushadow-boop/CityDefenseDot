# FORM — 编队、指挥授权、阵型与槽位执行

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/formation/` | 总体基线：[§12.1–12.4、§17.4、§10.3](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

负责 Team 内编队成员、控制权、订单、阵型/槽位、队形和执行约束。编队 AI 决定行为（BAI-F），本模块接受玩家/AI 同一指令并实现状态；不选择全军战术或直接更新个体位姿。

**协作边界：** CON/DEF、MIS-RT/COM 查询、MOV 路径/投影端口、RULES 权限策略。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Formation{id,team_id,controller,member_handles,order,layout,slots,morale}；本模块写成员/订单/布局/槽分配及聚合士气。Agent.FormationId 为同事务成员索引。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
formation_store / membership
order_authority / order_router / order_queue
layout/line / shield_wall / loose / square / circle / wedge / column
slot_generator / slot_projector / stable_assignment
formation_follow / reorganization / aggregate_stats
```

## 4. 数据模型与约束

`FormationOrder` 保留 §17.4 字段，扩展拟定 `queue_policy,completion_condition,expires_tick?`；`ControllerGrant{controller_ref,scope,priority,expires?,delegated}`；`FormationSlot{id,local_offset,projected_position,agent?,role_constraint}`；`LayoutDef{kind,spacing,row_limit,compression_rules}`。成员最多属于一编队；玩家撤销委派后旧授权 token 失效。

## 5. 公共接口

```text
IssueFormationOrder(order,authority) -> OrderReceipt
Delegate / RevokeControl(formation,controller) -> Receipt
AssignMembers / Split / Merge(formation,selection) -> Receipt
GenerateLayout(formation,layout,terrain_view) -> Slot[]
AssignSlots(members,slots,previous) -> SlotAssignment[]
GetFormationOrderView(id) -> FormationReadView
build_slot_targets(tick,snapshot) -> SlotTarget[]
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

OrderRouter 校验 mission、sequence、控制权、模式允许、目标可达；玩家优先于委派 AI，队长权限限制在自己编队。位置、面向、保持/推进/撤退/冲锋指定队、七类阵型、开停火/骑乘/下马/自由攻击、分组合并、攻城命令均通过订单注册。阵型按队伍数/体型/间距生成局部槽位，投影可行导航区域，按近邻和角色/行列约束稳定分配；尽量保留原槽，死亡仅局部重排。瓶颈压缩/纵队或分列，退出后恢复；中心共享路径+槽位跟随+局部避障，士兵接战可在约束内偏离。更新订单状态 Pending/Active/Completed/Failed/Replaced，返回原因。

## 7. 配置、异常与安全边界

不得每 tick 全局 O(N³) 匹配；配置槽位间距、误差阈值、重排冷却、布局压缩和委派优先级。溃逃和道路失效允许局部脱离并可追溯，不可悄悄覆盖玩家命令。

## 8. 表现及可观测性

战斗 UI 支持多选/全军/编号、阵型预览、方向/目标标记、部署、委派及失败反馈。

**性能与诊断：** 槽位近邻索引、增量成员维护；监控槽位误差、重组次数、命令响应时间和路径共享率。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-FORM-01 | BAI-01 | 玩家命令与委派 AI 同 tick 冲突 | 提交 | 玩家获胜，AI 回执说明 |
| T-FORM-02 | BAI-02 | 七种阵型、伤亡、狭窄通道 | 执行队形切换 | 槽唯一、可达、稳定重组 |
| T-FORM-03 | BAI-05 | 目标不可达或队伍溃散 | 提交/运行订单 | 状态失败或安全调整，HUD 有原因 |
| T-FORM-04 | NET-04 | 另一玩家发送非授权编队订单 | 提交 | Unauthorized，订单不变 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/formation/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
