# P2-MIS-RT-BATTLE-001 · 部署及增援的来源槽边界

候选状态为 CANDIDATE。开发 Agent p2mission，工作树 .worktrees/p2-mission，基线 `005d777`。需求 BAT-01、BAT-02、BAT-05、MIS-02，直接验收项 T-MIS-RT-02，回归 T-MIS-RT-03。[MIS-RT 详细设计](../../../docs/systems/game/mission/runtime/README.md)

Mission 在准备成功后将已验证的半开来源区间排序为 64 位边界数组，每次分配通过二分查找确认归属。存储量与区间数成正比，批部署的临时实体表共用同一份只读索引。人形兵源、无来源辅助实体、退场后句柄代际以及终局来源覆盖均由同一个 Mission 校验，自定义和多人结果也必须恰好覆盖各预留槽。

变更限于 `game/mission/runtime/entities.gd`、`game/mission/runtime/runtime.gd`、`game/tests/p2/mission/run.gd` 和本报告。公共协议及磁盘格式无变动。

## 实测

Windows，Godot 4.7.2.stable.official.ed1daf0bf，测试固定种子 `1234567890abcdef`。以下命令从任务工作树根目录执行。

```powershell
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path game --log-file "$env:TEMP/recollection-p2-mission-source.log" --script res://tests/p2/mission/run.gd
& $godot --headless --path game --log-file "$env:TEMP/recollection-p1-mission-source.log" --script res://tests/p1/mission/run.gd
git diff --check
```

| 用例 | 退出码 | 观测 |
|---|---:|---|
| T-MIS-RT-02 领域切片 | 0 | 实际 Mission 收到逆序的 1000 个分散预留，含相邻区间与 UINT32 最大槽。首次部署 500，运行中两波各换入 200；撤退后 900 个不同的曾入场槽和 100 个未入场槽均有终态。超容批次整批回滚，重复来源、迟到出生、过期句柄、非兵源冒用以及篡改结果拒绝。 |
| T-MIS-RT-03 与 P1 Mission | 0 | 50 次实际场景切换，最终节点数 1，失败数 0；既有重放摘要 `24427810fe1ace3d1cdfb22fbb42cdca7b98ec8eee7bc7a362dde96fd9677373` 相同。 |
| 差异空白检查 | 0 | 已跟踪文件差异通过。 |

P2 新用例首跑退出 1。结果夹具用点号追加校验字段，生成的 StringName 键不符合规范 JSON。改为显式字符串键后重跑通过。

测试由夹具提供终局结果，运行时负责拒绝错项、缺项和未入场状态矛盾。来源所属队伍、自动选择安全出生位置、来自真实战斗的撤退、以及 500/1000 人图形性能留待后续集成。完整 AT-04 和 AT-05 尚未在此任务运行。
