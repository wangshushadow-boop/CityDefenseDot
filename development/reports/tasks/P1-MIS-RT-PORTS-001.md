# P1-MIS-RT-PORTS-001 Mission 生命周期与端口

状态 CANDIDATE。基线 `3ef1cb6cb93d2e769f6bbdbaabfa379876b02996`，开发者 p1core，独立工作树 `.worktrees/p1-mission`。需求 BAT-01、BAT-02、BAT-05、MIS-02。实现文件位于 `game/mission/runtime/`，正式测试位于 `game/tests/p1/mission/run.gd`。

`runtime.gd` 实现已签核的 MissionPort，注入 CORE、引擎适配器和可选的结果构建端口。prepare 匹配场景与规则 ID，创建作用域并加载真实场景，失败逆序回收。固定步按阶段、稳定系统 ID 执行，校验输入形状及句柄。按预留区间分配人形，原子部署、容量上限、源槽终身去重、非兵力实体与回收递增 generation 均在运行时负责。结束操作先关闭 CORE 作业屏障，再向结果构建者传不可变终态与 outcome，校验返回的 MissionResult 和来源槽。无结果构建者时返回 Unavailable。dispose 回收真实场景租约及系统引用。

## 实测

Windows 运行 Godot Standard 4.7.2.stable.official.ed1daf0bf。由工作树根运行以下命令，各退出 0。客户端实跑 Windows 窗口、Vulkan 1.4.325、Forward+ 和 RTX 3090。headless 进程报告 display=headless。两边使用相同世界种子 1234567890abcdef，运行同一个生产 Mission 与模拟场景。测试独有的结果构建者只依据实际分配过的状态写入 alive/not_spawned。

```powershell
& 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://tests/p1/mission/run.gd
& 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe' --windowed --resolution 480x270 --path game --script res://tests/p1/mission/run.gd -- --client
```

| 用例 | 结论 |
|---|---|
| T-MIS-RT-03 | PASS。两个进程各 50 次实际任务切换，每场均确认真实 worker 已开始后销毁。退出屏障每次丢弃一个在途结果并释放一个真实场景，每轮请求、租约、scope 均归零，节点数最终回到 1。 |
| T-INF-ENGINE-03 | PASS。两个实际进程的生产 Mission 以相同固定输入和结果端口运行，终态与结果的 SHA-256 均为 `24427810fe1ace3d1cdfb22fbb42cdca7b98ec8eee7bc7a362dde96fd9677373`，输出 MISSION failures=0。 |
| T-MIS-RT-01/02/04 | 本阶段验证实际部署、重复来源拒绝、代际回收、零兵源及含预留槽的结果契约，完整野战胜负、多波增援、访问移动和交互玩法 NOT_RUN。 |

审查发现首个实现在不同 CORE 与同一引擎适配器复用 key 时会生成相同 MissionId。首轮修订使用两个服务的代际，复审发现同时重建两服务仍会重名。最终版将 mission_key 仅用作显示名称，每场由操作系统熵源发放新的 UUIDv4 实例标识，或由装配者明确注入已记录的权威实例 ID 进行回放。正式回归同时重建两个服务、复用同名任务，确认旧句柄被拒。双端对比显式使用同一权威记录。完整玩法、联网传输和战略结算归后续阶段。独立审查、QA 与集成提交由主 Agent 记录。
