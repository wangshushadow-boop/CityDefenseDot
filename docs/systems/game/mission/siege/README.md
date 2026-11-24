# SIEGE — 实时攻城器械、城防与动态连接

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/mission/siege/` | 总体基线：[§13.1、§12、§10.2](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

管理实时城门、城墙损坏、梯/攻城塔、冲车、投射器械、乘员槽、器械操作与动态导航变更；战略围城建造/补给归 ENC；目标胜负归 RULES。器械伤害通过 COM 兼容目标/碰撞，损毁状态由本模块写。

**协作边界：** MIS-RT、COM、MOV、FORM、RULES、CON/DEF。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

SiegeDevice、FortificationSegment、CrewSlot、BreachState 临时实体；战场结束生成 siege_changes 由 RESULTS 捕获并交 ENC 回写。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
fortification/gate / wall_segment / breach
 devices/device_state / battering_ram / tower / ladder / artillery
 crew_slot / operation_authority / device_damage
 link_coordinator / siege_snapshot_loader / siege_result_view
```

## 4. 数据模型与约束

`SiegeDevice{id,kind,transform,phase,health,ammo,crew_slots,team,route}`；`DevicePhase=Assembling|Moving|Deployed|Loading|Firing|Damaged|Disabled`；`FortificationSegment{id,damage_stage,health,link_ids,variant}`；`CrewSlot{index,role,occupant?,interaction_point}`。器械和城防不属于来源兵力槽。

## 5. 公共接口

```text
LoadSiegeSnapshot(spec) -> Result<Unit>
AssignCrew / ReleaseCrew(device,agent,slot) -> Receipt
OperateDevice(device,actor,intent) -> Receipt
ApplyDeviceDamage(target,damage_result) -> SiegeDelta
UpdateFortification(segment,damage) -> LinkChange[]
GetSiegeResultView() -> SiegeChanges
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

加载战略围城损坏/器械快照并检查对应场景变体；规则分配攻守路线与器械任务。乘员占槽需距离、阵营、存活、权限验证；移动/部署/装填/发射由状态机处理。撞击或投射器械触发合法伤害，门/墙破坏到阶段阈值切换模型并提交 MOV NavLink；塔就位/梯搭建成功才开放链接。槽位占用者失能即时释放，器械阻塞尝试回退/重新分配。胜负由突破/占领/击溃/撤退等规则判断，结束报告设备/城防差异。

## 7. 配置、异常与安全边界

配置器械乘员数、装填时长、耐久、射击范围、破坏阶段和链接；所有可用器械必须场景编译时检查乘员点与进攻/守备可达性。禁止打开未部署塔的链接或直接删除槽位导致伤亡丢失。

## 8. 表现及可观测性

显示器械健康、弹药、操控提示、城门/缺口、攻防目标和状态。

**性能与诊断：** 局部导航更新与器械物理预算；监控攻城通路利用、占槽失败、堵塞与设备状态。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SIEGE-01 | SGE-02 | 梯/塔/门/投射器械均存在 | 攻防并破坏 | 合法器械操作和动态导航可通行 |
| T-SIEGE-02 | NAV-01 | 城门破坏与同步延迟 | 查询 | 旧链接拒绝，更新后路径可用 |
| T-SIEGE-03 | SGE-03 | 进攻失败但城墙损坏 | 结算 | 保存损坏和器械状态，领地不自动易主 |
| T-SIEGE-04 | MIS-03 | 器械乘员点无可达路径 | 编译场景 | 拒绝内容并标记位置 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/mission/siege/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
