# P1-INF-ENGINE-PORTS-001 引擎适配验证

状态 CANDIDATE。开发者 p1core 在隔离工作树 `.worktrees/p1-engine` 开发，基线 `93318670efd71234cade98bceb24c1ed45ad33d7`。对应 COM-02、NAV-01、NET-01。本次涉及适配器、物理与导航查询、正式基础模拟资源、引擎 SDD 导航、独立场景及测试。所有文件位于任务允许路径。

每个 scope 创建隔离 World3D。模拟场景和展示资源分别加载，headless 只装配模拟树。ResourceLoader 的线程请求在销毁时收取或丢弃，每次获取具有独立租约身份，scope 销毁回收所有场景与请求。适配器通过真实导航 map iteration 确认更改后公布拓扑版本，通过 Godot 空间查询发出连续射线和球形扫掠。

## 运行记录

Windows，Godot Standard 4.7.2.stable.official.ed1daf0bf。工作树根目录运行：

```powershell
& 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe' --headless --log-file "$env:TEMP/p1-engine-agent.log" --path game --script res://tests/p1/engine/run.gd
```

进程退出 0，`ENGINE failures=0`。固定场景无随机种子。

| 测试 | 实测结果 |
|---|---|
| T-INF-ENGINE-01 | PASS。两个导航岛初始断开；开门后拒绝旧路径和未同步的新版本；引擎同步后跨岛路径抵达目标。 |
| T-INF-ENGINE-02 | PASS。20 米射线穿过两道 40 毫米薄壁，时间比例 399000、699000 百万分。掠边球体按稳定顺序命中两目标，2 公里球扫回归也得到两条。早期额外探针在 200 米球扫中漏报，因引擎给出的粗粒度 unsafe fraction 越过薄壁。修订后分段连续扫掠并细化接触区间；超过 4096 段或无法解析接触时显式报告 Unavailable。 |
| T-INF-ENGINE-03 | 切片 PASS。headless 实跑相同模拟资源的导航、物理与生命周期并拒绝加载展示。正式客户端与 headless 的同 Mission 规则对比本任务 NOT_RUN，交由集成验证。 |
| T-INF-ENGINE-04 | PASS。50 次实际加载、异步请求、取消与销毁，回到零请求、零租约、零作用域，宿主节点数回到起点。每循环中位数 3,994 微秒、P95 4,067 微秒、最大 4,079 微秒。 |

性能数值来自本机固定测试场景。完整战斗、千人导航和真实网络不在本次测量中。主 Agent 负责候选提交、独立审查、QA 和阶段集成。

独立审查曾在仅客户端加载的表现资源中测到两个碰撞体污染权威查询。改为每个客户端 scope 按需使用独立 World3D，回归测试真实加载同一碰撞场景作表现资源，并在两个 profile 的权威窗口各做查询。

独立 QA 的初始重叠反例导致球体起点位于碰撞体内部时遗漏第一个接触。增加起点形状重叠查询，实测 fraction_ppm=0、后续远处接触仍可返回。
