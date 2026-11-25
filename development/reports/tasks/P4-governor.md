# P4 总督治理任务与集成记录

六项任务服务于 T-GOV-01 和 T-GOV-02。主 Agent 整合 SET、CHR、CAMP、APP、BOOT 和 UI 后验收，开发者仅交付候选。原始工作树均从 `5e1ad4c` 创建。各任务 JSON 记录模块、路径与用于审核独立 diff 的直接提交基线。

| 任务 | 执行人和候选 | 交付及实测 |
|---|---|---|
| P4-GOV-001 · SET | governor_set · `6e0750c` | 庄邑开办、任免、资格复核、日结及上下限，领域套件 58/58。 |
| P4-GOV-002 · CHR | 主 Agent · `0412b83` | 从已有家户读取成员、资格和有效管理/统御；个人天赋与领地天赋对照，13/13。 |
| P4-GOV-003 · CAMP | governor_camp · `a5a85f8` | 治理状态随角色、时钟及账本一次提交。部署互斥、失格、冷载及失败回滚，49/49。 |
| P4-GOV-004 · APP | 主 Agent · `7cbdf21` | 现有受信会话路由三项操作，保留权限、修订及回执校验。真实磁盘与重放，17/17。 |
| P4-GOV-005 · BOOT | 主 Agent · `8c0f99a` | 将任免命令绑定当前玩家和沙盒。通过正式客户端入口及专项旧档探针验证。 |
| P4-GOV-006 · UI | governor_ui · `7cf820a`、`7a7be54` | 从实际人物页接管、任免、预览日结、推进与读档，家族结束仍可回看账簿。Windows 客户端通过 73/73。 |

主 Agent 检查所有候选提交与授权路径并逐项运行 `development/check_diff.py`，6 组 diff 共 11 个文件，越界 0。独立审查员另从冷归档审查全部差异。集成分支 `codex/p4-governor` 按 SET → CAMP → UI 合并至已接好 CHR、APP、BOOT 的主线，产生 `f3b8939`、`f2de242` 和生产候选 `0ca0100`。无合并冲突。需要整体回退时，上一个生产基线为 `5e1ad4c`；含治理字段的新存档应使用本版本读取。

独立 QA 由 governor_qa 执行，独立技术审查由 governor_review 执行。相关测试均直接运行 Godot，结构检查单独记录。主 Agent 在 Windows 本机对最终源码、客户端 PCK、专服冒烟及回归证据完成验收。[阶段报告](../stages/P4-governor.md) · [六项路径检查与集成日志](../tests/P4/governor/integration.zip)

主 Agent 释放六项写锁，回收三个已合并的隔离工作树。测试产生的本地缓存与导入元数据保留在 out/p4/worktree-artifacts。
