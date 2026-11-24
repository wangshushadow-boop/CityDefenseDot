# P2-MIS-RT-BATTLE-003 · 野战预留兵员归属

2026-11-24。执行者为子 Agent contracts，独立工作树 `.worktrees/p2-field_sources`，基线 `cdfe8eb6d507ef680c1d52bd28badb7ff5453b3b`。交付状态 CANDIDATE。实现 CON 对批准的 ADR-014 方案 A 的野战校验；任务关联 BAT-01、BAT-02、BAT-05、MIS-02。正式的阶段状态、审查、QA 与集成提交由主 Agent 登记。

[FieldSources](../../../game/contracts/field_sources.gd) 先调用既有 v1 校验，随后要求至少两支具有分配的不同队伍，每条分配只含 source_slot_range，两个端点均是合法整数。比较已预留和已分配区间在各端点的覆盖数变化，验证区间并集完全相等；排序后显式拒绝同队/跨队重叠。构建只读区间索引，按 source_slot_id 二分查找，返回原始 String 或 uint32 的 v1 team_key。输入修改不会影响查表。所需空间取决于区间数，扫描从不展开整段兵员。旧 v1 读取、编码与五个 Mission 生命周期端口继续使用原入口。[ADR-014](../../../docs/architecture/decisions/ADR-014-field-source-teams.md)

## 实测

Godot Standard 4.7.2.stable.official.ed1daf0bf，全部入口使用下列形式执行。每次在独立临时目录放置运行日志及 APPDATA/LOCALAPPDATA。最后一项由持久化脚本自身明确列为未运行。

```powershell
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path game --log-file $log --script res://tests/p2/field_sources/run.gd
```

| 脚本（相对于 game/tests） | 退出码 | 输出与覆盖 |
|---|---:|---|
| [p2/field_sources/run.gd](../../../game/tests/p2/field_sources/run.gd) | 0 | `FIELD_SOURCES checks=45 failures=0`。三队同 Party/兵种拆分，0 和 "0" 独立，稀疏/相邻/整个 uint32 区间、英雄单槽、半开上界、只读快照、历史空分配编码与解码。拒绝空队、重叠、漏分、越界、同数量错位、未知字段、浮点和布尔。 |
| p1/contracts/run.gd | 0 | T-CON-01、02、03 及 P1 契约边界 PASS。 |
| p1/mission/run.gd | 0 | 重放摘要 24427810fe1ace3d1cdfb22fbb42cdca7b98ec8eee7bc7a362dde96fd9677373，50 次切换通过。 |
| p2/mission/run.gd | 0 | 1,000 个预留，初始 500、两波各增援 200；900 个已入场，100 个未入场，失败 0。 |
| p1/application/run.gd | 0 | T-APP-01/AT-10 切片、T-APP-02/03、T-APP-04 切片，错误 0。 |
| p1/persistence/run.gd | 0 | 27 个子进程；T-PERSIST-02、T-PERSIST-01/03 切片通过，T-PERSIST-04 在该脚本为 NOT_RUN。 |

任务写入范围仅含独立契约文件、专属测试入口和本报告。本次验证对应 T-MIS-RT-01/02 的野战兵源准备切片。实际野战装配、同批部署故障回滚的跨模块复验及正式 AT-04/05 由后续任务组织，本任务未将这些项目标记通过。
