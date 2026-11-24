# INTERACT — 场景交互、NPC 与访问流程

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/interaction/` | 总体基线：[§8.3、§13.2、§14.3、§15](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

管理访问/任务场景中的互动对象、NPC 实例、道具、设施、交互授权和请求。场景 NPC 由世界投影创建，任务/对话和资产写入走 APP/QUEST/SET；不保留已死亡英雄的永久场景副本。

**协作边界：** CON/DEF、MIS-RT、MOV/COM、RULES、APP 业务用例端口。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

InteractionPoint、NPCSpawnBinding、InteractionSession、局部道具状态临时；人物持久身份归 CHR。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
interaction_point / interactable_registry
npc_schedule_projection / visitor_spawn
interaction_authority / proximity_query
handlers/dialogue / shop / recruitment / arena / prison / door
crime_context / escape_trigger / interaction_feedback
```

## 4. 数据模型与约束

`Interactable{id,kind,position,radius,condition_keys,handler_key}`；`NPCBinding{agent_handle,hero_id?,def_id,schedule_slot}`；`InteractionRequest{actor,target,action,mission_id,revision}`；`InteractionSession{token,actor,target,state,expires_tick}`。临时 NPC 必须带来源或明确非持久定义。

## 5. 公共接口

```text
ListNearbyInteractions(actor,visibility) -> InteractionOption[]
BeginInteraction(request) -> Result<InteractionSession>
ExecuteInteraction(token,choice) -> Receipt
EndInteraction(token,reason) -> Unit
refresh_npc_projection(world_view) -> SpawnChanges
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

按世界身份/外交/犯罪/任务/装备投影生成 NPC 与设施；邻近与视线筛选→授权→建立会话→交互选择重新校验对象在场和状态→调用 Dialogue/Trade/Recruit 等 APP 用例。被捕、越狱、潜入失败由 Mission 规则输出合法结果。访问退出关闭会话、释放临时对象。酒馆小游戏、竞技负责人、商人、名人等以 handler 注册扩展，不直接操作长期库存。

## 7. 配置、异常与安全边界

配置交互距离、视线、NPC 排班、会话 TTL、访问权限条件；动态 NPC 死亡/被俘/易主时按冻结世界或允许更新规则刷新。重复点击或旧 token 不重复发奖励。

## 8. 表现及可观测性

交互名称、距离、可执行选项、访问限制和被捕/退出原因。

**性能与诊断：** 空间索引查询邻近互动；按排班/事件刷新，不每帧生成 NPC；记录授权失败。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-INTERACT-01 | SET-04 | 世界中领主死亡、商人存在 | 进入城镇 | 仅合法 NPC 生成 |
| T-INTERACT-02 | QST-04 | 对话目标离场或权限变化 | 执行选择 | 拒绝/替代流程，无越权 |
| T-INTERACT-03 | MIS-01 / MIS-02 | 潜入、监狱、酒馆和访问 | 交互并离开 | 规则反馈正确，无临时装备串域 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/interaction/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
