# 在一个 Codex 窗口中组织多 Agent

## 启动

在本项目根目录打开 Codex（桌面、CLI 或支持的 IDE）。检查客户端版本、Git、Python 3.11+、当前可用 Subagent 工具及项目受信任状态。若环境只支持单 Agent，使用主 Agent 顺序扮演角色，不报告虚假的并行。用户只给阶段目标；主 Agent 负责任务图、创建/等待子 Agent、收集结果、修复、集成和验收。

项目 `.codex/config.toml` 使用 `[agents] enabled = true`、`max_concurrent_threads_per_session = 4`，并发上限不等于实际创建数量。可根据工具、额度、CPU 和磁盘调低；不要把 57 个模块同时启动。旧版可能使用 `max_threads` 兼容别名；若版本不识别配置，以实际官方文档及客户端提示为准，记录变更，不能假定已经生效。

`.codex/agents/` 包含 6 个可选自定义角色（architect/planner/developer/reviewer/qa/integration）；模型由当前会话继承或选择可用模型，未绑定特定付费档。主控是当前窗口本身，不额外占子 Agent 线程。自定义角色只说明职责，不是独立权限沙盒；不修改审批/沙盒。原生子 Agent 不保证自动 worktree 隔离。

## 工作目录隔离

主 Agent 先确认干净的基线 commit；保留用户已有改动。需要并行写入时，使用独立分支和 worktree，例如（仅示例，任务确定后再执行）：

```bash
git status --short
git worktree list
git worktree add -b task/P2-COM-001 ../recollection-wt-P2-COM-001 HEAD
```

主 Agent 将绝对目录和基线 commit 明确传入任务；子 Agent 首先 `pwd`、`git rev-parse --show-toplevel`、`git rev-parse HEAD`，确认真实工作区。若无法在该目录操作，降级为顺序写入，不通过改变沙盒权限规避限制。分支、worktree、锁、基线和 diff 记录于任务/报告；共享文件由主 Agent 串行变更。

集成后经负责人或现有仓库权限允许才清理已确认的工作树；不强制删除、覆盖未提交内容或自动推送远端。中断后按 [恢复流程](workflows/recovery.md) 恢复。

## 使用指令

先使用 [初始化提示词](prompts/initialize.md)，之后按 [阶段指令](prompts/README.md) 启动或继续。收到报告时核实测试命令、环境与 commit，而非只看完成百分比。若不能运行真实压力实验，P0 保留 BLOCKED；若无法人工试玩，相关质量项保留待确认。

官方配置参考（核对日期 2026-11-24）：
- https://developers.openai.com/codex/subagents/ — 原生子 Agent、项目角色文件及并发配置。
- https://developers.openai.com/codex/config-reference/ — 具体配置键、版本与兼容性。
- https://developers.openai.com/cookbook/examples/codex/iterating-development-workflows-with-codex — 仓库内持久化研发流程的参考。

本项目未在你的机器实际启动 Codex 或创建子 Agent；配置需经 P0-ENV 验证。
