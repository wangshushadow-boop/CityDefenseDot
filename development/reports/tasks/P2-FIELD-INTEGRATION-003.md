# P2-FIELD-INTEGRATION-003 引擎野战适配

开发候选。开发者 engine_field 在隔离工作树 .worktrees/p2-engine-field 以 e1c7f95 为基线。INF-ENGINE 依照现有工程公共契约和 P2 整场装配约定实现。独立审查、QA、集成状态由主 Agent 记录。

## 改动

- game/infrastructure/engine/adapter.gd 为 scope 的独立 World3D 提供位姿分步提交、回滚、出生点净空、环境视线和 COM 扫掠。
- game/infrastructure/engine/field_bodies.gd 在 Jolt 中投影真人形与坐骑，校验完整名册并处理代际替换。当前候选经主线程强制刷新世界变换，在同一固定步内即可命中。撤销恢复原名册和位置。
- game/infrastructure/engine/queries.gd 的两种调用共用既有射线和连续球形碰撞。COM 命中携带实际注册的句柄和命中部位。盾具有独立碰撞体，静态环境的目标为 null。
- game/tests/p2/field_engine/run.gd 检查 COM 投射物、命中顺序、出生点、撤销与重试、同代阵营保护、代际及独立 scope。profile.gd 量取批量位姿投影所用时间并以真实 Jolt 命中验证末位单位。
- 脚底按世界米传入，LOS 眼高 1.55 米。人类胸高命中点约为脚底上 1.1 米，骑手另加 0.95 米。动态角色占用第 30 碰撞层。出生点检查角色胶囊、场景障碍和 6 米内的异队。出生区和导航可达性继续由 Mission 控制。这些数值为本阶段可调的本地默认值。

## 实际自测

Windows，Godot 4.7.2.stable.official.ed1daf0bf Standard，指定的 headless 控制台。各脚本使用固定位置，无随机源。以下入口实际运行的是 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe --headless --path game --log-file <工作树绝对日志路径> --script res://tests/<入口>`。日志均保存在此工作树的 out/engine-test。

| 入口 | 退出码 | 断言或标记 | 日志 |
|---|---:|---|---|
| p2/field_engine/run.gd | 0 | 70 检查，0 失败。弓箭对无墙目标造成 16 点伤害，有墙目标无伤且产生阻挡事件；受试对象在相同固定步内移动、回滚及重试后立即可被真实 Jolt 扫掠 | p2-field_engine.log |
| p1/engine/run.gd | 0 | T-INF-ENGINE-01、02、04 通过，headless 切片通过，50 次循环，0 失败 | p1-engine.log |
| p2/combat/run.gd | 0 | 原 COM 入口，30/144 Hz 重放摘要一致，实物理 44 批、46 次查询 | p2-combat.log |
| p2/rules/run.gd | 0 | 38 个断言，实际物理接触 1 次 | p2-rules.log |
| p2/mission/run.gd | 0 | 1038 个检查，0 失败。千名保留人员、两次补充波次通过 | p2-mission.log |
| p1/mission/run.gd | 0 | 50 次切换和固定重放通过 | p1-mission.log |
| p2/field_engine/profile.gd | 0 | 500/1000 个动态碰撞代理的末位真实命中，四组各记录 120 步 | field-profile.log |

位姿构造后计时，包括 stage 和 commit；每组预热 12 步。在此共享主机的一次运行中，500 体静止及移动时的 P95 分别为 2.184 与 3.419 毫秒，1000 体为 3.488 与 6.112 毫秒。这组数据只测适配器开销。首次开发自测的相对日志路径由 Godot 拒绝写入，已改为绝对路径并完整复跑。

T-TEST-01 至 04 的阶段级条件以及 AT-04、AT-05、8 GiB 设备和完整混合战斗性能仍由最终整场工作包实测。本次代码与报告均在任务白名单。没有修改公共 DTO、存档或网络格式。
