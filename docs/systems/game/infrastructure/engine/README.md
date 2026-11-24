# INF-ENGINE — 引擎适配、物理、导航与资源端口

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/infrastructure/engine/` | 总体基线：[§19、§10.4、§11、§12.6、§20](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

实现引擎无关领域所需的导航/物理/渲染/资源/输入/音频/任务端口适配。Godot 4.x 为候选，版本/语言需 P0 压测冻结；核心领域不 import SceneTree、Node、RID 或引擎 SDK。

**协作边界：** CON/CORE 与各领域定义的 local ports；仅适配层依赖引擎 API。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

EngineContext、引擎句柄映射、资源租约、查询缓存和同步 revision；游戏权威状态仍由 World/Mission/COM/MOV 等拥有。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
ports_adapter / engine_context
navigation_adapter / dynamic_link_sync
physics_adapter / swept_collision / pose_bridge
resource_loader / scene_factory / lease_manager
render_adapter / animation_adapter / audio_adapter
headless_adapter / thread_guard
```

## 4. 数据模型与约束

`EngineLease{scope,resource_id,handle,ref_count}`；`PhysicsQuery{shape,from,to,mask,ignored_handles}`；`PhysicsHit{entity_handle,point,normal,region,fraction}`；`NavSyncReceipt{requested_revision,applied_revision,status}`。引擎对象不得出现在契约编码。

## 5. 公共接口

```text
load_scene(scene_def,cancel_token) -> Result<SceneLease>
query_sweep_batch(queries,snapshot_stamp) -> Hit[]
query_path_batch(requests,nav_revision) -> PathResult[]
apply_nav_links(changes) -> NavSyncReceipt
instantiate_visual(definition,scope) -> Result<VisualHandle>
release_scope(scope) -> BarrierReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

主/权威线程组织引擎操作；工作线程仅处理纯数据或经具体版本确认线程安全的接口。物理代理与权威位姿在固定 tick 相位同步，扫掠返回规范化命中候选；NavLink 更新等到引擎服务器同步后公布新 revision；资源异步加载带取消 scope，成功租约引用计数，场景失败逆序释放。headless 提供实际模拟碰撞/导航但不创建渲染音频。

## 7. 配置、异常与安全边界

P0 比较真实 500/1000 人混合战斗、骨骼、动态导航和 headless；未经 profiler 不迁移 C++。不承诺跨平台物理位级确定。引擎 API 升级须重新验证线程安全及同步语义；禁止 worker 直接改活动场景树。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 批量跨引擎调用；监控物理/路径查询 P95、引擎同步耗时、资源和句柄计数。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-INF-ENGINE-01 | NAV-01 | 请求开门后引擎尚未同步 | 查询 | 旧 nav_revision 明确，不能返回错误路径 |
| T-INF-ENGINE-02 | COM-02 | 高速弹体连续扫掠 | 碰撞适配 | 返回稳定候选，不漏穿越 |
| T-INF-ENGINE-03 | NET-01 | headless 环境 | 运行同 Mission | 同规则，不依赖渲染 |
| T-INF-ENGINE-04 | §19.4 | 50 次任务加载/取消/销毁 | 循环 | 租约释放，记录真实性能 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/infrastructure/engine/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
