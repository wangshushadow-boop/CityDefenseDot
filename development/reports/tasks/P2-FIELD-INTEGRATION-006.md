# P2-FIELD-INTEGRATION-006 · 野战 Mission 装配

**CANDIDATE**。开发者 Agent `results_dev`，独立工作区 `.worktrees/p2-field-pipeline`，基线 `5b606542d09acdcd0305c25adb955f06d67a13da`，未自行提交。模块 MIS-RT，需求 BAT-01、MIS-02，任务用例 T-MIS-RT-01、T-MIS-RT-02、T-TEST-01。规格见 [Mission 运行时](../../../docs/systems/game/mission/runtime/README.md)。沿用 ADR-011 至 015。

## 实际交付

| 路径 | 职责 |
|---|---|
| `game/mission/runtime/runtime.gd` | 在已有实体候选内处理出生伴随物、批量退出、部分首波部署；最后一个可失败步骤置于提交钩子之前 |
| `game/mission/runtime/field_pipeline.gd` | 在同一 Mission 注册 FORM、BAI、MOV、Jolt、COM、RULES、RESULTS 相位，统筹授权、撤销、兵种装备解析、实体世代和真实坐骑 |
| `game/mission/runtime/field_mission.gd` | 既有 MissionPort 的野战入口，承接本地凭据、编队指令、部署、输入、撤退、历史权限复验和已提交只读投影 |
| `game/tests/p2/field_pipeline/run.gd` | 正式装配、真实物理、旧授权、最后提交拒绝、击倒补员、四兵种行军与千槽战果回归 |
| `development/reports/tasks/P2-FIELD-INTEGRATION-006.md` | 本任务执行证据 |

BOOT 用 `FieldMission.new(core,engine,mission_key,registry,resolve_principal,brains_factory)` 创建同一个 Mission；训练和访问仍走原运行时。普通部队从正式 TroopDef 和装备物品解析，只有装备快照的英雄通过指定 EquipmentDef 查找真实装备和坐骑。数值和字符串队伍键保持区分，COM 仅在自身边界使用稳定的阵营序号。入场马匹从同一实体池分配；骑手与马分别进入带世代、位置和方向的可见投影。

固定步验证全部下游候选后，MOV 最终复核有效驾驶授权，然后发布已确认的 Jolt、AI、FORM、COM、RULES 和 RESULTS 数据。投射物、击倒及来源归属来自 COM 回执，撤退与自然胜负来自 RULES。只有已提交的 RULES 结论才可通过 `request_end`。实体、装备或权限冲突均返回对应诊断。本任务没有修改公共契约或其他模块。

## 自测环境和命令

Windows，Godot `4.7.2.stable.official.ed1daf0bf` Standard，真实 headless 场景、Jolt、Godot 导航。场景种子 `1234567890abcdef`。以下 `Godot` 指 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe`，各命令用 `--log-file` 输出到任务工作区 `out/field-pipeline/`。常规套件使用真实 COM/MOV/FORM/RULES/RESULTS/引擎；为了可重播地单独触发指定伤亡，`--casualties` 使用无自主决策的已标记测试 brain。

| 用例 | 实际命令 | 退出码 | 结果与证据 |
|---|---|---:|---|
| T-MIS-RT-01、T-TEST-01 | `Godot --headless --path game --script res://tests/p2/field_pipeline/run.gd -- --casualties` | 0 | PASS。239 个检查，实战近战命中、伤情/XP、撤退、自然胜利、拒绝冒领敌人、凭据被撤销后整步回滚，同 tick 重试，授权被撤回再授予后不能重放旧编队回执。`casualties.log` |
| T-MIS-RT-02 实际源槽与波次 | 同一 `--casualties` 命令 | 0 | PASS。实际近战连续命中并造成 COM 击倒，腾出的索引由同一运行时用第二代句柄调入真实预备兵；随后 RESULTS 票据保留旧来源的受伤和原部队的经验。 |
| 006、013、014 跨域组合 | `Godot --headless --path <隔离副本>/game --script res://tests/p2/field_pipeline/run.gd -- --brains=res://mission/runtime/field_brains.gd --mount --large --objective` | 0 | PASS。141 个检查。临时副本以本工作树 game 为底，叠入 013 的 `field_brains.gd` 和 014 的 `field_movement.gd`、`jump_motion.gd`；每次复制后重新启动 Godot。日志 `staged.log` 未出现 SCRIPT ERROR、ERROR 或 FAIL。 |
| T-MIS-RT-02 原 Mission 多波 | `Godot --headless --path game --script res://tests/p2/mission/run.gd` | 0 | PASS，1038 个检查。1000 预留、首发 500、再入场 200+200，最终 100 未入场。`mission.log` |
| 受影响回归 | 同上，脚本改为 `res://tests/p2/results/run.gd`、`res://tests/p2/rules/run.gd`、`res://tests/p2/field_engine/run.gd` | 均 0 | PASS。RESULTS 147 个断言，RULES 38 个断言，真实引擎 70 个检查。对应 `results.log`、`rules.log`、`field_engine.log` |
| 结构与工作区 | `python development/check_project.py`、`git diff --check`、`git status --short --untracked-files=all` | 均 0 | PASS。改动限定在上表五项。提交态 diff 权限门禁由主 Agent 执行。 |

