# 集成与回归

只有主 Agent 或被明确委派的 integration Agent 可操作集成分支；一批中串行合并。验证原基线、依赖已 DONE、候选 commit/分支存在、review/QA 通过、diff 未越权、用户修改安全。优先按依赖顺序合并或 cherry-pick（遵循仓库策略）；不得自动 force push、reset --hard 或删除其他 Agent 未交付成果。

合并前记录回滚点；冲突涉及公共契约、跨模块所有权或行为改变时停下提交方案。合并后执行真实构建、适用的模块/契约/跨模块测试以及 `python3 development/check_project.py`；结构检查不代替游戏回归。出现失败保持任务 IN_PROGRESS/BLOCKED，保留证据，通过安全的 revert 或单独修复提交恢复，不破坏历史。

填写 [集成报告](../templates/integration_report.md)，包括集成 commit、依赖、候选 diff 检查、合并方式、命令、退出码、回归结论及回滚点；再由主 Agent 更新 tasks/modules/project 和追踪表。确认成果保留后释放锁、清理已合并 worktree。

可用 `python3 development/check_diff.py <task-json> <base-commit> <candidate-commit> --repo <worktree>` 核对候选提交的实际变更路径；该脚本仅审查提交间 diff，不替代初始/当前 `git status`、未跟踪文件检查、所有权审查或权限沙盒。
