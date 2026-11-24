# 通用阶段指令（替换 PHASE 与目标）

开始执行 PHASE 阶段：TARGET。以 docs/game_design.md 第23章、development/planning/roadmap.md 及对应 SDD 为依据。遵循 AGENTS.md，核对当前项目状态和上游门禁；拆分当前阶段为可验证任务，主动创建多个 Subagent 分批并行，明确写范围并隔离工作区，避免共享文件冲突。你作为主 Agent 负责公共接口协调、实际代码检查、独立 review/QA、问题修复、串行集成及最终测试验收。不能执行的测试真实标记 NOT_RUN/BLOCKED；未达到门禁不得标 DONE。记录任务、证据、状态和阶段报告。本阶段完成或需要重大批准/真实环境时停止，不自动进入下一阶段。
