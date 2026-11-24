# 可执行任务目录

按 `../task_graph.json` 的 PACKAGE 拆分具体 EXECUTION 任务。复制 `../../templates/task.json`，保存为 `<id>.json` 并登记在 `../../state/tasks.json`（仅主 Agent 写）。任务由具体 spec/验收/允许与排除路径/基线 commit/前置依赖确定，不使用父目录作为无限授权。执行任务的 parent 必须是工作包；不能把未细化工作包直接交给开发 Agent 写全模块。`python3 development/check_project.py` 检查 ID/依赖/路径和状态基础约束。

环境检查/报告/审批等非业务任务允许 `module_id: null`，`spec` 指向正式流程或总体设计；只能在主 Agent 显式批准的研发/实验路径工作，不用于跨模块业务修改。P0 实验用 `test_scenarios/p0/<task-id>/` 或 `native/benchmarks/p0/<task-id>/`，不把试验代码作为正式业务。具体执行任务在 READY 前须有真实基线 commit、工作目录、允许路径、适用测试/明确可执行验收及已完成前置。没有正式测试 ID 的技术任务使用具体报告/实验判据，不伪造游戏测试。

P0 已登记并结案 10 个执行任务。规格保存基线、当时的工作区及验收边界；状态与历史以 `development/state/tasks.json` 为准。

模块任务不得直接授权其他独立模块路径。公共契约由 CON 等所有者专门任务修改；跨模块设计和审批另建主控管理任务，具体资产、接口或测试变更按对应模块拆分。结构检查仅覆盖基本路径规则，审查时仍需检查实际 diff 与互斥锁。
