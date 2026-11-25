# P2-RESULTS-001 · 野战来源与结果

**CANDIDATE**。开发者 Agent `results_dev`，工作区 `.worktrees/p2-results`，分离 HEAD，基线 `46af5b1fcc4eb0d13b64ef146298f82074685806`。交付形式为未提交的工作区 diff。主 Agent 负责独立审查、独立 QA 和集成门禁。

模块 RESULTS，对应 ARM-05、BAT-02/03/04 与 SGE-03。依据 [RESULTS 规格](../../../docs/systems/game/mission/results/README.md)、v1 MissionResult 和已批准的 ADR-014/015 A。

## 变更

| 路径 | 用途 |
|---|---|
| `game/mission/results/ports/field_results.gd` | 使用 Mission 的预留范围、出生历史、带世代的来源绑定和真实 COM/RULES 事实构建不可变票据 |
| `game/mission/results/README.md` | 模块入口与测试导航 |
| `game/tests/p2/results/run.gd` | Mission 固定步、真实碰撞、三方退出、异常票据及 App 路由回归 |
| `development/reports/tasks/P2-RESULTS-001.md` | 开发自测记录 |

授权范围内无公共契约、数据格式或战役写入修改。每步按实体集合变化登记来源绑定，按有效接触或退出记录变更。存活状态与是否入场分别读取 Mission 最终实体与历史槽集合。相同索引的不同世代分别归属，射手离开后已发投射物保留原来源。固定步失败时丢弃当步变更，结束回调只接受最后提交的 RULES 决定。预留范围逐槽有序展开，生成的 SHA-256 覆盖票据除摘要自身以外的所有字段。

当前野战计量为一次有正伤害的敌方人形接触记 1 点来源 XP。仅当实际 COM 击倒且同一击倒步的致伤来源可唯一关联到获胜敌方时，才产生俘虏候选。已撤离的伤员保留伤情，同步伤害来源有歧义时跳过候选。战役票据将符合条件的来源槽与其预留装备快照关联为战利品声明。经济奖励发放、医疗裁定和俘虏容量由后续战役结算负责。自定义与多人票据的战役身份留空，队伍汇总分别统计互斥终态及可与撤离并存的伤情。

## 实测

Windows，Godot `4.7.2.stable.official.ed1daf0bf` Standard，headless，场景种子 `1234567890abcdef`。在上述工作树执行，下表 `Godot` 为 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe`。将 APPDATA 指向工作树的 `out/profiles/results`，分别用 `--log-file` 在该目录保留表中日志。

| 用例 | 实际命令 | 退出码 | 结果与证据 |
|---|---|---:|---|
| T-RESULTS-01 | `Godot --headless --path game --script res://tests/p2/results/run.gd` | 0 | PASS。三方 1000 槽，其中 997 未部署。物理近战造成英雄失能，同步源槽/候选/XP/队伍统计，三方依次撤退和受伤撤离正确。弓手发射后退场，原索引复用，实际物理命中后仍归原槽。晚期故障回滚与重试保持一次 XP。日志 `results.log` |
| T-RESULTS-02 | 同一 RESULTS 脚本 | 0 | PASS。拒绝缺少、重复、范围外的槽、标识或修订不符、损坏哈希、假胜方、错队俘获、英雄状态不一致、重复英雄和过期目标句柄。诊断包含对应字段 |
| T-RESULTS-03 | 同一 RESULTS 脚本 | 0 | PASS。两个模式通过真实 `GameSession.finish_mission/route_result` 路由和重试，战役持久快照相等，战役结算调用数 0，多人结果接收器调用数 1。全组共 147 个断言、6 次物理接触、0 失败 |
| RULES 野战回归 | `Godot --headless --path game --script res://tests/p2/rules/run.gd` | 0 | PASS，38 个断言，1 次物理接触，`rules.log` |
| COM 野战回归 | `Godot --headless --path game --script res://tests/p2/combat/run.gd` | 0 | PASS，P2-COM-001/002 均 0 错误，44 组物理查询、46 次查询，`combat.log` |
| Mission 来源、增援回归 | `Godot --headless --path game --script res://tests/p2/mission/run.gd` | 0 | PASS，野战 1038 个检查，来源切片 0 失败，1000 预留下实际调入 500+200+200，`mission.log` |
| 研发结构、SDD 镜像 | `python development/check_project.py` 与 `python docs/architecture/check_mirror.py` | 0、0 | PASS，57 个规范、96 个目录映射 |
| T-RESULTS-04 | 未运行 | — | NOT_RUN。攻城设备和城防差异属于 P4，P2 野战 `siege_changes` 为空 |

1000 槽样本的规范 JSON 共 97,164 字节。单次完整结束、校验与缓存重读合计 231.578 毫秒。此测量包含 Mission 再次验证和重复读取。未测独立构建器 P95、完整野战视听性能或真实多人网络传输。本任务对实战路由的验证以本机真实 GameSession 和测试接收器为界。

## 交付

工作区 `git status --short --untracked-files=all` 列出的改动为上述四个路径。`git diff --check` 退出 0。提交态权限检查、正式 BOOT 接线、合并态全局重跑与 P2 阶段验收交由主 Agent。
