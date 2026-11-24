# P2-BAI-I-001 个体野战决策

状态为 CANDIDATE。开发者 combatbatch 在独立工作区 `.worktrees/p2-individual`、基线 `154af0805882d215652556c3677b23efa06ac750` 上完成候选。需求 BAI-03、BAI-05、BAI-06、COM-05 对应 T-BAI-I-01 至 04。模块规格为 [BAI-I SDD](../../../docs/systems/game/mission/ai/individual/README.md)。独立审查、独立 QA 与最终合并态复测由主 Agent 登记。

## 运行时接入

[FieldIndividual](../../../game/mission/ai/individual/ports/field_individual.gd) 与已有 FieldAI 共用真实 Mission ID。统一兵种为 infantry、archer、cavalry、mounted_archer。骑射单位在 COM 使用骑兵、弓和实际挂接的坐骑，读取的感知角色与 L1/L2 一致。

1. 装配层创建 `FieldIndividual.new(mission_id, field_ai.get_instance_id())`。每个权威步借助 `fork()` 建立候选，调用 `decide(job, field_ai.sense(job.subject).value, combat.view(job.subject).value, constraint, local)`。同一 job 的本地视图必须共享 scope、instance、tick、control/order/nav revision 和 generation。权限变更与目标失效都经过 FieldAI 的 collect/drain 检查。
2. constraint 是 L2 的有界 MemberConstraint。local 提供米制 slot_position、可空 exit_position、heading、nav_revision，以及 `can_travel(from,to,revision) -> bool`。实时规模使用已判定的通行区或同版本缓存；Worker 只读快照，Godot 物理和导航查询由所有者线程执行。可选的 threat_handle、threat_direction、react_at、reaction_skill（0 至 1）来自己方局部威胁，incapacitated 仅接受至多 12 个本地已确认失能目标。若用精简批读 COM 行，local 另随同一权威读提供 weapons 与 reload_until。
3. `field_ai.collect(job, proposal.intents)` 后，仅消费 `field_ai.drain()` 实际返回的 batch。最多一条移动、一条视角和一条动作。移动经与玩家相同的 `mov.apply_move_intent(stage, move, authority_context)`，动作进现有 COM。向候选调用 `accept(batch, proposal, action_receipt, movement_receipt)`。整步成功才替换当前候选，回滚时丢弃。退场调用 `forget(handle)` 屏蔽旧代际。一个失败的动作只对同一意图短暂退避，移动有独立回执。
4. L3 保留目标句柄、限时锁、机动及回执记忆。作战时依据有限的敌友接触、距离、角色、近邻数量、槽偏差、通行和火控权限决定行动。步兵接敌/格挡，远程选择弓弩、瞄准和装填，骑兵冲锋、打击和脱离，骑射在可达空间移动射击。受伤、初始溃散、队形锁、低弹药及失去坐骑均从 COM/MOV 的权威事实读取。飞行与伤害由 COM 处理。

## 测试证据

