# MIS-RT — Mission 运行时、实体与增援

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/runtime/` | 总体基线：[§10.1、§10.3–10.5、§11.1、§19](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

管理每个局部 Mission 的生命周期、Team、EntityStore、系统装配、固定步长、部署、SpawnDirector 和释放屏障；不实现伤害、AI 策略或各玩法胜负。场景访问也走 Mission，可按规则禁用 Combat 和 Formation。

**协作边界：** CORE/CON/DEF、Mission 各公开系统接口；APP/EngineAdapter 负责初始化与场景资源。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

MissionState{id,ruleset_id,tick,teams,entity_store,objectives,spawn_state,result_builder}；Runtime 拥有实体句柄分配、Team、源槽绑定及组件生命周期。组件写权见模块表；Combat 写 Health/Action/Equipment，Movement 写 Transform/Kinematics，Formation 写成员与命令。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
mission_runtime / mission_context / phase_pipeline
entity_store / entity_handle / component_registry
team_registry / spawn_director / deployment
source_slot_map / system_registry
lifecycle / dispose_barrier / mission_snapshot
```

## 4. 数据模型与约束

`MissionPhase=Preparing|Deployment|Running|Ending|Finalizing|Disposed`；`EntityHandle{index,generation}`；`SpawnTicket{source_slot,team_key,loadout,spawn_zone,priority}`；`Team{id,key,faction_ref,controller_policy}`。每个槽仅可对应一个活跃人形 Agent；骑乘马、弹体、器械使用非兵力实体句柄，不能计入兵源。

## 5. 公共接口

```text
prepare(spec,scene,ruleset) -> Result<MissionContext>
register_system(phase,system) -> Result<Unit>
allocate_entity(source_slot?,components) -> EntityHandle
apply_deployment(orders) -> Receipt
step_fixed(tick,inputs) -> TickReport
request_end(outcome) -> Result<Unit>
finalize() -> MissionResult
dispose() -> DisposeReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

创建 scope/随机流/资源租约→验证出生、导航和规则→按来源槽、战场容量、阵营配额准备部署→固定 tick：输入校验/障碍快照→战术编队个体 AI→移动→动作和命中候选→伤害/士气/成员数→目标/撤退/波次/结束→发布快照、延迟销毁。初始 60 Hz（30 Hz 待验证），渲染插值。增援从未生成槽选择合法安全出生区，考虑波次冷却与阵营配额，失败重试或保留未入场。结束冻结输入、屏障收集结果、路由、释放。

## 7. 配置、异常与安全边界

同一 Mission 唯一 scope；旧回调、过期实体 generation 拒绝。结束态禁止再改变结果的输入；出生点不可达不得在敌人中硬生成。每场战役源槽必须有终态（RESULTS）。英雄击倒不改变持久 HeroId。

## 8. 表现及可观测性

部署 UI 显示配额、编队及合法区；战斗 HUD 使用只读快照；击倒后的观战/委派按规则。

**性能与诊断：** 每系统 tick P50/P95/P99；500/1000 真战斗基准；记录活动实体、排队/失败出生、固定步积压、资源租约。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-MIS-RT-01 | BAT-01 | 双方兵力已预留、规则野战 | 部署并战斗到结束 | 胜负和结果正确，源槽完整 |
| T-MIS-RT-02 | BAT-02 | 总兵力 1000、同屏上限 500 | 多波增援、撤退 | 无重复生成，未入场保留 |
| T-MIS-RT-03 | BAT-05 | 50 次创建销毁且有在途任务 | 切换场景 | 无跨 Mission 回调或单调资源泄漏 |
| T-MIS-RT-04 | MIS-02 | 访问规则无 Combat | 启动并退出 | 仍能移动交互，无战斗系统副作用 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/runtime/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
