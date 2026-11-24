# P2-BAI-F-001 编队 AI 开发自测

基线为 `154af0805882d215652556c3677b23efa06ac750`。使用 Godot 4.7.2 Standard Windows headless。开发自测通过，待主 Agent 独立审查、QA 和集成验收。

## 交付与接线

[编队入口](../../../game/mission/ai/formation/ports/field_formation_ai.gd)维护当前编队行为、目标、任务 ID、控制版本和重组信息。[行为选择](../../../game/mission/ai/formation/behaviors/field_behavior.gd)读取 BAI 可见接触与己方 COM/MOV 聚合数据。成员、槽位、路径、弹药和权威订单仍由各领域维护。

1. 每 Mission、每队创建一个 `new(mission_id, issuer_id, ai.formation_view, form.view, team_key, ai.collect)`。组合层从同一 Mission 的 L1 已提交计划取本编队任务，以 BAI 已授予的 `formation` job 调用 `stage(job, task_or_null, terrain, next_sequence)`。给同一个 issuer 的所有命令生产者统一分配递增序号。任务站点用米，超时为绝对 tick。地形读侧给出当前 `clear_width/spacing/slot_error`（米）、`yaw`（弧度）、`reachable`，可附当前 FORM 槽位结果的 `compressed`。
2. stage 返回 token、orders、behavior、local_goal、member_constraint、slot_request 和 feedback。每次授予最多生成一个冻结 v1 订单。编队成员共用一份冻结字段形状的约束。玩家的有效持令、停火和跟随优先。AI 有权行进时，窄道中保留可达目的地并收紧编队，伤亡后使用 FORM 的剩余成员与新投影继续通过。
3. 对候选调用 `collect(token)`。它内部使用绑定的唯一 `BAI.collect`，检查 job、权限并消费一次。之后由组合层统一 `BAI.drain()`，保留与该 job 匹配的行。先对各域预检，L2 用 `validate(token,row)` 重查当前快照、控制权与实际 FORM 状态。跨域失败时 `rollback(token)` 不发布脑状态、命令或反馈。若已经 drain，保留该行；同一有效 job 的同等订单重做 collect 复用授权。新 job、变更订单和旧 token 不能复用旧回执。
4. 在不再回滚的帧发布段，按稳定顺序经 `FORM.issue_order(order,authenticated_actor,control_revision)` 送入与玩家相同的权威入口。订单的 issued_tick 为观测 tick + 1，重复发送保留同一 order_id、序号和载荷。L2 在 FORM.advance 前用 `commit(token,row)` 提交。组合层读取已提交 `view(id)`，提供 `member_constraint` 给 L3，并把 `feedback` 送到 L1 的下次已授予 job。FORM.advance 决定最终权威回执、玩家优先和冲突处理。FORM.build_slot_targets 接收 slot_request 的参数与导航投影函数，将成功的槽位传给 MOV.assign，共享走廊遵循有效 FORM 订单和 local_goal。Mission 销毁调用 close。

## 实测

[验收入口](../../../game/tests/p2/formation_ai/run.gd)使用同一测试世界的真实 BAI、FORM、MOV、COM 和引擎导航/物理。T-BAI-F-03 在工作树缺少 L1 源文件时，可由环境变量 `RECOLLECTION_TEST_L1` 指向并行开发树的真实 L1 源文件。合并后优先加载本仓 `res://mission/ai/tactical/ports/field_tactics.gd`。缺少两者时该项报告 NOT_RUN 并使 suite 失败。

| 验收 | 证据 |
|---|---|
| T-BAI-F-01 / BAI-01 | 可见目标使骑兵得到真实 Charge 候选。玩家 hold 已生效后，旧候选无法提交；新 job 即使拿着先前 L1 任务也保持 Hold，移动限额为 0，不产生替换令。另验假 job、过期控制版本、未委派、禁止开火及跟随友军。PASS。 |
| T-BAI-F-02 / BAI-02 | 导航采样测得通道宽 1 m。真实 v1 move 承载通过目标，FORM 压缩槽位。COM 弓箭击中一名 5 HP 成员，剩余两人重新分槽。MOV 从仍生效的订单取得终点并实际行走 240 步，中心到 (5.87243, 0, -7.98029)；宽地恢复原横队与 Advance，无重复订单。场景累计成功投影 25 个点。PASS。 |
| T-BAI-F-03 / BAI-04 | 使用生产 L1 实际生成的 cover 任务。弓箭释放从 1 支扣到 0，以及另一次任务运行到绝对超时，均产生合法 hold。提交后的 failed 回馈分别携带 ammo_depleted 和 timeout。L1 同一 job 无回馈时仍选择 ridge，回滚并提供回馈后排除 ridge、切换 Adapt，重新分配任务。落实六参 L1 构造器及真实 BAI 授权回执；L2 也覆盖收集后回滚、同 tick 重试、伪造/弃用 token 和重复提交。PASS。 |

自测最终输出为 `P2-BAI-F-001 PASS assertions=4775 failures=0`。附加行为覆盖推进、守点、射击、骑射、撤退、玩家跟随、不可达与溃散。单一大编队成本切片在 500/1000 名己方步兵的 COM/MOV/FORM 实读集上预热一次、各采 20 个已授予 job。分别测得 P50/P95 为 2316/3343 µs、4681/5025 µs。这段计时包括 L2 stage、BAI 收集并 drain、预检和脑状态提交。生成源数据、发布 BAI 快照、图形和各域权威执行不在切片内。基础 BAI 的独立混合 500/1000 回归也已跑通，max_backlog 均为 0，combined P95 为 7989/13225 µs。AT-04/05 与实际桌面整局帧率未在本任务执行。

| 命令（工作树根目录） | 结果 |
|---|---|
| `Godot_v4.7.2-stable_win64_console.exe --headless --log-file <scratch>/godot.log --path game --script res://tests/p2/formation_ai/run.gd --quit-after 1200` | 退出 0；测试时 RECOLLECTION_TEST_L1 指向 p2-tactical 工作树、APPDATA 与 LOCALAPPDATA 指向独立临时目录。 |
| 同一命令分别运行 `res://tests/p2/{formation,movement,combat,ai}/run.gd` | 四项实跑均退出 0；FORM 66499 可达槽位，MOV 切片完成，COM errors=0，BAI 500/1000 通过。 |
| `python game/tests/p1/harness/suite.py --godot D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe` | 15 套 PASS，各自退出 0。 |
| `python ci/gates.py dependencies`、`python development/check_project.py` | 均退出 0。只作依赖与工程结构检查。 |

早期测试复用了大尺度 FORM 场景，从窄道到所选终点的真实导航返回不可达，MOV 无路径，T-BAI-F-02 当次失败。改用专属小尺度导航夹具后，真实成员穿过同宽窄道并恢复横队。L1 并行开发期间的构造器和授权回调改变曾令 T-BAI-F-03 失败，随后按最终真实接口修正并重新运行。尚未执行本任务在正式 bootstrap 的整局装配、L3 生产消费及 8 GiB 硬件验收。