组合测试在河原真实场地上让相距 104 米的双方各出四兵种。双方收到实际 L1/L2 的 `line` 目标，FORM 发布命令，MOV 让双方阵列向目标行进，第 737 个固定步出现 Jolt/COM 确认伤害，采样最近距离 0.94 米。四人两马的试验逐对核实骑射手与马的句柄世代及移动位置。采用正式装备快照的英雄可下马、借助马匹投影中的原世代 rider_handle 识别并再骑上原马；场景放行的步行角色真实离地并落回场地。

千槽用例实际部署 500 个人形与 248 匹马，其同一时刻的可见模型亦为 748 个。整队退出后得到 250 个撤出来源和 500 个未入场来源。该次 headless 样本的出生步为 151.108 毫秒、第二步 28.573 毫秒。单步样本未验证完整帧性能，渲染、目标机性能及 1% low 由阶段基准另测。

## 先前失败与待验项

早期隔离副本遗漏 MOV 新增的 `jump_motion.gd`，引擎报脚本解析失败。补齐依赖后全部组合检查重跑通过，并新增最低断言数与真实命中判据，防止引擎脚本异常后以 0 退出而误记成功。最初的小队测试曾把自然溃逃胜利仅计作击倒，现分别核对 COM 的溃逃胜利和有预备队下的实际失能补员。

P2 桌面、目标设备、真实联网和阶段最终验收本任务均未执行。独立代码审查、独立 QA 和合并态验收由主 Agent 负责。开发交付限于本工作区的未提交候选。

## 2c49fb8 独立审查后的返修

在授权工作树上原样运行两份外部复现。末尾撤销纯转向加攻击输入的凭据时，旧实现把 tick 从 1 推到 2，角色从 Ready 变为 Windup；替换凭据的场景则停在 tick 1，阻塞后续合法输入。两份旧版复现都退出 1。

本次调整 `field_pipeline.gd` 的发布屏障和 `field_mission.gd` 的输入缓冲。所有非空外部批次在 MOV 或其他域发布前重新验证凭据、团队、角色世代与控制修订。该校验读取当步开始时的控制关系，使同一步由真实敌人击倒的玩家仍可正常结算。首次权限拒绝保留回滚和原批次。当次有效权限恢复时可以同 tick 原样重试；新凭据可以替代已失效的旧批次。没有替代输入时，下一次权威固定步复核仍已失效的凭据后，丢弃这批输入并继续。有效旧批次的冲突行为保留。

| 复验 | 实际命令与范围 | 退出码 | 证据 |
|---|---|---:|---|
| 独立脚本原样重跑 | Godot headless，`--path game --script D:/work/game/recollection/out/p2-qa/field-final-review/scope_commit.gd` 与同目录 `rebind.gd` | 0、0 | 末尾撤权保持 tick 1、原方向、Ready；新凭据接续成功推进到 tick 2。`returned-after.log`、`rebind-after.log` |
| 业务自测 | `--path game --script res://tests/p2/field_pipeline/run.gd -- --casualties` | 0 | 261 个检查通过，包括临时撤权同 tick 重试、纯转向与攻击、真实击倒、旧输入永久失效下的替代与服务器空输入推进。`returned-tests.log` |
| 真实组合 | 使用独立 QA 集成源的临时副本，覆盖本次两个生产文件与业务测试脚本；同上 `--brains=res://mission/runtime/field_brains.gd --mount --large --objective` | 0 | 163 个检查通过，500 人加 248 匹马；第 737 步实际命中。`returned-combined.log` |

另行定位双编队部署首次因 `deployment.spawn_site` 暂不可用。河原首次显示导航修订 1 已应用时，十个西侧站点的直接查询均未返回路径，Jolt 十处全部净空。随后修订 2 出现，路径查询成功；同一部署成功，首次玩家编队令使用序号 3。Mission 内已有按导航修订失效的缓存，BOOT 所有者负责保留待提交草案并重试。观测脚本 `west-probe.gd` 的附加调试探针在结束时打印了引擎资源回收告警，未用作正式通过证据。
