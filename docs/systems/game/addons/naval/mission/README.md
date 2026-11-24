# NAVAL-M — 海战扩展：船舶运动、接舷、战斗 AI

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/addons/naval/mission/（新增建议，ADR-010 评审）` | 总体基线：[§24.2–24.3、§12、§19，MOD-06](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

EXT。组合现有 Agent/Combat/Formation/Mission 与 ShipRuntime、SeaEnvironment、NavalMovement、Boarding、ShipDamage。船舶为可运动局部参考系，船员共享原动作战斗系统；海战策略作为现有三级 AI 注册实现。

**协作边界：** NAVAL-C/CON/DEF、MIS-RT/COM/FORM/MOV/BAI/RULES/RESULTS 扩展端口、INF-ENGINE。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

ShipRuntime、船体部件状态、甲板局部运动参考系、船员岗位、接舷连接及海上环境临时；人形 Agent 源槽仍由 RESULTS 追踪。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
ship_runtime / sea_environment / ship_damage
naval_movement / propulsion / collision / buoyancy
boarding / deck_nav / local_frame_transform
ai/tactical / ai/ship_formation / ai/crew
naval_rule / naval_result_extension
```

## 4. 数据模型与约束

`ShipRuntime{instance_id,pose,velocity,heading,hull_hp,part_damage,crew_slots,status}`；`DeckPose{ship_id,local_pos,local_rot}`；`BoardingLink{ship_a,ship_b,anchor_a,anchor_b,enabled,revision}`；`ShipStatus=Navigating|Approaching|Contact|Moored|Boarding|Disabled|Sinking|Withdrawn`。船员世界位姿由船世界变换乘局部姿态，不另存第二真值。

## 5. 公共接口

```text
step_naval_motion(tick,ship_intents,environment) -> ShipDelta
project_deck_position(local_pose,ship_pose) -> WorldPose
TryBoardingLink(ships,conditions) -> Receipt
AssignCrewStation / OperateShipDevice(...) -> Receipt
apply_ship_damage(candidate) -> ShipDamageDelta
build_naval_result_extension() -> NavalResultExtension
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

权威步长先更新海况、船舶推进/转向/简化浮力和碰撞，再更新船员参考系与甲板局部寻路，最后进行射击和接舷动作；世界射线使用变换后位姿。跨船 link 仅在船距、相对速度、朝向和连接条件成立时启用，断开时进行合法掉落/回退/水中状态处理。船体/部件损伤、沉没、投降各有状态机；沉没不能直接删除乘员源槽。L1 舰队目标，L2 舰船路线/队形/岗位，L3 船员操作与接战；玩家可亲自操船或委派。结果扩展与陆战统一提交。

## 7. 配置、异常与安全边界

配置简化风浪、浮力、推进、甲板导航、接舷阈值、救援/撤离与沉没；不得承诺完整流体仿真。海上局部坐标和动态链接需独立压测；扩展禁用不改变陆战行为。

## 8. 表现及可观测性

舰船控制、船况/部件、航向、船员命令、接舷目标、海战结果。

**性能与诊断：** 额外测移动参考系、船舶碰撞、甲板路径和大量船员；独立海战性能基线。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-NAVAL-M-01 | NAVAL-03 | 多船风浪、碰撞、损伤和火力 | 操船接舷 | 状态机、船体/部件与动作正确 |
| T-NAVAL-M-02 | NAVAL-04 | 船舶运动中连通/断开接舷 | 船员移动、沉没 | 局部路径与跨船状态合法，源槽不丢 |
| T-NAVAL-M-03 | NAVAL-05 | 船员、船体和货物有不同结果 | 生成并提交扩展结果 | 来源完整、幂等 |
| T-NAVAL-M-04 | NAVAL-07 | 海战模块未启用 | 启动野战 | 原陆战规则和存档保持兼容 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/addons/naval/mission/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。
