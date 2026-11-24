# 中断与恢复

重新开启 Codex 时读取 AGENTS.md、PROJECT_STATE.md、state/*.json、最近报告；检查实际 `git status`、分支、worktree、HEAD 和待提交 diff。不要假定上次 Agent 仍然运行。主 Agent 对照记录逐一确认任务工作区和锁、已合并 commit、真实证据。无法确认的 RUNNING 成果先保留并标为 BLOCKED 或恢复任务，不能删除。

若上次已达到候选实现但未完成审查，恢复 TESTING/REVIEW；若已合并但无证据，重跑回归，不重复合并；若状态文件与 commit 不一致，记录修复原因及实际依据。必须只恢复当前授权阶段，除非收到新阶段指令。会话/额度限制导致的未完成任务留待下一次用户启动。
