# P2-VIS-BATTLE-001 野战表现

开发候选。任务基线 `6e399f2dbc754a494424c7d544d911fcda8e3775`，工作树 `.worktrees/p2-visuals`，开发角色 battle。变更位于 VIS、专属测试目录和本报告。正式战场组合根、AI 和美术资产由其所有者集成。需求为 VIS-01、COM-05、BAI-06，验收索引为 T-VIS-01/02/03。

## 入口与画面

`res://presentation/visuals/ports/field_visuals.gd` 是可装配的 Node3D。本域消费已提交的 Mission 读模型。组合根添加节点后依次调用 `open_field(scope_id)`、`apply_snapshot({scope_id,tick,actors,projectiles})`、`consume_view_events(scope_id,tick,events)`，以 `render_interpolated(alpha,camera_position,near_radius)` 绘制。角色用 Mission + index/generation 标识，位置和朝向来自移动视图，动作、武器槽和骑乘关系来自战斗视图。`release_scope` 释放画面与资源，渲染端没有写入伤害的端口。

近景使用临时 GLB 的独立骨架、步态与武器蒙皮，叠加方向动作、格挡、硬直和骑姿。骑手跟随有效世代的坐骑，按马匹 Torso2 骨与人形髋部的间距贴合。远景以同一套网格、骨权重和动画烘焙不同步态、方向、上下马及换装姿态，再由 MultiMesh 批绘。步兵使用矛盾、弩兵配置远近武器、骑兵持长兵器。战场含地表、山林和双方集结旗。飞行器取权威投影，确认事件有去重和限额，受击与尸体视觉有有效期。本任务消费 BASE 的三个 Polyfork 角色及 Quaternius 坐骑；模型文件及授权归档属于 P2-VIS-BATTLE-002。

实机抽查千人广角与近景 PNG。首版近景缺少顶点色，图形检查发现肤色、盔甲和武器发白。补上导入材质的顶点色和色彩空间设置，远景同步校色，再跑全部六轮；测试已断言近景材质状态。已确认最终版本能辨识阵营、骑手、坐骑、武器与在途飞行器。[广角截图](../../../game/tests/p2/visuals/evidence/validated-1000/field.png) · [近景截图](../../../game/tests/p2/visuals/evidence/validated-1000/field-close.png)

## 实验与复跑

实测在 OS 临时项目中复制本任务的 game 目录，并补入同一 BASE 候选工作树的 `content/base/field` 资源。临时 APPDATA 和 LOCALAPPDATA 隔离。以下为相同入口；`$project` 为包含四件模型的 game 目录，`$godot` 与 `$python` 取 P0-ENV 已记录程序。测试共用的 BASE 文件由编辑器真实导入。性能 runner 拒绝覆写已有输出目录。

```powershell
& $godot --headless --path $project --editor --import
& $godot --headless --path $project --script res://tests/p2/visuals/run.gd
& $python game/tests/p2/visuals/benchmark.py --project $project --godot $godot --count 500 --out out/vis-500
& $python game/tests/p2/visuals/benchmark.py --project $project --godot $godot --count 1000 --out out/vis-1000
```

| 用例 | 实际结果 |
|---|---|
| T-VIS-01 | 功能入口退出 0。读取导入的骨架与武器，校验肩部四个有区别的活动窗旋转、上马贴合/下马、弩切换近战槽、命中去重、预测事件过滤、超时回收。 |
| T-VIS-02 | 同一真实 Melee 权威回放对四个方向分别运行近、远景。近景每个 tick 调四次渲染，远景每两 tick 渲染一次。逐 tick 比较动作、HP、命中记录；每次真实蓄力均只结算一次，对手从 100 到 86，视图输入保持原值。功能入口汇总 `VIS_FUNCTIONAL failures=0`，退出 0。 |
| T-VIS-03 视觉子项 | 锁定种子与镜头的两档均完成三轮 GPU 采样，两个 runner、六个进程均退出 0。逐轮验收画面时延、蒙皮数、批绘数、显存、视锥人数、投射物和尸体。性能驱动产生固定移动/动作/事件投影。完整真实战斗与 AI、输入、HUD、音频的合场测量由 FIELD-INTEGRATION 负责，本用例完整判据待该报告收口。 |

首轮开发验证遇到未隔离 editor 配置路径与一处 GDScript 变量类型推断错误，已修正后冷导入并复测。在贴图修复前的 GPU 记录单独保留；变更画面后的最终样本可按摘要中的未压缩 SHA-256 复核。[首版 500](../../../game/tests/p2/visuals/evidence/500/summary.json) · [首版 1000](../../../game/tests/p2/visuals/evidence/1000/summary.json) · [最终 500](../../../game/tests/p2/visuals/evidence/validated-500/summary.json) · [最终 1000](../../../game/tests/p2/visuals/evidence/validated-1000/summary.json)

## 视觉域 GPU 和 CPU 结果

Godot 4.7.2 Standard，RTX 3090 24 GiB，驱动 591.86，Ultra 9 285K，Windows 26H2。Forward+ Vulkan，1920×1080，关闭 VSync，2× MSAA。固定种子 241124，每档步/弓/骑 50/30/20%，另加 100/200 匹马。每轮预热 120 个 60 Hz tick，采 360 tick。模拟和插值均使用同一生产 VIS 入口。远近切换距离在压力轨迹设为 53 m，同时最多 36 个近景独立骨架，其余 564/1164 个使用动作姿态批绘。游戏近景默认半径 22 m。末帧两档全部 600/1200 个角色和坐骑中心位于视锥内。

| 档/轮 | 平均 FPS | 1% low FPS | 帧 P50/P95/P99/最差 ms | 投影生成及提交 tick P95 ms | viewport CPU/GPU P95 ms | 显存 MiB |
|---|---:|---:|---|---:|---|---:|
| 500/1 | 294.99 | 141.27 | 2.67 / 6.16 / 6.60 / 7.96 | 3.69 | 0.62 / 1.16 | 221.75 |
| 500/2 | 305.02 | 153.72 | 2.60 / 5.96 / 6.24 / 7.09 | 3.54 | 0.57 / 1.15 | 221.75 |
| 500/3 | 291.07 | 141.34 | 2.70 / 6.23 / 6.75 / 7.72 | 3.77 | 0.66 / 1.19 | 221.75 |
| 1000/1 | 107.73 | 59.47 | 10.70 / 14.37 / 16.37 / 17.79 | 8.63 | 0.98 / 4.14 | 221.62 |
| 1000/2 | 133.04 | 70.28 | 6.79 / 12.24 / 13.85 / 15.00 | 7.84 | 0.82 / 2.33 | 221.62 |
| 1000/3 | 114.68 | 64.46 | 10.33 / 12.95 / 14.94 / 15.97 | 7.84 | 0.89 / 4.18 | 221.62 |

显存取 `RenderingServer.RENDERING_INFO_VIDEO_MEM_USED`；最大 draw calls 分别为 1234/1246。样本包括 6 秒模拟时间对应的逐帧墙钟间隔、两类 viewport 耗时及固定步墙钟进度。两档均无持续积压。8 GiB 设备、正式发行美术、完整战场 CPU 耗时、玩家手感和 AT-04 均未由本任务验收。

独立审查复现 a91b7fc 在 tick 1 接收 tick 10 倒地事件时提前显示尸体。修正顺序为先应用已提交快照，再消费对应事件。超前事件返回可重试的 Unavailable，重送仍按事件编号去重。
