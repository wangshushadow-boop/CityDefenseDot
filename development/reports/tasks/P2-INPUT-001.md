# P2-INPUT-001 野战设备输入

状态为 CANDIDATE。开发者 p2formation 在 `.worktrees/p2-input` 工作树执行，分离 HEAD 为 `d5725c7b695ae5a1765af9590cb9c513b99884e5`，未提交。任务对应 INPUT、ACC-01、BAI-01、COM-05、NET-04、UX-01 及 T-INPUT-01 至 03。[输入 SDD](../../../docs/systems/game/presentation/input/README.md)

## 实现与接入

- Godot 节点通过未被 UI 消费的事件接收键鼠、手柄按钮和轴，在固定步生成冻结 v1 的 MoveIntent、LookIntent、AttackIntent、BlockIntent、EquipIntent、InteractionIntent 及 FormationOrder。绑定的角色句柄代际、控制修订、编队修订随各自请求提交，认证上下文由装配方持有。方向选择覆盖上、左、右和刺，攻击期间锁定所选方向。接入 COM 读端口后，同一固定步内的快速按放也能在合法阶段释放。[输入节点](../../../game/presentation/input/ports/field_input.gd)
- 输入支持战斗、指挥、地图与 UI 上下文，清理鼠标增量、持有状态和待发指令。支持移交角色、窗口失焦、GUI 获焦和断开手柄。手柄拔出会解除其摇杆和锁定操作，键盘上同时持有的移动继续生效。键鼠与手柄可分别改绑。灵敏度、反转 Y、死区、点击锁定格挡/攻击和绑定随本地档案保存。档案复用项目的规范 JSON 编解码，经同目录临时文件置换，不扩展存档与网络格式。Esc 和手柄菜单键保留替代入口。[本地设置](../../../game/presentation/input/field_profile.gd)
- 编队指挥支持全选、多选、按编号/手柄切换、阵型切换、移动/跟随/冲锋、委派和其他 FORM 已注册命令。调用方传入相机选取的毫米坐标、编队目标及被委派者。提交前保存选择和版本快照。FORM 对每个选中对象判权，实际回执和拒绝原因可送入界面。相同 tick 重复采样返回原回执，进程内恢复可带入已用订单序号。攻击武器槽由已确认角色读模提供。详细入口在[模块导航](../../../game/presentation/input/README.md)。

## 验证

Windows 本机使用 Godot 4.7.2 Standard。测试进程使用隔离的 APPDATA、LOCALAPPDATA 与临时日志，档案重开测试使用专属临时档案名。种子 241124 用于既有 P1/FORM 回归，输入测试使用固定事件序列。以下命令均在该工作树根目录执行。

```powershell
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --quit-after 600 --path game --script res://tests/p2/input/run.gd
& $godot --rendering-method gl_compatibility --resolution 480x300 --single-window --quit-after 600 --path game --script res://tests/p2/input/run.gd
& $godot --headless --quit-after 600 --path game --script res://tests/p2/combat/run.gd
& $godot --headless --quit-after 600 --path game --script res://tests/p2/formation/run.gd
python game/tests/p1/harness/suite.py --godot $godot --build P2-INPUT-001 --seed 241124
python -B ci/gates.py dependencies
python development/check_project.py
```

| 用例 | 开发者实测与边界 | 退出码 |
|---|---|---|
| T-INPUT-01 | 自动化通过。重绑物理键和手柄按键并重新创建节点，实际从文件恢复绑定和无障碍选项。用 `Input.parse_input_event` 经 Godot 分发已改绑的键，验证冲突、死区、反转、GUI 获焦与解除锁定状态。设备断开通过引擎信号注入，检测到的实体手柄为 0，人工热拔插 NOT_RUN。 | 0 |
| T-INPUT-02 | PASS。鼠标手势/按钮和手柄左右摇杆/扳机四向攻防生成相同的规范载荷。开始、持续、释放、格挡、取消格挡分别进入生产 COM 状态机。短按走 COM 状态读模，整轮只产生一次开始和一次释放。未做命中或本地伤害推断。 | 0 |
| T-INPUT-03 | PASS。玩家选中另一玩家编队提交 hold，经实际 FORM 认证回调被拒绝，编队订单保持原值。挂载的 Label 显示“你没有此项指挥权限”，在实际 Windows 窗口比较显示与隐藏帧的相同像素区域，验证文字确实绘制。多选混合权限同样被拒绝，合法目标、阵型、委派通过。远端 ENet 传输 NOT_RUN。 | 0 |
| 输入综合 | headless 379 个断言、Windows 480×300 窗口 380 个断言，均 0 失败。窗口为 RTX 3090、NVIDIA 591.86、OpenGL 3.3 Compatibility。 | 0 |
| 受影响回归 | P1 的 15 套测试全部通过。P2 COM 的固定步脚本与 30/144 Hz 重放通过，P2 FORM 的两档群体、实际 66,499 个可达端点通过。生产依赖检查问题数 0。 | 0 |

开发过程中，一次新加的 Godot 事件类型推导导致脚本编译错误，该轮即使进程退出 0 也记为失败。已指定 bool 类型并补上关键场景走到结尾的断言。快速点按测试第一次在 COM 恢复完成前取样，退出 1，现取完整权威恢复窗口并查状态。所有表中通过数据取自最终源码复跑。[可执行测试](../../../game/tests/p2/input/run.gd)

## 交接与待验证

变更仅限输入 README、`field_profile.gd`、`ports/field_input.gd`、`game/tests/p2/input/run.gd` 和本报告。最后一次实际比较采用生产输入节点的反馈 Label；完整桌面 HUD、真实手柄手感/热拔插、联网冗余和整场野战入口留待相应组装及验收。战斗结果与移动/交互执行由接收域决定，本任务只对上述具体已运行入口作出判定。独立审查、QA 和集成复测由主 Agent 记录。
