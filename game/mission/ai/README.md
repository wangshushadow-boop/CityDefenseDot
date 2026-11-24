# game/mission/ai/

公共感知与调度的进程内入口见 [field_ai.gd](ports/field_ai.gd)。组合层注册权威快照并注入视线查询，再将已校验的意图交给所属领域。独立决策层使用只读感知和调度任务。

[权威模块设计](../../../docs/systems/game/mission/ai/README.md) · [Godot 集成和负载测试](../../tests/p2/ai/run.gd)
