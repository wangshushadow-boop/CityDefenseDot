# P2-FIELD-INTEGRATION-010

在基线 e1c7f95 验证编队 AI 的工作票据、已接受读数、重试和释放。`begin_tick` 保存同一步所需的原状态。`rollback_tick` 恢复已有实例与票据。`commit_tick` 释放撤销资料。

* `Godot --headless --path game --script res://tests/p2/formation_ai_transaction/run.gd` 退出 0。输出 `Formation AI tick transaction PASS`。
* `Godot --headless --path game --script res://tests/p2/formation_ai/run.gd` 退出 0。输出 `P2-BAI-F-001 PASS assertions=4877 failures=0`。

完整 Mission 组合撤销由 006 验证。
