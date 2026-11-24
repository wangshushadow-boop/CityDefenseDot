# CAM — 相机、视角、选取与观战

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/presentation/camera/` | 总体基线：[§11.2、§15.2、§16.3](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

提供战略地图旋转缩放、第三/第一人称、骑乘、部署/指挥、观察和多人许可观战。负责相机碰撞与拾取射线，不拥有单位权威位姿、敌方可见性或伤害。

**协作边界：** CON、INPUT、INF-ENGINE 只读碰撞/选取、MIS-RT/WORLD/NET 许可视图。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

CameraState/Mode/Target/LocalSettings 属本地表现；观战目标由 RULES/NET 授权。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
camera_controller / mode_stack
campaign_orbit / third_person / first_person / mounted
deployment_camera / spectator / collision_arm
pick_ray / accessibility_motion
```

## 4. 数据模型与约束

`CameraMode=Map|ThirdPerson|FirstPerson|Mounted|Deployment|Spectator`；`CameraState{mode,target_ref,yaw,pitch,distance,fov,shake}`；`PickResult{position,visible_entity?,valid}`。视图目标必须匹配当前 scope。

## 5. 公共接口

```text
SetCameraMode(mode,target,permission) -> Result<Unit>
update_camera(frame_dt,pose_view,input) -> CameraPose
pick(screen_pos,visibility_context) -> PickResult
switch_spectator_target(target) -> Result<Unit>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

根据模式获取插值位姿和本地 look，应用角度/缩放约束，做相机臂扫掠避免穿墙，平滑过渡。第一/三人称及骑乘差异由配置；指挥选取射线转换为候选目标，合法可达仍由 FORM/MOV 重验。角色击倒后根据规则切换观战/委派；多人观战只读允许视角。地图缩放影响图标聚合但不改变世界时间或可见情报。

## 7. 配置、异常与安全边界

配置 FOV、碰撞半径、灵敏度、晃动、骑乘限制、观战权限；实体销毁切安全目标，拒绝跨 Mission 句柄。镜头穿模修正不传送权威角色。

## 8. 表现及可观测性

视角切换、观战目标、缩放/指挥反馈。

**性能与诊断：** 仅本地必要相机查询；记录相机碰撞、选取失败和帧时。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-CAM-01 | UX-02 | 玩家在城墙和骑乘状态切视角 | 移动相机 | 无长期穿模，指挥目标正确 |
| T-CAM-02 | ACC-01 | 关闭晃动、修改 FOV | 切场重启 | 设置有效 |
| T-CAM-03 | NET-04 | 观战者请求未授权敌方视角 | 切换 | 拒绝并保持合法视图 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/presentation/camera/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
