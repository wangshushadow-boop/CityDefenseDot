# P1-BOOT-001 启动与装配

**CANDIDATE**。开发者 p1con，隔离工作目录 `.worktrees/p1-bootstrap`，detached HEAD 基线 `7bff1a63fd5e6aa35df5ca40a80b0bf452282205`。依据 BOOT SDD v0.1、GDD §18.2、§19.1、§20、ADR-011/012/013，关联 NET-01。候选以工作区 diff 交付。

## 启动入口

同一主场景 `res://bootstrap/main.tscn` 按实际显示后端选择 client 或 headless，也可用 `-- --profile=tool` 只编译数据。默认从 `res://infrastructure/content/base` 的 manifest、definitions、场景资源生成 DEF 注册表和 ContentHash；`--content-path=<包目录>` 可重复传入，按内容编译器的依赖顺序解析。启动配置只读取命名白名单，命令行优先于环境。基础规则和包配置先由 INF-CONTENT 合并，之后应用合法世界配置和单人玩家配置，记录来源；headless 拒绝玩家覆盖。

`composition_root.gd` 根据 `module_graph.gd` 校验的依赖顺序创建 telemetry、compiler、内容快照、CORE、引擎、存储和 Session，工厂只收到自己的依赖。环路、缺依赖、重复注册均具有明确诊断，构造错误按逆序释放已建模块。清理失败时保留栈供重试，半初始化或正在关闭的根不对外提供会话服务。生产根注入真实 CAMP、Mission、PERSIST 及已编译定义；训练入口按实际内容选择训练场和规则，实例化真实模拟场景。BOOT 不持有战役或战场真值。

普通桌面提供新建沙盒、读取、保存、进入/结束练兵及关闭会话，操作都进入真实 Session。普通 headless 直接建立多人模式的权威 Mission，以 30 Hz 固定步持续运行；此入口提供 P1 运行时，完整联网传输与赛局留在 P6。工具 profile 不创建引擎或 Session。 `-- --p1-smoke` 为两个运行后端恢复相同演练标识、源数据和三个真实固定步，输出完整 Mission 固定步视图的规范 SHA-256。

## 运行证据

Windows，Godot 4.7.2 Standard `ed1daf0bf`。G 对应 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe`。所有测试直接使用工程入口或指定测试脚本。桌面按钮测试另用临时 Windows 用户数据目录。

| 测试 | 命令 | 退出 | 实际结果 |
|---|---|---:|---|
| T-BOOT-01 | `G --headless --path game --script res://tests/p1/bootstrap/run.gd` | 0 | PASS。a→b→a 拒绝、工厂调用数为零、未构造 Session；重复 ID Conflict、缺依赖 Unavailable。 |
| T-BOOT-02 | 同上 | 0 | PASS。真实 headless 后端加载内容、创建 Session、准备训练场及推进 Mission，未加载桌面脚本，无 Control、音频节点或渲染设备，关停后模拟场景已释放。 |
| T-BOOT-03 | 同上 | 0 | PASS。磁盘坏 manifest、真实包缺必需 battle_limit 两种情形均拒绝并报告 content，逆序释放所有已建服务。 |
| BOOT-BOUNDARIES | 同上 | 0 | PASS。Session 已构造后下游工厂失败且第一次清理失败，仍不能获取 Session 或执行业务，第二次 shutdown 释放成功。另覆盖错误 config_sources 类型、环境白名单、CLI 优先级、服务器配置及 tool profile。输出 `BOOT_CHECKS errors=0`。 |
| 双 profile 正式 smoke | `G --headless --path game -- --p1-smoke` 和 `G --path game -- --p1-smoke` | 均 0 | PASS。client 实际为 Windows / Vulkan 1.4.325 / Forward+ / RTX 3090 并已加载桌面，headless 未加载桌面；协议 1，均走到 Mission tick 3，七个构造服务逆序释放。 |
| 普通桌面操作 | `G --path game --script res://tests/p1/bootstrap/desktop.gd` | 0 | PASS。脚本在真实 Windows 窗口中操作生产按钮，验证创建并保存新 commit、关闭后读取、进入实际场景、退出释放、战役存档不变。 `BOOT_DESKTOP_BUTTONS errors=0`。 |
| 普通专服持续运行 | `G --headless --path game --script res://tests/p1/bootstrap/server.gd` | 0 | PASS。不带 smoke 标志，从正式主场景启动，实际多人模式 Mission 在九个物理帧观察窗内推进至 tick 8，`hz=30`。 |

两个正式进程均输出 ContentHash `fe76080c6789c8173d3b9010b8ebcb41b0757b806f443b827c4417af5b65a579`，完整演练视图 SHA-256 均为 `69ed8f14a584a71be123ee70a96772d022eda35da2a6f001aef7efede9e94029`。headless 主场景不会加载桌面资源。测试中的三个固定步是 P1 运行时证据，不代表已有战斗玩法或 P6 专服协议。

## 范围与交付

现场修复了部分清理失败时可取到 Session、配置来源类型错误触发脚本异常、真实内容缺必需数值延迟到运行时报错三项问题。最初缺配置测试使用了 Godot 的通用 JSON 读写，改变整数词法；改为用生产规范编解码器仅删除待测字段后，同一判据实跑通过。十个新增文件由六个 BOOT 源文件/场景、三个测试和本报告组成，未改共享配置、其他业务模块及全局状态。AT-15 长周期、真实公网/专服认证、完整游戏表现与其他平台均不在该任务自测范围，独立复核及阶段验收由主线程汇总。
