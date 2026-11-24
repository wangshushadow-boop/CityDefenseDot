# P1-PERSIST-CORE-001 存档核心

**CANDIDATE**。开发者 p1con，独立工作目录 `.worktrees/p1-persistence`，detached HEAD 基线 `a41de0689eabbf5793ceb3de4051c1321e0f07ca`。本报告对应 PERSIST SDD v0.1、GDD §18.1、已签核 ADR-012/013，关联 BAT-03、SAV-01/02/03。候选以未提交 diff 交付。

## 提交与恢复

`save_service.gd` 实现 `save_game(slot,snapshot,reason,expected_commit_id)`、`commit_critical(slot,snapshot,applied_result_id,expected_commit_id)`、`write_prebattle_checkpoint(slot,encounter_id,snapshot,expected_commit_id)`、`load_game(slot,installed_content)`、`recover(slot)` 和纯数据 `migrate(data,from,to)`。默认根目录为 `user://saves`。APP 可由装配根注入实例。可选 expected_commit_id 的空字符串表示调用方期望空槽，缺省按当前读到的版本竞争提交。

槽包含 manifest.json、world.bin、backup/。world.bin 的规范 JSON 同时包含完整业务快照和已应用结果的摘要、原回执 ID。每次成功写入都对实际 world.bin 字节校验 SHA-256。关键操作重发时先核对同一 ID 的原始请求，返回已持久化的 commit_id。同一 ID 对应不同内容时返回 Conflict，旧 marker 或业务 revision 拒绝。未使用可选的独立 transactions.bin。

同卷临时文件在写后重读校验。Windows 平台适配器获取按槽独占的文件句柄，重新核对主/备 marker 和选中快照的真实字节摘要，保存上一有效代，再替换 world.bin，最后发布 manifest.json。备份本身损坏时仍以完整主代为准；当前主代损坏时可从有效备份恢复，下一次保存继续保护该备份。未来结构版本和内容不匹配单独报错。明确支持的合成 v0 在内存副本中迁移，加载不会重写旧文件。

Godot 4.7.2 Windows 的 DirAccess.rename 会先删除已有目标。`atomic_windows.gd` 通过 Windows 自带 PowerShell 调用 .NET File.Replace 替换已有文件，首创使用同卷 File.Move。文件流在发布前 Flush(true)。传入脚本的序列化参数经 Base64 封装，存档路径没有进入命令表达式。适配代码封装于 GDScript 资源，PCK 运行仅依赖系统组件。[Godot Windows 实现](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/dir_access_windows.cpp#L288-L326)

## 实测

Windows、Godot 4.7.2 Standard `ed1daf0bf`，本机真实文件。表中 G 对应 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe`。运行时将 Godot 用户目录和日志放入临时目录。故障矩阵由父 Godot 实际启动子 Godot 进程，写入方在到达指定故障点后由测试回调终止其自身进程，新进程重新打开同一槽。

| 用例 | 命令或观察 | 退出 | 判定 |
|---|---|---:|---|
| T-PERSIST-02 | `G --headless --path game --script res://tests/p1/persistence/run.gd` | 0 | PASS。27 个子进程，错误 0。覆盖写前、实际半段 staging 文件、备份发布后、主 world 已替换但 marker 尚旧、marker 已切换而回执丢失。五次重开分别读旧、旧、旧、旧、新；再次重发及复开时奖励均恰好一次，回执 ID 稳定。另在真实双代槽逐字节改写现行 marker，验证缺少 checksum、损坏 commit_id 或非整数 schema_version 会恢复备份。未来 schema 和未知关键字段显式拒绝且保留原文件；另验证校验失败切换上代、备份上重试、Unicode 结果 ID、过期 revision 和 commit_id。两个真实独立进程同时持同一前置版本竞争，两轮分别观测 `["Unavailable","ok"]` 和 `["ok","Unavailable"]`，恢复所得快照恰属胜方。 |
| T-PERSIST-01 切片 | 同上 | 0 | PASS。多槽、三年等效分钟、十六进制 RNG 与仓库快照往返一致，槽间隔离及战前检查点。真实多年完整世界演进 NOT_RUN。 |
| T-PERSIST-03 切片 | 同上 | 0 | PASS。v0 合成旧头可迁移，原 marker 和世界文件字节不变。拒绝未知版本/字段、不匹配摘要、缺包，以及 bool/浮点/字符串/空值/负数版本。另从实际存档恢复锻造定义，用 DEF 注册表验证组件，再解析物品实例引用。已发行档和完整锻造玩法 NOT_RUN。 |
| T-PERSIST-04 存档切片 | `G --headless --path game --script res://tests/p1/persistence/stress.gd` | 0 | 50 次真实提交与新 Store 重新加载通过。提交和重开合计本次 P95 为 602 ms，最高 836 ms，测量时另一套故障矩阵并行执行。真实 Mission 切换 50 次、泄漏门禁及 AT-15 均 NOT_RUN。 |
| PCK 独立发布 | `python game/tests/p1/persistence/pack_smoke.py --godot G --path game` | 0 | PASS。从独立临时目录加载单个 PCK，三个游戏进程在含空格、中文及单引号的路径实测创建、关键保存/重发、重新读取。Python 仅用于组装测试包。 |

## 范围及交付

验证的是模拟写入中断和真实进程终止后的恢复。实机切断电源、强制磁盘写满、存储控制器缓存持久性及 Windows 以外平台均 NOT_RUN。Windows 以外的写适配返回明确的 Unavailable。正常路径会清理本次临时文件，硬终止留下的 .pending 目录不参与恢复或枚举有效提交。同步文件操作的耗时包含系统进程启动，调用者应在取到不可变安全点快照后把持久化交给后台执行。游戏主线程实际编排、完整域状态、物理掉电及跨平台验证仍由对应门禁验收。

开发中修复了脚本与 SceneTree 的 root 名称冲突、合成 v0 被 v1 快照保护误拒，以及浮点版本被 GDScript int 参数隐式截断，已知版本主索引缺必填字段曾误报未来版本，修复后新增主损坏与未来版本的真实写盘对照。期间动态表达式推断导致的编译错误已改为显式 bool。最终重新执行 27 子进程，全部按原判据通过。Git 路径核查为 `game/infrastructure/persistence/{save_service.gd,atomic_windows.gd}`、`game/tests/p1/persistence/{run.gd,worker.gd,stress.gd,pack_smoke.py}` 与本报告，共七个新增文件。独立 QA、审查、集成及阶段状态由主 Agent 记录。
