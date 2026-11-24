# P2-FORM-002 编队指挥与执行

状态为 CANDIDATE。开发者 p2formation 在隔离工作树 `.worktrees/p2-formation2`、分离 HEAD `cdfe8eb6d507ef680c1d52bd28badb7ff5453b3b` 上完成候选，未创建提交。任务对应 FORM、BAI-01、BAI-02、BAI-05、NET-04 和 T-FORM-01 至 04。[模块 SDD](../../../docs/systems/game/mission/formation/README.md)

## 候选内容

- 每场 Mission 创建一个编队门面。部署、伤亡和增援只更新本域拥有的成员表和代际索引。成员读取带版本，分组、合并和指定源队调拨在校验所有来源后一起更新。编队编号在当前 Mission 内不可重用。跨模块通过 `member_formation(handle)` 读取逆向索引。[编队入口](../../../game/mission/formation/ports/field_formation.gd)
- 接入方传受信上下文和控制版本，玩家及受托 AI 都走 v1 `FormationOrder`。先验证 Mission、身份和全部授权，再处理重试、载荷冲突、序列和执行 tick。新订单在下一个固定步生效，允许同一版本的整数组或按编队传进程内版本映射。撤销委派使待执行、排队、执行中及重放的旧授权失效。同 tick 玩家与 AI 抵触，AI 的订单查询返回 `Replaced/player_priority`。每个编队可读取当前订单、队列和原因。
- 野战注册了位置、跟随、面向方向/敌人、保持、推进、撤退、指定队冲锋，以及七种阵型、开停火、使用远程武器、骑乘/下马、保持距离和自由攻击。组织类支持分配、分组、合并、委派和任命队长。调用方的选择集对应 `formation_ids`。推进默认排队，移动/冲锋等默认替换移动，姿态/约束与组织操作立即更新，移动到点默认由执行者以 `arrived` 完成。取消会对撤掉的活动与排队订单保留原因。以上默认策略由类型注册，沿用冻结的封套，没有新增顶层字段或必填排队/超时字段。[类型注册](../../../game/mission/formation/order_rules.gd)
- 实际队形使用 P2-FORM-001 槽位实现。调用方通过批处理注入地形查询；道路、目标、溃散、槽位无法投影均向执行者和读模提供原因。编队约束由后续 MOV、COM、AI 和显示层读取。[源码导航](../../../game/mission/formation/README.md)

## 自测

Windows，Godot 4.7.2 Standard，种子 241124。Godot 的 APPDATA、LOCALAPPDATA 和日志指向临时目录。命令在任务工作树根目录运行。

```powershell
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --quit-after 420 --path game --script res://tests/p2/formation/run.gd
python game/tests/p1/harness/suite.py --godot $godot --build P2-FORM-002 --seed 241124
python -B ci/gates.py dependencies
python development/check_project.py
python docs/architecture/check_mirror.py
```

| 用例与条件 | 开发者实测 | 退出码 |
|---|---|---|
| T-FORM-01 同 tick 玩家与委派 AI 冲突 | PASS。两种抵达顺序均由玩家取得活动订单，AI 收到具体取代原因；跨 tick 已受理的玩家订单也有保护。 | 0 |
| T-FORM-02 七种队形、真实可达地面/一米窄道、伤亡与重组 | PASS。500 人通过权威订单驱动七种队形、窄道/展开及逐种减员。500 和 1000 人的槽位回归逐个验证成员、唯一目标与种子重放，合计成功投影 66,499 个槽位端点。最后一次几何回归两轮分别耗时 249,977 和 546,676 µs，含多次重建、引擎查询及断言。 | 0 |
| T-FORM-03 不可达、溃散、目标消失与道路失效 | READ-MODEL PASS。真实导航不可达订单为 Failed，活动订单因溃散或狭道失败时有原因。HUD 屏幕呈现 NOT_RUN，本域不能独立签完整 Then。 | 0 / — |
| T-FORM-04 另一玩家发送非授权订单 | AUTHORITY PASS。逐一使用独立上下文、伪造身份、不同 Mission、混合可控/不可控选择及撤销后重试。均返回 Unauthorized，另一编队活动订单保持原值。跨 ENet 远端客户端场景 NOT_RUN。 | 0 / — |
| 补充测试 | 重复 ID 载荷冲突、多选不同版本、错误 tick、代际句柄、伪造成员、跨队未授权调拨、队列过期、取消、完成条件和只读快照均通过。 | 0 |
| P1 回归 | 15 套 application、bootstrap、campaign、content、contracts、core、definitions、engine、harness、inventory、mission、persistence、ports、rules、telemetry 全部 PASS。 | 0 |
| 结构及生产依赖 | 模块镜像、项目结构和依赖门禁通过，依赖问题数 0。 | 0 |

