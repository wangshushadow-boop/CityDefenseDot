# P2-FIELD-INTEGRATION-018 批量球扫实验

开发候选。INF-ENGINE 开发者 engine_field，独立工作树 .worktrees/p2-sweep-culling，基线 84c2e042cbe61d3b992c6398a5689958310f11da。实际代码仅修改 game/infrastructure/engine/queries.gd。测试入口位于 game/tests/p2/field_sweep_batch/。工作树 out/sweep/ 保留实际 Godot 日志。

## 几何反例与实现

实测中，同一步内用 Jolt BoxShape 包含 32 个水平球扫，在单面三角形的背向一侧查询可返回空。单条球位于正面时仍会命中，两种绕序各复现一次。该实验版本退出 1，已移除。留下的薄墙夹具覆盖两种绕序和两侧查询。

采用既有的 Jolt 起点重叠检测、精确球扫和多碰撞体枚举。在一次 sweep 调用中复用最多八种半径的 SphereShape3D 和查询对象，每次覆盖运动、变换、掩码与排除项。超过容量的其他半径正常使用独立形体。缓存随调用结束释放；各步继续读取当时的实际物理世界。三个整数坐标直接校验，消除逐分量回调开销。移动和战斗模块的代码与参数保持原有行为。

## 对照运行

使用指定 Godot_v4.7.2-stable_win64_console.exe（4.7.2.stable.official.ed1daf0bf），Windows 无头 Jolt，固定几何和编队，过程无随机采样。用 git archive 导出基线 game，再复制同一份测试脚本。对两份 game 使用相同启动参数，依次执行基线、候选、候选、基线、基线、候选。每次进程的两个入口均退出 0。

- 几何入口为 `Godot --headless --path <game> --script res://tests/p2/field_sweep_batch/run.gd`。在同一空间对照逐条和批量结果，包括返回顺序、点、法线、命中比例和错误。覆盖已抬高和贴地探针、斜面、桥面、薄门移动及撤销、隔离层、起点重叠、异构查询和单面三角形。最终两份 game 均为 36 检查、0 失败，完整回传摘要均为 a97c34e6d363a9f08ecf926022de0cf846978955bdf99c88f3fad077895899f4。
- MOV 入口为 `Godot --headless --path <game> --script res://tests/p2/field_sweep_batch/profile.gd`。正式 river_plain 载入真实导航与 Jolt 地面；20% 骑乘、全部兵员提交 MoveIntent。200 个固定步，最后 60 步计量 stage_step。500/1000 人分别完成 84,833/138,362 次球扫，500/1000 次路径查询，所有人实际移动。两组在所有运行的逐步位置、速度 SHA-256 分别为 f1466c3e5062ff83792978dcca3cf2b72543c05f88a2a71062e44edc570cfa03 与 c51273d588fe771cc378851598eb70a82913dc2beeefe9d716336429b3ef7ca2。

| 固定工作量 | 基线三轮 P95 (ms) | 候选三轮 P95 (ms) |
|---|---|---|
| 16 条水平球扫，实际地面 | 0.152 / 0.108 / 0.108 | 0.092 / 0.083 / 0.118 |
| 500 条水平球扫，实际地面 | 3.495 / 3.533 / 3.413 | 2.698 / 2.767 / 3.202 |
| 1000 条水平球扫，实际地面 | 6.858 / 6.775 / 7.123 | 5.388 / 5.431 / 5.253 |
| 1000 条水平球扫、59 个真实命中 | 7.419 / 7.268 / 7.503 | 5.892 / 6.080 / 6.090 |
| 500 人 MOV.stage_step | 8.607 / 8.563 / 8.362 | 9.731 / 7.505 / 7.559 |
| 1000 人 MOV.stage_step | 21.214 / 18.415 / 20.996 | 17.258 / 16.285 / 17.475 |

首轮 500 人 MOV 的候选 P95 高于基线。三轮中位耗时均下降，1000 人候选的三轮中仍有两轮 MOV 单模块 P95 超过 16.667 ms。共享主机上的该切片不能验证整场帧率或完整固定步门槛。原日志文件以 1-base、2-candidate、3-candidate、4-base、5-base、6-candidate 开头，后缀为 -run.log 或 -profile.log；最终几何复核另见 final-base.log 与 p2-field_sweep_batch.log。

## 回归及未测

同一候选上 p1/engine（50 次循环）、p2/field_engine（70 项）、p2/movement（T-MOV-01–04）和 p2/combat（真实物理 44 批/46 查询）均退出 0。初次 MOV 自测在导航引擎准备好提供路径前启动，无人移动，退出 1。已改为等待一条真实、可达且含两个以上点的路径，再运行全部 A/B 测量。git diff --check 退出 0。整场 AT-04/05、正式 GPU、8 GiB 设备和独立审查由阶段集成任务记录。
