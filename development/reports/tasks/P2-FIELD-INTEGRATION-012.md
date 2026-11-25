# P2-FIELD-INTEGRATION-012 骑射近远景与持械

开发者 hud_dev，工作区 `.worktrees/p2-mounted-visual`，基线 `5b606542d09acdcd0305c25adb955f06d67a13da`，候选为未提交 diff。模块 VIS，需求 BAT-01，用例 T-VIS-01。本报告状态 CANDIDATE。[视觉规格](../../../docs/systems/game/presentation/visuals/README.md)

## 实现与依赖

[模型和附件](../../../game/presentation/visuals/field_model.gd) 载入原 general.glb 与正式 short_bow.tscn。骑射手的近战装备使用 GLB 自带的蒙皮戟，短弓的六段弓身和弦随 RightHand 移动。弩手保留导入模型的蒙皮弩和正式 sidearm.tscn。近远程装备互斥，骑射拉弓动作调整两条手臂，保留 COM 当前骑乘状态对应的下肢姿态。

[野战视图](../../../game/presentation/visuals/ports/field_visuals.gd) 读取正式兵种 role、COM 的 weapon_slot 和 mount_handle。槽 0 使用戟，槽 1 使用弓；有效、同代且存活的马匹决定乘骑。远景持弓有独立的上下马姿态网格，持戟与骑士共享同一原模型的预烘焙网格。由坐骑或槽位变化触发同一代理的换装和姿态刷新。释放 Mission scope 同时释放两种手持实例与远景批次。

变更限于上述两个 VIS 源文件、[新增用例](../../../game/tests/p2/mounted_visual/run.gd)和本报告。未写公共契约、内容资产、COM、Mission 或项目共享状态。开发工作树保留分配的基线。该基线的 011 首版尚无 sidearm.tscn，测试在忽略目录 `out/p2-mounted-visual-dev/game` 中叠加 011 候选 `264b1f138e9db7a3366965eeb7e35bf5a739bd13` 的内容定义、manifest、署名、短刀和原 loadouts 用例。集成需包含该修订。[BASE 定义](../../../game/content/base/field/field.json)

## 可复验命令及观测

下列命令从主仓库运行，`$project` 为上述测试快照或集成两份变更后的 `game` 项目。所有游戏测试均使用 Godot 4.7.2 Standard。输入样本的骑射兵种来自正式内容编译；使用 COM 的可骑乘 cavalry profile 配置 ranged=bow，由真实装备意图和 mount/dismount 产生视图中的槽位和挂接句柄。

```powershell
$project = 'out/p2-mounted-visual-dev/game'
$evidence = (Resolve-Path 'out/p2-mounted-visual-dev').Path
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $godot --path $project --headless --script res://tests/p2/mounted_visual/run.gd
& $godot --path $project --resolution 1600x900 --script res://tests/p2/mounted_visual/run.gd -- "--output=$evidence"
& $godot --path $project --headless --script res://tests/p2/visuals/run.gd
& $godot --path $project --headless --script res://tests/p2/field_assets/run.gd
& $godot --path $project --headless --script res://tests/p2/field_loadouts/run.gd
python "$project/tests/p2/field_assets/cold_import.py" --godot $godot
```

| 入口 | 实际结果 | 退出码 |
|---|---|---|
| mounted_visual 无窗口 | 91/91。检查四种组合、右手骨骼实际位置、七段短弓几何、近远程互斥、远景弓肢位置、同一骑射手远景上下马换装、持弓动作、兵员退场及 scope 卸载、步兵和骑士原武器、弩手正式短刀与弩。Godot 无窗口驱动无法读回 MultiMesh 实例矩阵，使用提交给批次的变换。 | 0 |
| mounted_visual Windows 图形窗口 | 95/95。RTX 3090，Vulkan Forward+，1600×900；实际读取 MultiMesh 实例变换。相同相机分别强制两档 LOD，额外保存四张截图，便于肉眼比较。 | 0 |
| 原 visuals、field_assets、field_loadouts | VIS_FUNCTIONAL 零失败。四个原始 GLB 均实际加载，三个人形各 22 骨、马 50 骨，验证真实动画、野战导航与卸载。内容编译摘要为 `3c3694f1c22a1d36b7ee99d6b04e47c6556a43db94dc89a7f2d16ff6a05eedad`。 | 各 0 |
| 原 field_assets/cold_import.py | 临时目录内从头导入，并执行 field_assets，两个子进程均成功。 | 0 |

窗口证据在主仓库 `out/p2-mounted-visual-dev/` 下，为 `mounted-near.png`、`mounted-far.png`、`mounted-action.png` 和 `mounted-action-far.png`。从左至右是马上持弓、马上持戟、步行持弓、步行持戟。最初窗口比较发现边缘单位超出取景，已调整测试相机并重拍。初次共用临时用户目录导入有一次 safe-save 错误，最终冷导入用独立目录复跑通过。

## 尚待验收

完整野战 BOOT 对兵种角色、COM 槽位和马匹投影的正常入口集成、目标硬件上的 500/1000 人长时性能及人工美术验收均未在本任务执行。独立审查、QA 与集成由主 Agent 记录。
