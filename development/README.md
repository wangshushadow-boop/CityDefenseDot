# recollection 研发执行体系

本目录补充游戏规格的执行层，不新增自研 Agent 调度服务。Codex 主 Agent 直接使用原生子 Agent（若环境不支持则顺序执行），用户按阶段授权；所有任务、依赖、结果和下一步保留在 Git 中。

- [使用指南](codex_setup.md) · [工作流](workflow.md) · [角色](agents/README.md) · [启动与阶段提示词](prompts/README.md)
- [阶段计划](planning/roadmap.md) · [工作包 DAG](planning/task_graph.json) · [模块所有权](planning/module_owners.json) · [具体任务](planning/tasks/README.md)
- [状态](state/README.md) · [模板](templates/README.md) · [证据](reports/README.md)

运行 `python3 development/check_project.py` 做结构、图和追踪检查；`python3 development/check_project.py --ready P0` 查看依赖满足的工作包（不启动任务）；`python3 development/check_diff.py --help` 查看候选 commit 写范围审查。检查脚本为轻量本地质量门禁，不代替真实游戏代码审查、测试、沙盒或 Codex 原生调度。
