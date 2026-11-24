# P2-BAI-T-001 普通野战 L1 战术计划

**状态为 CANDIDATE。** T-BAI-T-01、02、03 开发自测连续三轮通过。工作区为 `.worktrees/p2-tactical`，detached HEAD `154af0805882d215652556c3677b23efa06ac750`。开发者为主 Agent 委派的 nav。基于 BAI-T SDD 0.1、BAI-01、BAI-04 和主树 P2.md 的分层交接约定。未写 Git 提交、架构契约和共享状态。

## 候选内容

| 路径 | 变更 |
|---|---|
| `game/mission/ai/tactical/ports/field_tactics.gd` | 在主 Agent 草案上完成输入、授权和事务检查。按已知接触、真实可达性与视线、目标位置、编队角色/弹药、己方有效人数和士气选择每队一个任务。 |
| `game/mission/ai/tactical/README.md` | 指向本地门面、场景测试及权威 SDD。 |
| `game/tests/p2/tactical/arena.tscn` | 共享边的平地、坡道、平台导航多边形，以及可遮挡物理射线的低墙。 |
| `game/tests/p2/tactical/run.gd` | 真实 BAI/team、FORM 和引擎导航/物理查询；包含等距、锁期、局部回退、拒绝旧任务、玩家权限、事务、增援、撤退、空弹和局部成本诊断。 |

只向获授权的编队输出 L2 约定的 role、goal、completion 等字段；实际成员角色按活跃单位计数，独立坐骑排除在战力计数之外。评估及选择发生在获准的 L1 调度内；对外可观察阶段为 Deploy、Engage、Adapt、Retreat、Finish。有可用旧站点且仍在 180 步锁期时优先复验该站点。480 步任务超时、授权/订单修订、增援/伤亡比例、已知目标或者弹药状态变化可触发重评。不可用站点按编队短期记忆，导航修订变化或等待期届满后允许再次探查。没有可靠站点时在当前位置 hold。

## 组合层接入

`FieldTactics.new(scope_id, team, may_command, evaluate_site, current_view, admit_job)` 的四项本地注入为：

- `may_command(scope_id,formation_id,control_revision,order_revision) -> bool`。从当前权威 FORM/Mission 读模检验团队指挥岗位及两份修订。stage 初筛，每次 commit 再检查。测试中的两名发令者各在不同场景通过已执行的 FORM 订单建立修订读模；正式组合须使用自己发布到 BAI 的同一订单版本来源。
- `evaluate_site(scope_id,nav_revision,formation_id,origin_m,site_m,contact_m_or_null,role) -> Result({reachable:bool,line:bool})`。测试注入实际 query_path_batch 及 query_sweep_batch。每组至多 32 个候选点，采用米制有限 Vector3，可选 objective 布尔标记。
- `current_view(team) -> Dictionary` 直接返回成功的 `BAI.team_view(team).value`，不可用时返回空字典。stage 对比整份权威视图并使用可信行计算，commit 检查当前 stamp。检查 Godot 实际的有符号 Mission 对象 instance、tick、导航修订和本队编队修订。
- `admit_job(job) -> Result` 的直接绑定为 `board.collect.bind([])`。L1.commit 先检查权威、视图和作用域，再调用此回调，只有真实 BAI 受理的 job 能发布。若组合已统一收集/分发，应传入从本步真实 BAI 回执中核实并一次领取此 job 的适配器。

在 Mission 的可回滚阶段调用 `stage(job,team_view,sites,feedback=[],finished=false)`。它返回一份独立候选副本，已发布的 `view()` 保持上次结果。失败或其余领域放弃该步时调用 `rollback()`，相同 BAI job 可重新 stage。各领域准备完后才调用 `commit()`，并检查其 Result；失败时丢弃候选，保留上次已提交计划。配合直接绑定时，BAI.collect 只在此处消费一次，组合层依原流程统一 drain，不为 L1 私自排空其他层回执。L2 只接已提交并仍有授权的 FormationTask，L1 不调用 FORM.issue_order。`close()` 使本实例和待提交候选失效。

L2 反馈为 `{formation_id,task_id,status,reason,progress}`，status 接受 running、blocked、failed、completed。检查 task_id 对应上一份已提交任务。其他旧 id 不能改变当前任务，重复匹配及非法状态会遭拒。有效完成反馈保留原任务，失败/阻塞允许局部回退，player_order/not_delegated 让出相应编队。

