# 柳溪庄总督会面与庄簿委托独立技术终审

**PASS，2026-11-25。** 最终候选 `4cfca392e3ff9cfaaf0cc239d268da2a4e464e99` 已修复首轮实测的三项错误。核验范围为庄署在任人物、委托、庄簿、奖励和兼容，本报告供主 Agent 验收 P5-VISIT。

- 审查任务 P5-VISIT-REVIEW，独立角色 reviewer，工作区 `D:\work\game\recollection`，分支 `codex/p5-estate-visit`。基线 `9b975cc1b1809b620415aa64101e74df8b351252`，初审 `f8c9bdb3f693a8bea840d8a30330c2f1d8f27aae`。
- 对照 ADR-018、P5-VISIT-001 至 007、QST-01/02/04、T-VISIT-01/02。审查 QUEST、CHR、CAMP、SET、APP、BOOT、UI 的提交差异及测试调用方。审查者仅写 `out/p5/review/` 总结、探针和日志，Git 归档及引擎缓存也位于此处。`git diff --check 9b975cc 4cfca39` 退出 0。

## 初审 CHANGES_REQUIRED 及关闭依据

| 严重性 | 初审位置 | 实际复现及影响 | 终版关闭依据 |
|---|---|---|---|
| 高 | `game/campaign/quest/ports/estate_commission.gd:119` 附近的历史账校验 | D3 接事，D4 实际管理加成 3。D5 替换 SET 日账后，把 D4 加成改为 800、结余改为上限 1000，冷恢复成功。玩家能按不可能的繁荣增长交差。 | QUEST 核对留存摘要并调用 SET 的 `validate_daily_report`。管理/统御上界来自原发布者。D7 手动重算错误记录的摘要后，超出技能上界或违反算式仍拒载。 |
| 中 | 同上，及 `game/campaign/runtime.gd:370` 的事实投影 | 在 D5 存档把 D4 繁荣期初和期末都加一，D4 结余 505，D5 起账 504。初审接受两个互相冲突的余额。 | 相邻两日逐项比较繁荣与民心。另从 D3 开庄、D4 接事的真实旧档构造同样冲突，确保测试不依赖第一天强制起账 500。两项重算摘要后均拒载。 |
| 中 | 初审 `estate_commission.gd:146` 附近的接事日期校验 | 实际 D3 开庄，任务日期改成 D2、账日改成 D3 且截止改到 D5，仍可冷恢复。 | CAMP 送入 SET 开庄日。QUEST 在校验期限前检查起日。改写任务日期和账日并重算摘要，返回 `visit.origin`。 |

终版还拒绝一份增减相抵、期末与次日起账一致、技能在范围内，但没有原始摘要的账。全部拒载例同时比较失败前后的在用存档。摘要与账同存，用于检测误改。独立真实性核验来自 SET 公式、开庄日、能力上界和仍可见的日账。

## 实际行为与证据

- 名册来自真实家族英雄及 SET 的任命。通过治理页的“拜访庄署”，可见到刚任命的家族成员，通过交谈接事，在委托簿查日账，再与同一个人核对按上限截断后的实际增量。正常流程全部操作以命令重新核验人物和领地。UI 没有维护另一份任务或经验数据。
- 原发布者被撤换后，即使同一人当天重新获任，旧任务仍失败。当日不能重接，次日可接。签结后原发布者离任，原承办人仍可领奖。角色换代后不能继承前任的委托经验。暂时伤病/囚禁、回报期限及答错重试在 QUEST/CHR/战役套件覆盖。
- APP 实体磁盘套件覆盖玩家身份、接事前故障、签结后领奖断写、提交完成但回执丢失、再开存档、同 ID 重放与另一个 ID 重领。修改技能和领取标志共用一次提交。CHR 使用实际管理技能的既有成长规则。
- 基线代码经治理与日结命令生成、编码 18,198 字节的 P4 已任命总督存档。终版从文件解析后载入，所有字段保持相等，现任总督可给出首次委托。文件和两端脚本均随包附上。
- 无头运行使用 Windows Godot 4.7.2 Standard（ed1daf0bf）。桌面复验使用实际 Windows 窗口、960×600、Vulkan Forward+、RTX 3090。建档任命完成后仅发送 Tab、Enter，检查每个待激活控件的中心在窗口内，完成拜访、交谈、接事、查簿、过日、回复、领奖和返回。键盘事件由引擎注入，没有真人操作、屏幕阅读器或手柄测试。

| 版本 / 项目 | 实际命令入口，完整参数在 replay.ps1 | 退出码 | 结果 | 证据 |
|---|---|---:|---|---|
| 初审历史、失格及领奖 | Godot --headless --script boundaries.gd | 1 | FAIL 20/23 | boundaries-initial.log |
| 初审真实窗口 Tab/Enter | Godot --windowed --resolution 960x600 --script keyboard.gd | 0 | PASS 27/27 | keyboard-first.log |
| 终版原样复测 | Godot --headless --script boundaries.gd | 0 | PASS 23/23 | boundaries-final.log |
| P4 基线生成老档 | Godot --headless --script old_estate.gd | 0 | PASS | old-baseline.log，legacy-p4.json |
| 终版读 P4 及独立摘要/历史负例 | Godot --headless --script history.gd | 0 | PASS 16/16 | history-final.log |
| 终版真实窗口 Tab/Enter | Godot --windowed --resolution 960x600 --script keyboard.gd | 0 | PASS 27/27 | keyboard-final.log |
| 终版 QUEST / CHR | Godot --headless --script res://tests/p5/{estate_commission,visit_people}/run.gd，各自执行 | 0、0 | PASS 71/71、17/17 | estate_commission-final.log，visit_people-final.log |
| 终版 CAMP / APP | Godot --headless --script res://tests/p5/{estate_campaign,visit_session}/run.gd，各自执行 | 0、0 | PASS 42/42、16/16 | estate_campaign-final.log，visit_session-final.log |

## 复跑及交付

将证据包解压到可写目录，使用能访问上述 Git 对象的本地仓库及同版本 Godot。从解压目录运行以下 PowerShell，脚本在新建的空目录生成三个 Git 归档、真实旧档和各自的测试日志。复跑脚本已独立运行，整体退出 0，并逐项核对首版的三项预期失败。窗口测试需要 Windows 图形会话。

```powershell
.\replay.ps1 -Repository D:\work\game\recollection
```

独立终审无遗留阻断。此处采用战役存档字段比较、真实客户端键盘输入和源码测试，客户端导出包、鼠标验收及完整阶段门禁由项目独立 QA/集成报告记录。本报告及代码不会更新项目任务状态。
