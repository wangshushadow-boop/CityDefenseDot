# P2-FIELD-INTEGRATION-020 满载路径队列的同批交付

开发候选由 revision_fix 在 `p2-field-route-retention` 工作树实现，基线 `6887ebdad8e095f88f842b7bf4db51ab70774179`。模块 MOV，需求 BAI-06，阶段切片 T-TEST-01、T-MIS-RT-02。

500 人、1000 个预留槽的河原冲锋场景在第 4371 步失败，返回 `NotFound/path_ticket`。直控路径队列最多保留 128 个完成结果。同一步中，最老路径先命中，另一人请求新路径。新结果驱逐了最老结果，而移动系统在处理整批后才尝试领取两张票据。

`path_queue.gd` 增加内部的直控路径申请方法，申请时取出缓存命中的独立结果副本。未命中者仍由队列按预算求解。`field_movement.gd` 在同批导航修订一致时消费保留结果，其余情况使用原有核验票据流程。完成结果仍按 FIFO 驱逐，事务中不持有跨步豁免。每批保留的份数受原有直控上限约束，没有改变公共契约。

## 实测

在 Godot 4.7.2 Standard Windows console 使用 `--headless --path game --script res://tests/p2/<套件>/run.gd`。本机工作树的原始日志为 `out/retention/<运行名>/godot.log`。

| 运行名 | 套件 | 退出码 | 结果 |
|---|---|---|---|
| final-baseline | field_path_retention，相同测试脚本及修复前的 MOV | 1 | 153 个断言中 1 个失败。填满 128 条真实可达路径后，同一批两个驱动者触发 NotFound/path_ticket。 |
| fixed-full | field_path_retention | 0 | 167 项通过。两人同一步向前移动，回滚后两人恢复原位。原步重试后提交，总计仅做一次新几何查询，伪票和被淘汰的原票均被拒绝。 |
| movement | movement | 0 | 500/1000 人路径、动态连接、窄道、骑手及队列上限各项通过。 |
| move-intents | move_intents | 0 | 4541 项通过。两档负载全部移动，每步真实路径查询峰值 8。 |
| motion-batch | motion_batch | 0 | 3359 项通过。48 人窄道的 5 次下游回滚与对照产生 0 个分歧帧。 |
| 静态检查 | `python -B ci/gates.py dependencies` 与 `git diff --check` | 0 | 依赖及格式通过。 |

编写用例时，首版测试继承脚本无法编译，退出 1。重用已有测量器后改为独立入口。另一次夹具初始导航迭代尚无可达路径，在移动位移判据失败，退出 1。加入已有测试的真实可达性预热后，在基线及修复版原样复跑。

交付文件为以上两个 MOV 实现、`game/tests/p2/field_path_retention/run.gd` 与本报告。开发自测尚未复跑原第 4371 步的完整战场，交由阶段 QA 独立验证。
