# INPUT — 输入设备、控制映射与玩家命令

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/presentation/input/` | 总体基线：[§1.4、§11.2、§12.2、§15、§16.2](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

键鼠、手柄和可访问性映射转换为标准移动、视角、攻击、格挡、装备、交互与编队命令；场景/界面上下文切换和设备焦点处理。输入不直接改权威姿态、伤害或编队状态。

**协作边界：** CON、APP/MP 命令端口、COM/FORM 控制上下文只读、UI/CAMERA。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

设备状态、InputProfile、按键绑定、输入采样序号和本地预测缓冲归 INPUT；控制权由 RULES/FORM/NET 决定。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
device_adapter / action_map / rebinding
input_context / focus_router / deadzone
character_intent_builder / direction_selector
formation_order_builder / sequence_buffer
accessibility_input
```

## 4. 数据模型与约束

`InputBinding{action,device,key_or_axis,modifiers,context}`；`InputFrame{client_sequence,client_tick,move_axes,look_delta,action_edges,held_actions}`；`ControlContext{mission_id,controlled_agent?,formation_permissions,mode,ui_focus}`。动作边沿与持续输入区分。

## 5. 公共接口

```text
sample_devices() -> InputFrame
translate(frame,context) -> IntentSet | Commands
rebind(profile,action,binding) -> Result<Unit>
build_order(selection,target,order_type) -> FormationOrder
flush_on_context_change(context) -> Unit
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

设备采样→死区/灵敏度/反转→按 UI/地图/战斗/指挥上下文过滤→转换为规范意图（方向攻击四向、蓄力释放、格挡、弓弩装填、骑乘、切武器）→按序提交。UI 获焦、失焦、设备断开时清除粘滞输入；编队选择和位置预览最终生成 FormationOrder。多人输入按 tick/sequence 去重、发送受限冗余；服务器重验权限和动作状态。

## 7. 配置、异常与安全边界

绑定冲突提示；核心退出/菜单保留替代操作。无障碍选项仅改变合法输入映射，不提高多人权威能力。屏幕坐标和世界目标由 CAMERA/查询适配转换；服务器不信任客户端命中。

## 8. 表现及可观测性

绑定编辑、手柄图标、方向反馈、指挥快捷键和冲突提示。

**性能与诊断：** 固定输入采样和去抖；记录输入到提交延迟、序列缺失、上下文冲突。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-INPUT-01 | ACC-01 / UX-01 | 键鼠与手柄重映射、断开设备 | 操作并切换上下文 | 无卡键，设置持久化 |
| T-INPUT-02 | COM-05 | 相同方向动作来自不同设备 | 转换 | 规范意图一致 |
| T-INPUT-03 | NET-04 / BAI-01 | 试图选择无权限单位 | 发送订单 | 权威拒绝且 UI 有反馈 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/presentation/input/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
