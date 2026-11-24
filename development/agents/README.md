# 研发角色

主 Agent 在当前 Codex 窗口承担 Orchestrator，按实际工作需要使用其余角色；每个开发子 Agent 可以接不同模块任务，不需要 57 个常驻线程。角色文件是职责权威来源，`.codex/agents/*.toml` 只绑定角色，不重复定义完整流程。

- [orchestrator](orchestrator.md) — 主 Agent：阶段控制、任务分批、验收与状态
- [architect](architect.md) — 架构师：设计冲突、端口、冻结及 ADR
- [planner](planner.md) — 计划员：细化工作包、依赖与验收
- [developer](developer.md) — 开发者：指定模块实现与自测
- [reviewer](reviewer.md) — 审查员：独立审查 diff、架构、正确性与安全
- [qa](qa.md) — 测试员：独立验证、性能及验收证据
- [integration](integration.md) — 集成员：受控合并、全局验证和回滚
