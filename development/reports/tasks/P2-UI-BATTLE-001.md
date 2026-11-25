# P2-UI-BATTLE-001 野战 HUD 开发报告

开发者 hud_dev，工作区 `.worktrees/p2-hud`，detached HEAD 基线 `46af5b1fcc4eb0d13b64ef146298f82074685806`，状态 CANDIDATE。需求为 ACC-01、UX-01、UX-02、UX-03。验收范围为 UI SDD 的 P2 野战部分。[任务规格](../../../docs/systems/game/presentation/ui/README.md)

## 交付与边界

- 控件按 Mission scope 与 revision 读取我方编队、可见目标、可用命令、RULES 状态和结果。部署前可多选编队、选区与阵型、预览并撤销部署草案。开战后可选编队、敌方目标或使用相机给出的落点，执行坚守、冲锋、移动、变阵及委派。授权变化和不可达目标会显示相应回执。
- 界面把用户意图连同读模版本发往装配方，不携带权限、队伍身份或战果。倒地选择、撤退二次确认和结束页依赖权威回读。F6 切入或释放焦点，手柄十字键上进入，方向键导航，A 确认，B 返回。可以保存中英文、字号、对比、字幕及坚守键改绑。设置与战斗数据分开保存。
- 交付五个文件。生产代码为 [HUD](../../../game/presentation/ui/ports/field_hud.gd)、[文本表](../../../game/presentation/ui/field_hud_text.gd)、[模块导航](../../../game/presentation/ui/README.md)。测试为 [交互入口](../../../game/tests/p2/ui/run.gd)，本报告为第五项。基线工作树的 `git status --short --untracked-files=all` 与 `git diff --check` 用于核对范围，未更改公共契约、其他模块或全局状态。

## 可复现测试

在上述工作树使用 PowerShell。为避免污染玩家设置，命令将 APPDATA 指向临时目录；测试使用进程专属配置并在结束时清理。

```powershell
$env:APPDATA = $env:TEMP
$engine = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path game --script res://tests/p2/ui/run.gd
& $engine --path game --resolution 1280x720 --rendering-method gl_compatibility --script res://tests/p2/ui/run.gd -- --snapshot
& $engine --path game --resolution 1920x1080 --script res://tests/p2/ui/run.gd -- --snapshot
& $engine --headless --path game --script res://tests/p2/input/run.gd
& $engine --headless --path game --script res://tests/p2/rules/run.gd
```

| 用例 | 实测、样本及证据 | 退出码 |
|---|---|---|
| T-UI-01 野战部分 | Godot Viewport 派发鼠标、键盘和合成手柄事件。覆盖多选、手柄导航和确认、Escape 与按钮取消、F6 去回焦点、倒地后观战或委派、本方撤退确认、离开结束页。 | 0 |
| T-UI-02 | 通过实际 INPUT、FORM 验证多个编队坚守、指定敌方冲锋、方阵、委派、不可达移动以及授权拒绝。两支编队的部署预览与重置经独立装配夹具接收，尚未接入整场入口。通过真实 RULES 的 stage/commit 验证兵力、主将状态、本方撤退和胜方；结果页兵员分类使用显式的槽位样本。错 scope 及低于已显示 revision 的读数均清屏。 | 0 |
| T-UI-03 / T-UI-04 野战部分 | headless 960×600 共 123 项检查。RTX 3090、Windows 1280×720 OpenGL Compatibility 和 1920×1080 Vulkan Forward+ 各 125 项检查，均为 0 失败。可见状态、控件边界、滚动、语言与字号、对比、字幕及重建恢复均有断言。坚守键通过真实 INPUT 改绑为 J，新输入实例从磁盘恢复。同尺寸窗口分别保存中文部署与英文大字截图。开发者查看了 720p 中英文截图。 | 0 |
| 依赖回归 | INPUT 原套件 379/379。RULES 原套件 38 项断言通过，包含一次物理接触。 | 0 |

临时截图位于 `%TEMP%/recollection-field-hud-{1280x720,1920x1080}-{deployment-zh,battle-en}.png`，可用带 `--snapshot` 的窗口命令重新生成。早期测试发现 headless 默认 64×64 窗口导致点击落在界外，以及引擎默认 UI 确认动作只绑定键盘。测试改为指定有效 headless 尺寸，HUD 在自身持焦时处理手柄导航，两项均已在上述最终版本复跑。

## 未运行及交接

实体手柄体验、真实热拔插、人工可读性验收、正式整场野战装配、野战端到端的部署落点及完整结果生成均为本开发任务 NOT_RUN。招募、交易与其他非野战流程未执行。GUI 测试中的血量、弹药和字幕来自明确的测试投影；背景为空，以便复验控件。真实性能与完整场景应以阶段集成证据为准。独立审查、QA、受控集成及最终阶段验收由主 Agent 记录。
