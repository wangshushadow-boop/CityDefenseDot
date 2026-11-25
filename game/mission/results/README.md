# RESULTS · 野战结果

[模块规格](../../../docs/systems/game/mission/results/README.md) · [野战结果入口](ports/field_results.gd) · [Godot 回归入口](../../tests/p2/results/run.gd)

在 Mission 部署时打开结果追踪，将实际 COM 回执和当步 RULES 报告交给结果入口。Mission 通过事务钩子发布记录，并在结束屏障调用 `build_result`。