## 测试和命令

Windows x64，Godot Standard 4.7.2 stable ed1daf0bf，headless。使用确定性几何、固定 roster，无随机源。

```powershell
$engine = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
$pythonRuntime = 'C:/Users/10822/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $engine --headless --path game --log-file "$env:TEMP/p2-tactics.log" --script res://tests/p2/tactical/run.gd
& $engine --headless --path game --log-file "$env:TEMP/p2-tactics.log" --script res://tests/p2/formation/run.gd
& $engine --headless --path game --log-file "$env:TEMP/p2-tactics.log" --script res://tests/p2/ai/run.gd
& $pythonRuntime ci/gates.py dependencies
& $pythonRuntime docs/architecture/check_mirror.py
& $pythonRuntime development/check_project.py
git diff --check
git status --short --untracked-files=all
```

| 用例 | 退出码 | 开发实测 |
|---|---:|---|
| T-BAI-T-01 | 0 / 0 / 0 | 5 个候选含真实离网位置。低墙挡住平地至敌方的线，平台连通坡道且有视线。弓手选择 deck/cover，步兵选择 objective/advance，骑兵选择 lateral/flank，骑射选择 harass。相同评分/等距且同戳时，交换输入顺序仍按稳定 id 选择。 |
| T-BAI-T-02 | 0 / 0 / 0 | L2 blocked 使单个编队切换至 better 并进入 Adapt，其余保留任务 id；仅一处失败时先 hold，等待期后再试。缺弹、收到增援、超时、失去可见接触分别触发重分配或取消目标。低士气转 Retreat，离网候选全部失败时 hold。 |
| T-BAI-T-03 | 0 / 0 / 0 | 真实 FORM 玩家 hold0 始终保留；明确委派后方可获任务。stage 后同 tick 撤权或执行新 FORM 订单均拒绝 commit。保持当前 stamp 和视图而伪造 job.id，从正常 stage/commit 入口提交失败；原计划和 BAI 输出不变。同名新 Mission 拒绝旧首 job 与旧候选。 |
| FORM 基线回归 | 0 | T-FORM-01～04、P2-FORM-002，66,499 个可达槽，失败 0。 |
| BAI 基线回归 | 0 | 原 BAI 500/1000 真实混合负载，整步 P95 分别为 7.056/13.877 ms，积压 0。此基线回归未运行独立 L1。 |
| dependencies / check_mirror / check_project / diff | 0 | 依赖、镜像、项目结构和已跟踪文件空白检查通过。 |

最终三轮均输出 `FIELD_TACTICS errors=0 nav_queries=1576 physical_los=4590`。开发中首个运行对 RefCounted 的负 instance、FORM 连续 tick 和夹具的真实遮挡判断失误，最初三项断言失败；已用实际引擎数值和几何修正。新增接触用例还发现 Deploy 的旧 hold 在锁期内沿用，阻挡接敌后的重新选位；现以已观察目标及弹药变化打破该编队的锁期。三轮均包含这些回归。

## 局部性能

每档 20 个 BAI 授予的 1 Hz 决策，20 个编队、双阵营、5 个候选，场上 500/1000 人分别有 250/500 本方成员。每档每轮提交 200 份任务，500 人使用 680 次地形查询与 2,126 条物理射线，1000 人使用 692 次与 2,139 条。时间包含本队视图、L1 stage/commit、真实授权和候选地形查询；射线计数包含为 BAI 建立当前情报的查询。

| 人数 | 三轮 L1 P50 毫秒 | 三轮 L1 P95 毫秒 | 三轮最慢决策毫秒 |
|---|---|---|---|
| 500 | 2.673 / 2.844 / 2.768 | 3.496 / 3.467 / 3.200 | 3.505 / 3.606 / 3.346 |
| 1000 | 4.518 / 4.502 / 4.823 | 5.358 / 5.264 / 5.369 | 8.527 / 5.395 / 5.411 |

本任务只测普通野战 L1。三层完整同帧成本、图形性能、其他战斗类型、最终 Mission 装配、独立审查与 QA 在此工作树 NOT_RUN。上表只能用于组合层安排 L1 低频计算；阶段性能须由实际整场装配验证。候选交主 Agent 审查、QA 和集成。
