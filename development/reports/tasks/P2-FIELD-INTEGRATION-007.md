# P2-FIELD-INTEGRATION-007

在基线 e1c7f95 验证编队成员、槽位、控制修订和共享命令回执。`begin_tick` 保存同一步所需的原状态。`rollback_tick` 恢复已有实例与票据。`commit_tick` 释放撤销资料。

* `Godot --headless --path game --script res://tests/p2/formation_transaction/run.gd` 退出 0。输出 `Formation tick transaction PASS`。
* `Godot --headless --path game --script res://tests/p2/formation/run.gd` 退出 0。输出 `P2-FORM-001 PASS failures=0 reachable_slots=66499 seed=241124`。

最初测试向 hold 发送了未注册的完成条件 explicit，退出 1。改用已冻结的 executed 后重跑通过。完整 Mission 组合撤销由 006 验证。