一次新增测试对动态读模使用了静态类型推导，Godot 报解析失败。终止该次进程后补齐 Dictionary 类型，完整入口重新运行通过。验收依据取自完成标志和错误日志。[测试入口](../../../game/tests/p2/formation/run.gd) · [订单与导航用例](../../../game/tests/p2/formation/field_cases.gd)

## 首次独立审查与 QA 退修

主 Agent 固化首轮候选 `2f35ed66079f986aa74698544ddf500323480318` 后，独立审查与 QA 均要求修复。开发者在该提交上原样复现并修正以下行为。

- 玩家跨队合并、用旧代际拆分等组织订单可能在真实提交时失败。固定步现在按所选编队依次解决所有者和受托者的争用，仅成功执行或排队的所有者指令能占用当步优先权。同一 tick 的先行拆分改变了成员表或编队编号时，后续订单读提交后的状态。多选仍整批裁决。相互委派形成循环时，按稳定的发起人和序号决定先后。
- 使用 Godot 的严格同值比较判断队键。整数 `0` 和字符串 `"0"` 在目标关系、合并、调拨三个路径都作为不同阵营处理。已执行的玩家移动指令持续受保护，之后授予队长权限也不会将其替换。玩家取消或执行者确认完成后，已获准的队长可以在下一步接管。
- 模块回归新增非法合并、代际失效拆分、跨队调拨、无效委派在两种抵达顺序下的正反断言，另行验证在场成员索引、同 tick 争抢新编队编号、跨队 charge/follow、有效玩家指令的取消/完成及多选冲突。

以下命令均在独立工作树、同一套 Godot 4.7.2 Standard 下运行。开发者使用未修改的独立脚本，未覆盖审查员和 QA 的原始日志。

| 原样命令或入口 | 修复前 | 修复后 |
|---|---|---|
| `& $godot --headless --path game --script D:/work/game/recollection/out/p2-review/formation2_conflicts.gd` | 退出 1，玩家合并失败后，合法队长令被取代，活动订单为空。 | 退出 0。合并 Failed/formation_ids，队长 hold 成为 Active。 |
| `& $godot --headless --path game --script D:/work/game/recollection/out/p2-qa/qa-form2.gd` | 退出 1，19 项中 5 失败，出现 String/int 比较脚本错误。 | 退出 0，`QA_FORM PASS checks=19 failures=0`，无脚本错误。 |
| 本文编队 Godot 入口及新增回归 | 首轮用例已通过，缺少上述反例。 | 退出 0，T-FORM-01/02、03-READ-MODEL、04-AUTHORITY 通过，66,499 个可达槽位端点。 |
| 本文 P1 harness，构建标签 `FORM-002-rework1` | 首轮 15 套通过。 | 15/15 套退出 0。生产依赖门禁 `dependencies PASS issues=0`。 |

退修改动只涉及 `ports/field_formation.gd`、`field_cases.gd` 和本报告。最终独立审查、QA 和主树集成态待主 Agent 确认。实际 HUD 和跨 ENet 场景仍未运行。

## 交接

变更位于编队 README、`order_rules.gd`、`ports/field_formation.gd`、编队测试 `run.gd` 和 `field_cases.gd`，以及本报告。测试使用生产引擎导航适配器和专属导航场景。未修改公共契约、引擎配置、状态或追踪表。实际 HUD、端到端战斗入口、全军动态运动/战斗表现、64/128 客户端及帧时预算均未在本任务验证。独立审查、QA、主树集成态由主 Agent 记录。