Windows，Godot 4.7.2 Standard `ed1daf0bf`，Core Ultra 9 285K，headless。下列 `Godot` 指 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe`，测试进程使用专属 APPDATA 和 LOCALAPPDATA。夹具和入口为 [野战场景](../../../game/tests/p2/individual/arena.tscn)、[L3 实测](../../../game/tests/p2/individual/run.gd) 和 [权威移动对照](../../../game/tests/p2/individual/move_integration.gd)。

| 测试 | 实际命令及退出码 | 实测 |
|---|---|---|
| T-BAI-I-01、03 | `Godot --headless --path game --script res://tests/p2/individual/run.gd`，0 | 步兵/弓兵/弩兵/骑兵/骑射分别有 3/2/1/1/2 次物理命中，26 个 tick 内实际出现 start、hold、release。AI 输入与移除可选目标提示的玩家输入经同一 COM，逐步生命、动作、伤害和回执相等。弓首次攻击在 tick 1/13，弩在 1/21。 |
| T-BAI-I-02 | 同一入口，0 | 真墙遮蔽指定焦点、有限目标重新代际、目标锁到期、故人退场、不可达、有限火控与队形、动作退避/回滚、委派在 collect 与 drain 之间被撤销、真实 WorkerThreadPool 迟到结果、Mission 重开。628 项检查全部通过。 |
| T-BAI-I-04 | 同一入口，0 | 1000 人及 500 匹额外坐骑；120 个 60 Hz 步，10120 个真实分层授权 job、每步至多 85 个。113 个视野内可作出反应的紧急事件全部响应，最大积压 0，3717 条 COM 动作实际执行，MOV 在个体决策间继续移动。 |
| 玩家与 AI 共用正式 MOV | `Godot --headless --path <合成工程>/game --script res://tests/p2/individual/move_integration.gd`，0 | 两人源各自使用独立 MOV，逐步坐标一致。步兵 100 步仅 6 条命令，55 步无新命令仍移动，终点离出口 0.042 m。骑射 180 步仅 12 条命令，122 步无新命令仍移动，终点误差 0.195 m。合计 957 项通过，含失败事务重试、错凭据拒绝与到点停步。 |

移动合成工程从本候选复制 game，叠加 P2-MOV 输入任务的完整 movement 目录，输入场景和 AI 用例相同。最近合成使用的 field_movement.gd SHA-256 为 `fd9c5077c13bd0f355ebdfb5be9140373d2655f34a88cab43ebf781ef607d42b`，intent_route.gd 为 `b5c3473b599f8dcdfc44c43c40082e66c533fd0ee155120772e74baf1b4c8742`。基线单独运行该新增 MOV 入口测试会明确 NOT_RUN；其余 L3 实测直接在工作树运行。最初步兵直接越过出口后振荡，骑射沿用短制动距离时冲过 1.246 m。按固定步间隔、坐骑实际速度与减速度调整到点速度后，同一终点判据通过。

## 1000 人决策与固定步时间

四个兵种各占四分之一。已实跑真实 MOV 导航、人群移动、BAI 物理 LOS、L3、COM 状态机、坐骑和物理查询。压力夹具使用真实静态碰撞体；逐兵物理命中对照在上面的角色场景完成。三轮相同工作量，以下为 P95 毫秒。

| 轮次 | MOV 步 | 批读位姿并生成 COM 输入字典 | L3 decide/accept | COM（含物理） | 测试夹具整步 |
|---|---:|---:|---:|---:|---:|
| 1 | 5.486 | 1.750 | 4.009 | 10.478 | 29.645 |
| 2 | 5.011 | 1.507 | 3.871 | 9.938 | 28.466 |
| 3 | 5.271 | 1.635 | 3.982 | 9.707 | 28.571 |

三轮整步均超过 16.667 ms。此工作量含 50% 骑乘人员，正式门禁为 20% 骑兵；本项证明紧急反应与低频移动继续运行，完整战场的帧率、固定步时限及 AT-04/05 仍需按阶段条件独立验收。P4 器械交互、真实网络和 GPU 渲染均未在本任务运行。

同一引擎的 `res://tests/p2/ai/run.gd -- --functional-only`、`p2/combat`、`p2/movement`、`p2/mission` 和 `p1/contracts` 的现有入口分别退出 0。AI 回归保留真实工作量和性能输出，functional-only 模式用于这个模块的行为回归。开发中曾因测试脚本的类型推断和 MOV roster token 类型错误触发 Godot 错误，修复后复跑；所有最终结果同时核对进程退出码、通过标志及引擎错误输出。

`python ci/gates.py dependencies`、`python docs/architecture/check_mirror.py`、`python development/check_project.py` 和 `git diff --check` 均退出 0。

仅新增 L3 端口、三个专属测试/场景和本报告；无全局写入、数据格式或网络契约变更。候选由主 Agent 固化、独立审查和集成。
