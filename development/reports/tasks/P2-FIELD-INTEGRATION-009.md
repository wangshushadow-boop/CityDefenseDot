# P2-FIELD-INTEGRATION-009

在基线 e1c7f95 验证战术计划发布、撤销、过期授权和释放。`begin_tick` 保存同一步所需的原状态。`rollback_tick` 恢复已有实例与票据。`commit_tick` 释放撤销资料。

* `Godot --headless --path game --script res://tests/p2/tactics_transaction/run.gd` 退出 0。输出 `Tactics tick transaction PASS`。
* `Godot --headless --path game --script res://tests/p2/tactical/run.gd` 退出 0。输出 `FIELD_TACTICS errors=0 nav_queries=1576 physical_los=4593`。

完整 Mission 组合撤销由 006 验证。
