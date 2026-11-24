# game/presentation/input/

项目：`recollection`。模块：`INPUT`。

[野战输入节点](ports/field_input.gd) 接收 Godot 键鼠和手柄事件。装配方通过 `configure` 注入批量意图与编队订单的授权入口，通过 `bind_combat_view` 注入角色动作读模，按 Mission 固定步调用 `step`。相机将选取结果交给 `set_target`，HUD 可绑定 `feedback_changed` 或现有 Label。[本地绑定与设置](field_profile.gd) · [验收入口](../../tests/p2/input/run.gd) · [模块规格](../../../docs/systems/game/presentation/input/README.md)
